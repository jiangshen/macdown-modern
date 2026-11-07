import Foundation

/// Compatibility for the bundled Handlebars context. This deliberately recognizes
/// the observed value/each grammar; helpers, partials and unknown paths are errors.
/// It never evaluates code, reads properties dynamically or executes page scripts.
public struct LegacyHTMLTemplate: Sendable {
  public enum Failure: Error, Equatable, Sendable {
    case tooLarge, invalidEncoding, unsupportedExpression, malformedBlock, outputTooLarge
  }
  public struct Context: Sendable {
    public let title: String
    public let titleTag: String
    public let body: String
    public let styleTags: [String]
    public let scriptTags: [String]

    public init(title: String, body: String, styleTags: [String] = [], scriptTags: [String] = []) {
      self.title = title
      titleTag = title.isEmpty ? "" : "<title>" + Self.escape(title) + "</title>"
      self.body = body
      self.styleTags = styleTags
      self.scriptTags = scriptTags
    }

    fileprivate static func escape(_ value: String) -> String {
      value.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
        .replacingOccurrences(of: "`", with: "&#96;")
        .replacingOccurrences(of: "=", with: "&#61;")
    }
  }

  public static let maximumSourceBytes = 65_536
  public static let maximumOutputBytes = 256 * 1_048_576
  private enum Field: String, Sendable { case title, titleTag, body, this }
  private enum Collection: String, Sendable { case styleTags, scriptTags }
  private indirect enum Node: Sendable {
    case literal(String)
    case value(Field, escaped: Bool)
    case each(Collection, [Node])
  }
  private let nodes: [Node]

  public init(data: Data) throws {
    guard data.count <= Self.maximumSourceBytes else { throw Failure.tooLarge }
    guard let source = String(data: data, encoding: .utf8) else { throw Failure.invalidEncoding }
    var parser = Parser(source: source)
    nodes = try parser.parse(inLoop: false)
  }

  public func render(_ context: Context, maximumBytes: Int = Self.maximumOutputBytes) throws
    -> String
  {
    try Task.checkCancellation()
    var writer = Writer(
      context: context, maximumBytes: min(Self.maximumOutputBytes, max(0, maximumBytes)))
    try writer.write(nodes, item: nil)
    return writer.output
  }

  private struct Parser {
    let source: String
    var offset: String.Index
    var count = 0
    init(source: String) {
      self.source = source
      offset = source.startIndex
    }

    mutating func parse(inLoop: Bool) throws -> [Node] {
      var nodes: [Node] = []
      while offset < source.endIndex {
        guard let start = source.range(of: "{{", range: offset..<source.endIndex) else {
          nodes.append(.literal(String(source[offset...])))
          offset = source.endIndex
          break
        }
        nodes.append(.literal(String(source[offset..<start.lowerBound])))
        let raw = source[start.lowerBound...].hasPrefix("{{{")
        let opening = source.index(start.lowerBound, offsetBy: raw ? 3 : 2)
        let closing = raw ? "}}}" : "}}"
        guard let end = source.range(of: closing, range: opening..<source.endIndex) else {
          throw Failure.malformedBlock
        }
        let expression = source[opening..<end.lowerBound].trimmingCharacters(
          in: .whitespacesAndNewlines)
        offset = end.upperBound
        count += 1
        guard count <= 2048 else { throw Failure.tooLarge }
        if expression == "/each" {
          guard inLoop, !raw else { throw Failure.malformedBlock }
          return nodes
        }
        if expression.hasPrefix("#each") {
          guard !raw, !inLoop else { throw Failure.unsupportedExpression }
          let parts = expression.split(whereSeparator: \.isWhitespace)
          guard parts.count == 2, parts[0] == "#each",
            let collection = Collection(rawValue: String(parts[1]))
          else {
            throw Failure.unsupportedExpression
          }
          nodes.append(.each(collection, try parse(inLoop: true)))
        } else {
          guard let field = Field(rawValue: expression), inLoop ? field == .this : field != .this
          else {
            throw Failure.unsupportedExpression
          }
          nodes.append(.value(field, escaped: !raw))
        }
      }
      guard !inLoop else { throw Failure.malformedBlock }
      return nodes
    }
  }

  private struct Writer {
    let context: Context
    let maximumBytes: Int
    var output = ""
    var bytes = 0

    mutating func append(_ value: String) throws {
      try Task.checkCancellation()
      let size = value.utf8.count
      guard size <= maximumBytes - bytes else { throw Failure.outputTooLarge }
      output += value
      bytes += size
    }

    mutating func appendEscaped(_ value: String) throws {
      var start = value.startIndex
      var count = 0
      for index in value.unicodeScalars.indices {
        count += 1
        if count % 4096 == 0 { try Task.checkCancellation() }
        let replacement: String
        switch value.unicodeScalars[index].value {
        case 38: replacement = "&amp;"
        case 60: replacement = "&lt;"
        case 62: replacement = "&gt;"
        case 34: replacement = "&quot;"
        case 39: replacement = "&#39;"
        case 96: replacement = "&#96;"
        case 61: replacement = "&#61;"
        default: continue
        }
        try append(String(value[start..<index]))
        try append(replacement)
        start = value.unicodeScalars.index(after: index)
      }
      try append(String(value[start...]))
    }

    mutating func write(_ nodes: [Node], item: String?) throws {
      for node in nodes {
        switch node {
        case .literal(let value): try append(value)
        case .value(let field, let escaped):
          let value: String
          switch field {
          case .title: value = context.title
          case .titleTag: value = context.titleTag
          case .body: value = context.body
          case .this: value = item ?? ""
          }
          if escaped { try appendEscaped(value) } else { try append(value) }
        case .each(let collection, let children):
          let values = collection == .styleTags ? context.styleTags : context.scriptTags
          for value in values { try write(children, item: value) }
        }
      }
    }
  }
}
