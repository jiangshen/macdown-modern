import Foundation
import Testing

@testable import EditorCore

@Suite("Original editor theme format")
struct EditorThemeTests {
  struct Fixture: Decodable {
    struct Case: Decodable {
      let name: String
      let source: String
      let rules: [Rule]
    }
    let cases: [Case]
  }
  struct Rule: Codable, Equatable {
    let selector: String
    let attributes: [Attribute]
  }
  struct Attribute: Codable, Equatable {
    let name: String
    let kind: Int
    let value: String
  }

  @Test("Every original bundled theme and grammar fixture matches the original parser")
  func characterized() throws {
    let url = try #require(
      Bundle.module.url(forResource: "LegacyEditorThemes", withExtension: "json"))
    let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    #expect(fixture.cases.count >= 21)
    for item in fixture.cases {
      let theme = try EditorTheme.parse(item.source)
      let editor = ["editor", "editor-current-line", "editor-selection"].flatMap { selector in
        theme.rules.filter { $0.selector == selector }
      }
      let elements = theme.rules.filter { !$0.selector.hasPrefix("editor") }
      let result = (editor + elements).filter { !$0.attributes.isEmpty }.map { rule in
        Rule(selector: rule.selector, attributes: rule.attributes.reversed().map(Self.canonical))
      }
      #expect(result == item.rules, "Original theme: \(item.name)")
      if item.name.hasSuffix(".style") { #expect(theme.diagnostics.isEmpty, "\(item.name)") }
    }
  }

  private static func canonical(_ attribute: EditorTheme.Attribute) -> Attribute {
    let kind: Int
    let value: String
    switch attribute.value {
    case .color(let color):
      kind = attribute.name == "foreground-color" ? 0 : attribute.name == "background-color" ? 1 : 2
      value = String(format: "%02x%02x%02x%02x", color.alpha, color.red, color.green, color.blue)
    case .fontSize(let size):
      kind = 3
      value = "\(size.relative ? 1 : 0):\(size.points)"
    case .fontFamily(let family):
      kind = 4
      value = family
    case .fontStyle(let styles):
      kind = 5
      value = "\(styles.rawValue)"
    case .custom(let text):
      kind = 6
      value = text
    }
    return Attribute(name: attribute.name, kind: kind, value: value)
  }

  @Test(
    "Unknown blocks and invalid attributes recover at the next blank line with line diagnostics")
  func recovery() throws {
    let theme = try EditorTheme.parse(
      """
      unknown
      foreground: ffffff

      H1
      missing separator
      foreground: #123456
      font-size: 999999999999999999999999
      font-style: bold, sideways, italic

      EMPH
      foreground: 80112233
      """)
    #expect(theme.rules.map(\.selector) == ["H1", "EMPH"])
    #expect(theme.diagnostics.map(\.line) == [1, 5, 6, 7, 8])
    #expect(theme.rules[0].attributes.first?.value == .fontStyle([.bold, .italic]))
    let color = try #require(theme.rules[1].attributes.first)
    #expect(color.value == .color(.init(red: 17, green: 34, blue: 51, alpha: 128)))
  }

  @Test(
    "Theme source stays separate from Markdown and preserves Unicode font names and custom attributes"
  )
  func values() throws {
    let source =
      "\u{FEFF}editor\r\nfont-family: 中文 Mono\r\nfont-size: +2px\r\ncustom-value = retained:exactly\r\n"
    let theme = try EditorTheme.parse(source)
    #expect(theme.diagnostics.isEmpty)
    #expect(
      theme.rules.first?.attributes.map(\.value) == [
        .fontFamily("中文 Mono"), .fontSize(.init(points: 2, relative: true)),
        .custom("retained:exactly"),
      ])
    #expect(source.contains("\r\n") && source.hasPrefix("\u{FEFF}"))
    let original = try EditorTheme.parse("editor\nforeground: 112233\n\neditor\n")
    #expect(original.rules.count == 1)
    #expect(original.rules.first?.attributes.count == 1)
    #expect(original.diagnostics.map(\.line) == [4])
  }

  @Test("Oversized, NUL and excessive rules fail explicitly while diagnostic storms are bounded")
  func limits() throws {
    #expect(throws: EditorTheme.ParseError.tooLarge) {
      try EditorTheme.parse(String(repeating: "a", count: EditorTheme.maximumBytes + 1))
    }
    #expect(throws: EditorTheme.ParseError.containsNul) { try EditorTheme.parse("editor\n\0") }
    #expect(throws: EditorTheme.ParseError.tooComplex) {
      try EditorTheme.parse(String(repeating: "H1\nforeground: 112233\n\n", count: 4097))
    }
    #expect(throws: EditorTheme.ParseError.tooComplex) {
      try EditorTheme.parse("H1\n" + String(repeating: "foreground: 112233\n", count: 16385))
    }
    let errors = try EditorTheme.parse("H1\n" + String(repeating: "invalid\n", count: 10000))
    #expect(errors.diagnostics.count == 256)
  }
}
