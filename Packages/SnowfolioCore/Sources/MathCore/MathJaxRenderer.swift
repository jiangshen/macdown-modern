import Foundation
import JavaScriptCore

/// Actor-confined compatibility path. Only pinned library modules run in the
/// context; all document ordering, cancellation, limits and publication are Swift.
final class MathJaxRenderer {
  private var context: JSContext?
  private var adaptor: JSValue?

  func render(
    _ expressions: [MathExpression], consume: (Int, RenderedMath) throws -> Void
  ) throws {
    let context = try engine()
    guard let modules = context.objectForKeyedSubscript("SnowfolioMathJax") else {
      throw MathEngineError.engineFailed
    }
    guard let adaptor else { throw MathEngineError.engineFailed }
    let tex = try checked(context) {
      modules.forProperty("TeX")?.construct(withArguments: [
        [
          "packages": [
            "base", "ams", "newcommand", "bbox", "color", "cancel", "mathtools", "boldsymbol",
            "braket", "textmacros", "verb", "unicode", "extpfeil",
          ],
          "tags": "none", "maxBuffer": 16_384, "maxMacros": 1000,
        ]
      ])
    }
    let output = try checked(context) {
      modules.forProperty("SVG")?.construct(withArguments: [
        [
          "fontData": modules.forProperty("MathJaxTexFont") as Any, "fontCache": "none",
        ]
      ])
    }
    let document = try checked(context) {
      modules.forProperty("mathjax")?.invokeMethod(
        "document",
        withArguments: [
          "", ["InputJax": tex, "OutputJax": output],
        ])
    }
    let visitor = try checked(context) {
      modules.forProperty("SerializedMmlVisitor")?.construct(withArguments: [])
    }
    guard let constructor = document.forProperty("options")?.forProperty("MathItem"),
      let body = adaptor.invokeMethod(
        "body", withArguments: [document.forProperty("document") as Any])
    else { throw MathEngineError.engineFailed }
    var items = [JSValue?](repeating: nil, count: expressions.count)
    var issues = [MathRenderIssue?](repeating: nil, count: expressions.count)
    // Bound retained ASTs for the forward-reference pass independently of HTML
    // cache size. Released item roots do not accumulate during SVG publication.
    var remainingNodes = 500_000
    defer {
      tex.forProperty("parseOptions")?.setValue(nil, forProperty: "root")
      tex.setValue(nil, forProperty: "mathNode")
      for item in items.compactMap({ $0 }) {
        item.setValue(nil, forProperty: "root")
        item.setValue(nil, forProperty: "typesetRoot")
      }
    }
    for (index, expression) in expressions.enumerated() {
      try Task.checkCancellation()
      guard expression.isComplete else {
        issues[index] = .unsupportedExpression
        continue
      }
      guard expression.source.utf16.count <= 16_384, remainingNodes > 0 else {
        issues[index] = .expressionTooLarge
        continue
      }
      let item = try checked(context) {
        constructor.construct(withArguments: [expression.source, tex, expression.display])
      }
      item.forProperty("start")?.setValue(body, forProperty: "node")
      _ = try checked(context) { item.invokeMethod("setMetrics", withArguments: [16, 8, 1280, 1]) }
      _ = try checked(context) { document.invokeMethod("compileMath", withArguments: [item]) }
      if failed(item, tex: tex) {
        issues[index] = .unsupportedExpression
      } else if let root = item.forProperty("root"),
        try spendNodes(root, remaining: &remainingNodes)
      {
        items[index] = item
      } else {
        issues[index] = .expressionTooLarge
        item.setValue(nil, forProperty: "root")
        tex.forProperty("parseOptions")?.setValue(nil, forProperty: "root")
        tex.setValue(nil, forProperty: "mathNode")
      }
    }
    let namespace = "sfmath-" + UUID().uuidString.lowercased()
    for (index, expression) in expressions.enumerated() {
      try Task.checkCancellation()
      guard let item = items[index] else {
        try consume(
          index,
          MathRenderer.fallback(expression.source, issue: issues[index] ?? .unsupportedExpression))
        continue
      }
      // Same native second-compilation contract as MathDocument.compile(): all
      // labels exist before an earlier unresolved reference is compiled again.
      var recompiled = false
      if let data = item.forProperty("inputData")?.forProperty("recompile"), !data.isUndefined {
        _ = try checked(context) {
          item.invokeMethod("state", withArguments: [data.forProperty("state") as Any])
        }
        item.forProperty("inputData")?.setValue(data, forProperty: "recompile")
        _ = try checked(context) { document.invokeMethod("compileMath", withArguments: [item]) }
        recompiled = true
      }
      let result: RenderedMath
      if failed(item, tex: recompiled ? tex : nil) {
        result = MathRenderer.fallback(expression.source, issue: .unsupportedExpression)
      } else {
        _ = try checked(context) { item.invokeMethod("typeset", withArguments: [document]) }
        let svg = try checked(context) {
          adaptor.invokeMethod("innerHTML", withArguments: [item.forProperty("typesetRoot") as Any])
        }
        let mathml = try checked(context) {
          visitor.invokeMethod("visitTree", withArguments: [item.forProperty("root") as Any])
        }
        if (svg.forProperty("length")?.toInt32() ?? Int32.max) > 1_048_576
          || (mathml.forProperty("length")?.toInt32() ?? Int32.max) > 1_048_576
        {
          result = MathRenderer.fallback(expression.source, issue: .expressionTooLarge)
        } else if let svg = svg.toString(), let mathml = mathml.toString() {
          do {
            let html = try MathMarkup.html(
              svg: svg, mathml: mathml, source: expression.source, display: expression.display,
              namespace: namespace)
            result = RenderedMath(html: html, issue: nil)
          } catch is CancellationError { throw CancellationError() } catch MathMarkup.Failure
            .tooLarge
          { result = MathRenderer.fallback(expression.source, issue: .expressionTooLarge) } catch {
            result = MathRenderer.fallback(expression.source, issue: .unsupportedExpression)
          }
        } else {
          throw MathEngineError.engineFailed
        }
      }
      item.setValue(nil, forProperty: "root")
      item.setValue(nil, forProperty: "typesetRoot")
      items[index] = nil
      try consume(index, result)
    }
  }

  private func failed(_ item: JSValue, tex: JSValue?) -> Bool {
    let error = item.forProperty("inputData")?.forProperty("error")
    return tex?.forProperty("parseOptions")?.forProperty("error")?.toBool() == true
      || (error != nil && error?.isUndefined == false && error?.isNull == false)
  }

  private func spendNodes(_ root: JSValue, remaining: inout Int) throws -> Bool {
    var queue = [root]
    var cursor = 0
    while cursor < queue.count {
      if cursor.isMultiple(of: 256) { try Task.checkCancellation() }
      guard remaining > 0 else { return false }
      remaining -= 1
      let node = queue[cursor]
      cursor += 1
      if let children = node.forProperty("childNodes") {
        let count = children.forProperty("length")?.toInt32() ?? 0
        for index in 0..<max(0, count) {
          if let child = children.atIndex(Int(index)) { queue.append(child) }
        }
      }
    }
    return true
  }

  private func checked(_ context: JSContext, _ operation: () -> JSValue?) throws -> JSValue {
    context.exception = nil
    guard let value = operation(), context.exception == nil else {
      throw MathEngineError.engineFailed
    }
    return value
  }

  private func engine() throws -> JSContext {
    if let context { return context }
    guard let url = Bundle.module.url(forResource: "MathJax4", withExtension: "js"),
      let context = JSContext()
    else { throw MathEngineError.missingResources }
    context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
    guard context.exception == nil,
      context.objectForKeyedSubscript("SnowfolioMathJax")?.isObject == true
    else { throw MathEngineError.engineFailed }
    guard let modules = context.objectForKeyedSubscript("SnowfolioMathJax") else {
      throw MathEngineError.engineFailed
    }
    let adaptor = try checked(context) {
      modules.invokeMethod("liteAdaptor", withArguments: [["fontSize": 16]])
    }
    _ = try checked(context) {
      modules.invokeMethod("RegisterHTMLHandler", withArguments: [adaptor])
    }
    self.adaptor = adaptor
    self.context = context
    return context
  }
}
