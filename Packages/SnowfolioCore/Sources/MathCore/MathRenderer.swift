import Foundation
import JavaScriptCore

public enum MathEngineError: Error, Sendable { case missingResources, engineFailed }
public enum MathRenderIssue: Sendable { case unsupportedExpression, expressionTooLarge }

public struct RenderedMath: Sendable {
  public let html: String
  public let issue: MathRenderIssue?
}

public struct MathExpression: Hashable, Sendable {
  public let source: String
  public let display: Bool

  public init(_ source: String, display: Bool) {
    self.source = source
    self.display = display
  }

  // TeX annotations preserve authored bytes, including canonically equivalent
  // Unicode spellings. String's normal equality would merge those cache keys.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.display == rhs.display && lhs.source.utf8.elementsEqual(rhs.source.utf8)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(display)
    var text = source
    text.withUTF8 { bytes in
      hasher.combine(bytes.count)
      hasher.combine(bytes: UnsafeRawBufferPointer(bytes))
    }
  }
}

/// Actor-confined, with no native, DOM, file or network bindings exposed to TeX.
/// Only pinned bundled code runs; expressions are passed as JavaScript values.
public final class MathRenderer {
  private enum CacheScope: Hashable { case standalone, document, emptyDefinitions }
  private struct CacheKey: Hashable {
    let expressions: [MathExpression]
    let scope: CacheScope
  }

  private var context: JSContext?
  private var cache: [CacheKey: [RenderedMath]] = [:]
  private var cacheBytes = 0
  public init() {}

  /// Standalone expressions cannot change definitions used by another call.
  public func render(_ source: String, display: Bool) throws -> RenderedMath {
    try Task.checkCancellation()
    guard source.utf16.count <= 16_384 else {
      return Self.fallback(source, issue: .expressionTooLarge)
    }
    var rendered: RenderedMath?
    try render([MathExpression(source, display: display)], documentDefinitions: false) { _, value in
      rendered = value
    }
    guard let rendered else { throw MathEngineError.engineFailed }
    return rendered
  }

  /// Definitions follow source order within this batch and expire at its end.
  /// Caching the whole batch preserves definition side effects and dependencies.
  public func renderDocument(_ expressions: [MathExpression]) throws -> [RenderedMath] {
    var results: [RenderedMath] = []
    try renderDocument(expressions) { _, result in results.append(result) }
    return results
  }

  /// Streams larger documents without retaining every rendered formula twice.
  public func renderDocument(
    _ expressions: [MathExpression], consume: (Int, RenderedMath) throws -> Void
  ) throws {
    try render(expressions, documentDefinitions: true, consume: consume)
  }

  private func render(
    _ expressions: [MathExpression], documentDefinitions: Bool,
    consume: (Int, RenderedMath) throws -> Void
  ) throws {
    try Task.checkCancellation()
    guard !expressions.isEmpty else { return }
    let key = CacheKey(
      expressions: expressions, scope: documentDefinitions ? .document : .standalone)
    if let cached = cache[key] {
      for (index, result) in cached.enumerated() {
        try Task.checkCancellation()
        try consume(index, result)
      }
      return
    }
    var macros: JSValue?
    var results: [RenderedMath]? = []
    var retainedCost = expressions.reduce(0) { $0 + $1.source.utf8.count }
    if retainedCost > 2_097_152 { results = nil }
    func emit(_ result: RenderedMath, at index: Int) throws {
      if results != nil {
        retainedCost += result.html.utf8.count
        if retainedCost > 2_097_152 {
          results = nil
        } else {
          results?.append(result)
        }
      }
      try consume(index, result)
    }
    var hasDefinitions = false
    for (index, expression) in expressions.enumerated() {
      try Task.checkCancellation()
      let pureKey = CacheKey(expressions: [expression], scope: .emptyDefinitions)
      if documentDefinitions, !hasDefinitions, let cached = cache[pureKey]?.first {
        try emit(cached, at: index)
        continue
      }
      let result: RenderedMath
      if expression.source.utf16.count > 16_384 {
        result = Self.fallback(expression.source, issue: .expressionTooLarge)
      } else {
        let context = try engine()
        if macros == nil { macros = JSValue(newObjectIn: context) }
        guard let macros else { throw MathEngineError.engineFailed }
        context.exception = nil
        let value = context.objectForKeyedSubscript("katex")?.invokeMethod(
          "renderToString",
          withArguments: [
            expression.source,
            [
              "displayMode": expression.display, "output": "htmlAndMathml", "throwOnError": true,
              "trust": false, "strict": "ignore", "maxExpand": 1000, "maxSize": 20,
              "macros": macros, "globalGroup": documentDefinitions,
            ],
          ])
        if context.exception != nil {
          context.exception = nil
          result = Self.fallback(expression.source, issue: .unsupportedExpression)
        } else if let value, value.isString, let html = value.toString(),
          html.utf8.count <= 1_048_576
        {
          result = RenderedMath(html: html, issue: nil)
        } else {
          result = Self.fallback(expression.source, issue: .expressionTooLarge)
        }
        if documentDefinitions, !hasDefinitions {
          // Only formulas observed to leave an empty definition table are safe
          // to reuse independently. Definitions themselves always execute.
          let count = context.objectForKeyedSubscript("Object")?.invokeMethod(
            "keys", withArguments: [macros])?.forProperty("length")
          hasDefinitions = count?.isNumber != true || count?.toInt32() != 0
        }
      }
      try emit(result, at: index)
      if documentDefinitions, !hasDefinitions { store([result], for: pureKey) }
    }
    try Task.checkCancellation()
    if let results { store(results, for: key) }
  }

  private func store(_ results: [RenderedMath], for key: CacheKey) {
    var cost = 0
    for expression in key.expressions {
      cost += expression.source.utf8.count
      if cost > 2_097_152 { return }
    }
    for result in results {
      cost += result.html.utf8.count
      if cost > 2_097_152 { return }
    }
    if cost <= 2_097_152 {
      if cache.count >= 64 || cacheBytes + cost > 2_097_152 {
        cache.removeAll(keepingCapacity: true)
        cacheBytes = 0
      }
      cache[key] = results
      cacheBytes += cost
    }
  }

  private func engine() throws -> JSContext {
    if let context { return context }
    guard !MathStyle.css.isEmpty,
      let url = Bundle.module.url(forResource: "KaTeX", withExtension: "js"),
      let context = JSContext()
    else { throw MathEngineError.missingResources }
    context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
    guard context.exception == nil,
      context.objectForKeyedSubscript("katex")?.isObject == true
    else { throw MathEngineError.engineFailed }
    self.context = context
    return context
  }

  private static func fallback(_ source: String, issue: MathRenderIssue) -> RenderedMath {
    let escaped = source.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
    return RenderedMath(html: "<code class=\"math-error\">" + escaped + "</code>", issue: issue)
  }
}

public enum MathStyle {
  public static let layoutCSS: String = {
    guard let regex = try? NSRegularExpression(pattern: "@font-face\\s*\\{[^}]*\\}") else {
      return css
    }
    return regex.stringByReplacingMatches(
      in: css,
      range: NSRange(location: 0, length: (css as NSString).length), withTemplate: "")
  }()

  /// Includes the release's original WOFF2 fonts as data URLs for offline exports.
  public static let css: String = {
    guard let url = Bundle.module.url(forResource: "KaTeX", withExtension: "css"),
      let css = try? String(contentsOf: url, encoding: .utf8),
      let licenseURL = Bundle.module.url(forResource: "KaTeX-LICENSE", withExtension: "txt"),
      let license = try? String(contentsOf: licenseURL, encoding: .utf8)
    else { return "" }
    // Exporting embedded fonts also carries their original distribution notice.
    return "/*\n" + license.replacingOccurrences(of: "*/", with: "* /") + "\n*/\n" + css
      + "\n.md-math{max-width:100%;}.md-math-display{display:block;overflow-x:auto;overflow-y:hidden;padding:.4em 0;}.math-error{white-space:pre-wrap;color:inherit;}.md-math:has(.katex-html:empty){display:none;}"
  }()
}
