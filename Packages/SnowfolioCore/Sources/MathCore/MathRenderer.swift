import Foundation
import JavaScriptCore

public enum MathEngineError: Error, Sendable { case missingResources, engineFailed }
public enum MathRenderIssue: Sendable { case unsupportedExpression, expressionTooLarge }

public struct RenderedMath: Sendable {
  public let html: String
  public let issue: MathRenderIssue?
}

/// Actor-confined, with no native, DOM, file or network bindings exposed to TeX.
/// Only pinned bundled code runs; expressions are passed as JavaScript values.
public final class MathRenderer {
  private var context: JSContext?
  private var cache: [String: RenderedMath] = [:]
  private var cacheBytes = 0
  public init() {}

  public func render(_ source: String, display: Bool) throws -> RenderedMath {
    try Task.checkCancellation()
    guard source.utf16.count <= 16_384 else {
      return Self.fallback(source, issue: .expressionTooLarge)
    }
    let key = (display ? "display:" : "inline:") + source
    if let cached = cache[key] { return cached }
    let context = try engine()
    context.exception = nil
    let value = context.objectForKeyedSubscript("katex")?.invokeMethod(
      "renderToString",
      withArguments: [
        source,
        [
          "displayMode": display, "output": "htmlAndMathml", "throwOnError": true,
          "trust": false, "strict": "ignore", "maxExpand": 1000, "maxSize": 20,
          // No expression can redefine the macros used by a different document.
          "macros": [String: String](),
        ],
      ])
    let result: RenderedMath
    if context.exception != nil {
      context.exception = nil
      result = Self.fallback(source, issue: .unsupportedExpression)
    } else if let value, value.isString, let html = value.toString(), html.utf8.count <= 1_048_576 {
      result = RenderedMath(html: html, issue: nil)
    } else {
      result = Self.fallback(source, issue: .expressionTooLarge)
    }
    try Task.checkCancellation()
    let cost = key.utf8.count + result.html.utf8.count
    if cost <= 2_097_152 {
      if cache.count >= 64 || cacheBytes + cost > 2_097_152 {
        cache.removeAll(keepingCapacity: true)
        cacheBytes = 0
      }
      cache[key] = result
      cacheBytes += cost
    }
    return result
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
  /// Includes the release's original WOFF2 fonts as data URLs for offline exports.
  public static let css: String = {
    guard let url = Bundle.module.url(forResource: "KaTeX", withExtension: "css"),
      let css = try? String(contentsOf: url, encoding: .utf8),
      let licenseURL = Bundle.module.url(forResource: "KaTeX-LICENSE", withExtension: "txt"),
      let license = try? String(contentsOf: licenseURL, encoding: .utf8)
    else { return "" }
    // Exporting embedded fonts also carries their original distribution notice.
    return "/*\n" + license.replacingOccurrences(of: "*/", with: "* /") + "\n*/\n" + css
      + "\n.md-math{max-width:100%;}.md-math-display{display:block;overflow-x:auto;overflow-y:hidden;padding:.4em 0;}.math-error{white-space:pre-wrap;color:inherit;}"
  }()
}
