import Foundation
import JavaScriptCore

public enum CodeHighlightError: Error, Sendable { case missingResources, engineFailed }

public struct HighlightedCode: Sendable {
  public let language: String
  public let html: String
}

/// Non-Sendable by design: create and retain inside one parser actor. No JSContext
/// or JSValue escapes this object, and document text is passed only as a value.
public final class CodeHighlighter {
  private let languages: [String: String]
  private var context: JSContext?
  private var cache: [String: HighlightedCode] = [:]
  private var cacheBytes = 0

  public init() throws {
    guard let url = Bundle.module.url(forResource: "Languages", withExtension: "json") else {
      throw CodeHighlightError.missingResources
    }
    var names = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    // Preserve MacDown aliases in addition to the release's complete alias catalog.
    for (alias, language) in [
      "jl": "julia", "c++": "cpp", "coffee-script": "coffeescript", "objective-c": "objectivec",
      "obj-c": "objectivec", "graphviz": "dot", "gv": "dot",
    ] {
      names[alias] = language
    }
    languages = names
  }

  public var supportedLanguages: [String] { Set(languages.values).sorted() }

  public func highlight(_ source: String, language info: String) throws -> HighlightedCode? {
    try Task.checkCancellation()
    guard let name = info.split(whereSeparator: \.isWhitespace).first?.lowercased(),
      let language = languages[name], !source.isEmpty,
      source.utf16.count <= 65_536
    else { return nil }
    let key = language + "\u{0}" + source
    if let cached = cache[key] { return cached }
    let context = try engine()
    guard let prism = context.objectForKeyedSubscript("Prism"),
      let grammar = prism.objectForKeyedSubscript("languages")?.objectForKeyedSubscript(language),
      !grammar.isUndefined, !grammar.isNull
    else { throw CodeHighlightError.engineFailed }
    context.exception = nil
    let value = prism.invokeMethod("highlight", withArguments: [source, grammar, language])
    guard context.exception == nil, let value, value.isString, let html = value.toString() else {
      context.exception = nil
      throw CodeHighlightError.engineFailed
    }
    try Task.checkCancellation()
    let result = HighlightedCode(language: language, html: html)
    let cost = key.utf8.count + html.utf8.count
    if cost <= 1_048_576 {
      if cache.count >= 32 || cacheBytes + cost > 1_048_576 {
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
    guard let url = Bundle.module.url(forResource: "Prism", withExtension: "js"),
      let context = JSContext()
    else { throw CodeHighlightError.missingResources }
    // Only checksum-pinned bundled grammar code is evaluated. The context exposes
    // no file/network/DOM/native bridge; Markdown can never supply executable code.
    context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
    guard context.exception == nil else { throw CodeHighlightError.engineFailed }
    self.context = context
    return context
  }
}
