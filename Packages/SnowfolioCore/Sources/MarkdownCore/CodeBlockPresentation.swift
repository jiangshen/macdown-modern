import CodeHighlightCore
import Foundation

/// Fence metadata comes from cmark's AST, never a second Markdown parser.
struct CodeFenceInformation {
  let language: String
  let customLabel: String?

  init(_ information: String, accessory: CodeBlockAccessory) {
    var language = information
    var label: String?
    if accessory == .custom, let colon = information.firstIndex(of: ":") {
      language = String(information[..<colon])
      let value = String(information[information.index(after: colon)...])
      if !value.isEmpty { label = value }
    }
    self.language = language.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
    customLabel = label
  }
}

struct CodeBlockPresentation {
  let html: String
  let decorated: Bool
  let limited: Bool

  init(
    source: String, highlighted: HighlightedCode?, information: CodeFenceInformation,
    label: String?, lineNumbers: Bool, position: String
  ) throws {
    let numbered =
      lineNumbers ? try CodeLineMarkup.numbered(source, highlighted: highlighted?.html) : nil
    decorated = numbered != nil || label != nil
    limited = lineNumbers && numbered == nil && !source.isEmpty
    guard highlighted != nil || decorated else {
      html = ""
      return
    }
    let language = highlighted?.language ?? information.language
    let className = language.isEmpty ? "" : " class=\"language-" + Self.escape(language) + "\""
    let custom =
      information.customLabel.map { " data-information=\"" + Self.escape($0) + "\"" } ?? ""
    let numberFlag = numbered == nil ? "" : " data-code-numbered=\"true\""
    let highlightFlag = highlighted == nil ? "" : " data-code-highlighted=\"true\""
    let code = numbered ?? highlighted?.html ?? Self.escape(source)
    let pre =
      "<pre data-sourcepos=\"" + position + "\"" + className + custom + numberFlag + highlightFlag
      + "><code" + className + ">" + code + "</code></pre>"
    if let label {
      html =
        "<div class=\"md-code-block\"><div class=\"md-code-label\">" + Self.escape(label) + "</div>"
        + pre + "</div>"
    } else {
      html = pre
    }
  }

  private static func escape(_ value: String) -> String { MarkdownFrontMatter.escape(value) }
}

/// Splits only the pinned highlighter's generated span markup, retaining nested
/// token attributes across newlines. Plain blocks need no markup parser. Code,
/// selection text and terminal newlines remain exact; numbering has no DOM text.
private enum CodeLineMarkup {
  static let maximumSourceBytes = 1_048_576
  static let maximumRows = 10_000
  static let maximumOutputBytes = 8 * 1_048_576

  static func numbered(_ source: String, highlighted: String?) throws -> String? {
    guard !source.isEmpty, source.utf8.count <= maximumSourceBytes else { return nil }
    let rows = source.split(separator: "\n", omittingEmptySubsequences: false)
    let terminal = source.hasSuffix("\n")
    let count = rows.count - (terminal ? 1 : 0)
    guard count <= maximumRows else { return nil }
    let lines: [String]
    if let highlighted {
      guard highlighted.utf8.count <= 4 * 1_048_576 else { return nil }
      var reader = SpanReader()
      guard let parsed = try reader.read(highlighted) else { return nil }
      lines = parsed
      guard lines.count == rows.count else { return nil }
    } else {
      lines = rows.map { MarkdownFrontMatter.escape(String($0)) }
    }
    let digits = String(count).count
    var output = ""
    var bytes = 0
    for index in 0..<count {
      try Task.checkCancellation()
      let line =
        "<span class=\"md-code-line\" style=\"--md-code-gutter:" + String(digits + 2)
        + "ch\"><span class=\"md-code-number\" data-line=\"" + String(index + 1)
        + "\" aria-hidden=\"true\"></span>" + lines[index] + "</span>"
        + (index + 1 < count || terminal ? "\n" : "")
      guard line.utf8.count <= maximumOutputBytes - bytes else { return nil }
      output += line
      bytes += line.utf8.count
    }
    return output
  }

  /// Prism emits only span envelopes. Preserve their bytes (including HTML
  /// entities in attributes) while balancing that small, trusted vocabulary.
  /// This is neither a Markdown parser nor a general document HTML parser.
  private struct SpanReader {
    private var lines: [String] = []
    private var current = ""
    private var tags: [String] = []
    private var bytes = 0

    private mutating func append(_ value: String) -> Bool {
      let size = value.utf8.count
      guard size <= maximumOutputBytes - bytes else { return false }
      current += value
      bytes += size
      return true
    }

    private mutating func text(_ value: Substring) throws -> Bool {
      for (index, part) in value.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
      {
        try Task.checkCancellation()
        if index > 0 {
          guard append(String(repeating: "</span>", count: tags.count)) else { return false }
          lines.append(current)
          current = ""
          guard append(tags.joined()) else { return false }
        }
        guard append(String(part)) else { return false }
      }
      return true
    }

    mutating func read(_ html: String) throws -> [String]? {
      var cursor = html.startIndex
      while cursor < html.endIndex {
        try Task.checkCancellation()
        guard let start = html[cursor...].firstIndex(of: "<") else {
          guard try text(html[cursor...]) else { return nil }
          cursor = html.endIndex
          break
        }
        guard try text(html[cursor..<start]) else { return nil }
        if html[start...].hasPrefix("</span>") {
          guard !tags.isEmpty, append("</span>") else { return nil }
          tags.removeLast()
          cursor = html.index(start, offsetBy: 7)
        } else {
          guard html[start...].hasPrefix("<span"), tags.count < 64 else { return nil }
          let afterName = html.index(start, offsetBy: 5)
          guard afterName < html.endIndex,
            html[afterName] == ">" || html[afterName].isWhitespace,
            let end = Self.tagEnd(html, from: afterName)
          else { return nil }
          let opening = String(html[start...end])
          guard !opening.hasSuffix("/>"), append(opening) else { return nil }
          tags.append(opening)
          cursor = html.index(after: end)
        }
      }
      guard tags.isEmpty else { return nil }
      return lines + [current]
    }

    private static func tagEnd(_ html: String, from start: String.Index) -> String.Index? {
      var quote: Character?
      for index in html[start...].indices {
        let character = html[index]
        if let active = quote {
          if character == active { quote = nil }
        } else if character == "\"" || character == "'" {
          quote = character
        } else if character == ">" {
          return index
        }
      }
      return nil
    }
  }
}
