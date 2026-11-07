import Foundation

/// A data-only representation of the original .style format. AppKit maps these
/// values to presentation attributes; parsing never touches a document or font.
/// Grammar compatibility: PEG Markdown Highlight (Ali Rantakari, MIT option;
/// complete notice retained in App/Resources/Licenses/peg-markdown-highlight.txt).
public struct EditorTheme: Equatable, Sendable {
  public struct Color: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8
    public let alpha: UInt8
  }

  public struct FontSize: Equatable, Sendable {
    public let points: Int
    public let relative: Bool
  }

  public struct FontStyle: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let bold = Self(rawValue: 1)
    public static let italic = Self(rawValue: 2)
    public static let underlined = Self(rawValue: 4)
  }

  public enum Value: Equatable, Sendable {
    case color(Color)
    case fontSize(FontSize)
    case fontFamily(String)
    case fontStyle(FontStyle)
    case custom(String)
  }

  public struct Attribute: Equatable, Sendable {
    public let name: String
    public let value: Value
  }

  public struct Rule: Equatable, Sendable {
    public let selector: String
    /// Source order, including duplicates. The original AppKit adapter gives
    /// the first repeated scalar attribute priority and combines font traits.
    public let attributes: [Attribute]
  }

  public struct Diagnostic: Equatable, Sendable {
    public let line: Int
    public let message: String
  }

  public let rules: [Rule]
  public let diagnostics: [Diagnostic]

  public enum ParseError: Error, Equatable {
    case tooLarge, containsNul, tooComplex
  }

  private static let asciiWhitespace = CharacterSet(charactersIn: " \t\r\n\u{0B}\u{0C}")

  public static let maximumBytes = 1_048_576
  public static let selectors: Set<String> = [
    "editor", "editor-current-line", "editor-selection", "LINK", "AUTO_LINK_URL", "AUTO_LINK_EMAIL",
    "IMAGE", "CODE", "HTML", "HTML_ENTITY", "EMPH", "STRONG", "LIST_BULLET", "LIST_ENUMERATOR",
    "COMMENT", "H1", "H2", "H3", "H4", "H5", "H6", "BLOCKQUOTE", "VERBATIM", "HTMLBLOCK",
    "HRULE", "REFERENCE", "NOTE",
  ]

  public static func parse(_ source: String) throws -> Self {
    guard source.utf8.count <= maximumBytes else { throw ParseError.tooLarge }
    guard !source.utf8.contains(0) else { throw ParseError.containsNul }
    var text = source
    if text.first == "\u{FEFF}" { text.removeFirst() }
    text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
      of: "\r", with: "\n")
    var rules: [Rule] = []
    var diagnostics: [Diagnostic] = []
    var declared = false
    var declarationCount = 0
    var blockCount = 0
    var selector: String?
    var attributes: [Attribute] = []
    func diagnose(_ line: Int, _ message: String) {
      if diagnostics.count < 256 { diagnostics.append(.init(line: line, message: message)) }
    }
    func finish() {
      guard let selector, declared else { return }
      if selector.hasPrefix("editor") { rules.removeAll { $0.selector == selector } }
      // An invalid-only special rule still replaces the preceding rule, as in
      // the original parser. Keep its empty attribute collection explicitly.
      rules.append(Rule(selector: selector, attributes: attributes))
    }
    for (index, rawLine) in text.components(separatedBy: "\n").enumerated() {
      let number = index + 1
      let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
      if line.isEmpty {
        finish()
        selector = nil
        attributes = []
        declared = false
        continue
      }
      if line.hasPrefix("#") { continue }
      if selector == nil {
        blockCount += 1
        guard blockCount <= 4096 else { throw ParseError.tooComplex }
        let header = line.trimmingCharacters(in: Self.asciiWhitespace)
        let name = String(
          header.prefix {
            !" \t\r\n\u{0B}\u{0C}".contains($0) && $0 != "#" && $0 != ":" && $0 != "="
          })
        // Keep an unknown block separate from the following block. Its content
        // must never accidentally become attributes of a valid selector.
        selector = name
        if !selectors.contains(name) { diagnose(number, "Unknown style rule: \(name)") }
        continue
      }
      let declaration = line.prefix { $0 != "#" }
      guard let separator = declaration.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
        diagnose(number, "Expected an attribute followed by : or =")
        continue
      }
      let name = String(declaration[..<separator]).trimmingCharacters(in: Self.asciiWhitespace)
      let value = String(declaration[declaration.index(after: separator)...])
        .trimmingCharacters(in: Self.asciiWhitespace)
      guard !name.isEmpty, !value.isEmpty else {
        diagnose(number, "An attribute name and value are required")
        continue
      }
      declared = true
      declarationCount += 1
      guard declarationCount <= 16384 else { throw ParseError.tooComplex }
      guard let parsed = attribute(name, value: value, report: { diagnose(number, $0) }) else {
        continue
      }
      attributes.append(parsed)
    }
    finish()
    return Self(rules: rules.filter { selectors.contains($0.selector) }, diagnostics: diagnostics)
  }

  private static func attribute(
    _ name: String, value: String, report: (String) -> Void
  ) -> Attribute? {
    let canonical: String
    let parsed: Value
    switch name {
    case "color", "foreground", "foreground-color", "background", "background-color", "caret",
      "caret-color":
      canonical =
        name == "color" || name.hasPrefix("foreground")
        ? "foreground-color"
        : name.hasPrefix("background") ? "background-color" : "caret-color"
      guard value.utf8.count == 6 || value.utf8.count == 8,
        value.utf8.allSatisfy({
          (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }),
        let hex = UInt32(value, radix: 16)
      else {
        report("Expected a six-digit RGB or eight-digit ARGB color")
        return nil
      }
      parsed = .color(
        .init(
          red: UInt8((hex >> 16) & 255), green: UInt8((hex >> 8) & 255),
          blue: UInt8(hex & 255), alpha: value.utf8.count == 8 ? UInt8(hex >> 24) : 255))
    case "font-size":
      canonical = name
      var prefix = value[...]
      let relative = prefix.first == "+" || prefix.first == "-"
      if relative { prefix.removeFirst() }
      let digits = prefix.prefix { $0.isASCII && $0.isNumber }
      guard !digits.isEmpty, let amount = Int((value.first == "-" ? "-" : "") + String(digits)),
        (-4096...4096).contains(amount)
      else {
        report("Font size must begin with an integer between -4096 and 4096")
        return nil
      }
      // Historical px/pt suffixes both represent points. Retain that choice.
      parsed = .fontSize(.init(points: amount, relative: relative))
    case "font-family":
      canonical = name
      parsed = .fontFamily(value)
    case "font-style":
      canonical = name
      var styles: FontStyle = []
      for token in value.split(separator: ",", omittingEmptySubsequences: true) {
        switch token.trimmingCharacters(in: Self.asciiWhitespace).lowercased() {
        case "bold": styles.insert(.bold)
        case "italic": styles.insert(.italic)
        case "underlined": styles.insert(.underlined)
        default: report("Unknown font style: \(token)")
        }
      }
      parsed = .fontStyle(styles)
    default:
      canonical = name
      parsed = .custom(value)
    }
    return Attribute(name: canonical, value: parsed)
  }
}
