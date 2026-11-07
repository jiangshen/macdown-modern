import CYaml
import Foundation

public enum MarkdownRenderNotice: String, Sendable {
  case invalidFrontMatter, complexFrontMatter
}

/// Ordered, literal metadata. YAML aliases stay shared node references rather than
/// expanding an untrusted graph into exponentially many Swift objects.
public struct MarkdownFrontMatter: Sendable {
  public enum Value: Sendable {
    case scalar(String)
    case sequence([Int])
    case mapping([Entry])
  }
  public struct Entry: Sendable {
    public let key: Int
    public let value: Int
  }
  public let values: [Value]
  public let root: Int
  public let range: MarkdownSourceRange
  public let utf16Range: NSRange
  public let html: String

  struct Detection {
    var metadata: MarkdownFrontMatter?
    var notice: MarkdownRenderNotice?
    var maskedSource: String
  }

  private enum Failure: Error { case invalid, complexity }

  static func detect(in source: String) throws -> Detection {
    guard source.hasPrefix("---") || source.hasPrefix("\u{FEFF}---") else {
      return Detection(maskedSource: source)
    }
    let bytes = Array(source.utf8)
    var cursor = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
    func nextLine() -> (start: Int, end: Int, next: Int) {
      let start = cursor
      while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 13 { cursor += 1 }
      let end = cursor
      if cursor < bytes.count {
        if bytes[cursor] == 13, cursor + 1 < bytes.count, bytes[cursor + 1] == 10 { cursor += 1 }
        cursor += 1
      }
      return (start, end, cursor)
    }
    func delimiter(_ line: (start: Int, end: Int, next: Int), byte: UInt8) -> Bool {
      guard line.end - line.start >= 3,
        bytes[line.start..<line.start + 3].allSatisfy({ $0 == byte })
      else { return false }
      return bytes[line.start + 3..<line.end].allSatisfy { $0 == 32 || $0 == 9 }
    }
    let first = nextLine()
    guard delimiter(first, byte: 45), first.next > first.end else {
      return Detection(maskedSource: source)
    }
    let yamlStart = first.next
    var lineNumber = 1
    while cursor < bytes.count {
      if lineNumber.isMultiple(of: 256) { try Task.checkCancellation() }
      let line = nextLine()
      lineNumber += 1
      guard delimiter(line, byte: 45) || delimiter(line, byte: 46) else { continue }
      guard line.start - yamlStart <= 65_536 else {
        return Detection(notice: .complexFrontMatter, maskedSource: source)
      }
      do {
        let yaml = Array(bytes[yamlStart..<line.start])
        let (values, root) = try parse(yaml)
        let properties = try propertiesHTML(values: values, root: root)
        let range = MarkdownSourceRange(
          start: .init(line: 1, column: 1),
          end: .init(line: lineNumber, column: line.end - line.start))
        let prefix = String(decoding: bytes[..<line.next], as: UTF8.self)
        let metadata = Self(
          values: values, root: root, range: range,
          utf16Range: NSRange(location: 0, length: prefix.utf16.count),
          html:
            "<section class=\"md-frontmatter\" aria-label=\"Document properties\" data-sourcepos=\"1:1-\(lineNumber):\(line.end - line.start)\">"
            + properties + "</section>\n")
        var masked = bytes
        for offset in 0..<line.next where masked[offset] != 10 && masked[offset] != 13 {
          masked[offset] = 32
        }
        return Detection(metadata: metadata, maskedSource: String(decoding: masked, as: UTF8.self))
      } catch is CancellationError { throw CancellationError() } catch Failure.complexity {
        return Detection(notice: .complexFrontMatter, maskedSource: source)
      } catch { return Detection(notice: .invalidFrontMatter, maskedSource: source) }
    }
    return Detection(maskedSource: source)
  }

  /// The maintained Yams package supplies CYaml/libyaml's event parser. A bounded
  /// Swift composer keeps literal scalars, ordered pairs and shared alias references.
  private static func parse(_ bytes: [UInt8]) throws -> ([Value], Int) {
    var parser = yaml_parser_t()
    guard yaml_parser_initialize(&parser) != 0 else { throw Failure.invalid }
    defer { yaml_parser_delete(&parser) }
    return try bytes.withUnsafeBufferPointer { input in
      yaml_parser_set_input_string(&parser, input.baseAddress, input.count)
      struct Frame {
        let id: Int
        let mapping: Bool
        var children: [Int] = []
      }
      var values: [Value] = []
      var stack: [Frame] = []
      var anchors: [String: Int] = [:]
      var root: Int?
      var documents = 0
      var events = 0
      func attach(_ id: Int) throws {
        if !stack.isEmpty {
          stack[stack.count - 1].children.append(id)
        } else if root == nil {
          root = id
        } else {
          throw Failure.invalid
        }
      }
      func register(_ anchor: UnsafeMutablePointer<UInt8>?, id: Int) {
        if let anchor { anchors[String(cString: anchor)] = id }
      }
      var ended = false
      while !ended {
        try Task.checkCancellation()
        events += 1
        guard events <= 8_192, values.count <= 4_096, stack.count <= 32 else {
          throw Failure.complexity
        }
        var event = yaml_event_t()
        guard yaml_parser_parse(&parser, &event) != 0 else { throw Failure.invalid }
        defer { yaml_event_delete(&event) }
        switch event.type {
        case YAML_STREAM_START_EVENT: break
        case YAML_DOCUMENT_START_EVENT:
          documents += 1
          guard documents == 1 else { throw Failure.invalid }
        case YAML_SCALAR_EVENT:
          let scalar = event.data.scalar
          let id = values.count
          values.append(
            .scalar(
              String(
                decoding: UnsafeBufferPointer(start: scalar.value, count: scalar.length),
                as: UTF8.self)))
          try attach(id)
          register(scalar.anchor, id: id)
        case YAML_SEQUENCE_START_EVENT, YAML_MAPPING_START_EVENT:
          let id = values.count
          let mapping = event.type == YAML_MAPPING_START_EVENT
          values.append(mapping ? .mapping([]) : .sequence([]))
          try attach(id)
          register(
            mapping ? event.data.mapping_start.anchor : event.data.sequence_start.anchor, id: id)
          stack.append(Frame(id: id, mapping: mapping))
        case YAML_SEQUENCE_END_EVENT, YAML_MAPPING_END_EVENT:
          guard let frame = stack.popLast(), frame.mapping == (event.type == YAML_MAPPING_END_EVENT)
          else { throw Failure.invalid }
          if frame.mapping {
            guard frame.children.count.isMultiple(of: 2) else { throw Failure.invalid }
            values[frame.id] = .mapping(
              stride(from: 0, to: frame.children.count, by: 2).map {
                Entry(key: frame.children[$0], value: frame.children[$0 + 1])
              })
          } else {
            values[frame.id] = .sequence(frame.children)
          }
        case YAML_ALIAS_EVENT:
          guard let name = event.data.alias.anchor, let id = anchors[String(cString: name)] else {
            throw Failure.invalid
          }
          try attach(id)
        case YAML_DOCUMENT_END_EVENT:
          guard stack.isEmpty else { throw Failure.invalid }
        case YAML_STREAM_END_EVENT: ended = true
        default: throw Failure.invalid
        }
      }
      guard let root, documents == 1, stack.isEmpty else { throw Failure.invalid }
      return (values, root)
    }
  }

  private static func propertiesHTML(values: [Value], root: Int) throws -> String {
    var html = ""
    var bytes = 0
    var visited = 0
    func append(_ text: String) throws {
      bytes += text.utf8.count
      guard bytes <= 262_144 else { throw Failure.complexity }
      html += text
    }
    func render(_ id: Int, ancestors: Set<Int>) throws {
      try Task.checkCancellation()
      visited += 1
      guard visited <= 4_096, ancestors.count < 32, !ancestors.contains(id),
        values.indices.contains(id)
      else { throw Failure.complexity }
      var path = ancestors
      path.insert(id)
      switch values[id] {
      case .scalar(let value): try append(escape(value))
      case .sequence(let children):
        try append("<ul class=\"md-property-list\">")
        for child in children {
          try append("<li>")
          try render(child, ancestors: path)
          try append("</li>")
        }
        try append("</ul>")
      case .mapping(let entries):
        var keys = Set<String>()
        for entry in entries {
          guard values.indices.contains(entry.key) else { throw Failure.invalid }
          if case .scalar(let key) = values[entry.key], !keys.insert(key).inserted {
            throw Failure.invalid
          }
        }
        try append("<dl class=\"md-properties\">")
        for entry in entries {
          try append("<div class=\"md-property\"><dt>")
          try render(entry.key, ancestors: path)
          try append("</dt><dd>")
          try render(entry.value, ancestors: path)
          try append("</dd></div>")
        }
        try append("</dl>")
      }
    }
    try render(root, ancestors: [])
    return html
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
}
