import Foundation
import Testing

@testable import MarkdownCore

@Suite("Theme source scopes")
struct MarkdownThemeScopeTests {
  private struct Fixtures: Decodable {
    struct Case: Decodable {
      let name: String
      let source: String
      let notes: Bool
      let legacy: [String: [[Int]]]
      let native: [String: [[Int]]]?
      let difference: String?
    }
    let cases: [Case]
  }

  private func ranges(_ token: MarkdownSyntaxToken, in syntax: MarkdownSyntax) -> [NSRange] {
    var ranges: [NSRange] = []
    for run in syntax.runs where run.style.tokens.contains(token) {
      if let previous = ranges.last, NSMaxRange(previous) == run.range.location {
        ranges[ranges.count - 1].length += run.range.length
      } else {
        ranges.append(run.range)
      }
    }
    return ranges
  }

  private func style(_ text: String, source: String, syntax: MarkdownSyntax) throws
    -> MarkdownSyntaxStyle
  {
    let offset = (source as NSString).range(of: text).location
    return try #require(syntax.runs.first { NSLocationInRange(offset, $0.range) }?.style, "\(text)")
  }

  @Test("Original entity/reference/note scopes have exact fixtures and explicit native differences")
  func characterized() async throws {
    let url = try #require(
      Bundle.module.url(forResource: "LegacyThemeScopes", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    #expect(fixtures.cases.count == 9)
    for fixture in fixtures.cases {
      var options = MarkdownRenderingOptions()
      options.footnotes = fixture.notes
      options.codeHighlighting = false
      options.rawHTML = true
      let parsed = try await MarkdownProcessor().render(
        fixture.source, options: options, includeSyntax: true)
      let syntax = try #require(parsed.syntax)
      #expect((fixture.native == nil) == (fixture.difference == nil), "\(fixture.name)")
      for (name, token) in [
        ("HTML_ENTITY", MarkdownSyntaxToken.entity), ("REFERENCE", .referenceDefinition),
        ("NOTE", .note),
      ] {
        let expected = try #require((fixture.native ?? fixture.legacy)[name])
        let scalars = Array(fixture.source.unicodeScalars)
        let expectedUTF16 = expected.map { span in
          let lower = scalars[..<span[0]].reduce(0) { $0 + $1.utf16.count }
          let length = scalars[span[0]..<span[1]].reduce(0) { $0 + $1.utf16.count }
          return NSRange(location: lower, length: length)
        }
        #expect(ranges(token, in: syntax) == expectedUTF16, "\(fixture.name): \(name)")
      }
    }
  }

  @Test(
    "Native-recognized definitions rebase adjacent source scopes and sourcepos",
    arguments: ["\n", "\r\n", "\r"])
  func referencePositions(_ newline: String) async throws {
    for (prefix, continuation) in [
      ("", ""), ("  ", "  "), ("> ", "> "), ("- ", "  "), ("> - ", ">   "),
    ] {
      let source = [prefix + "[a]: /target", continuation + "中文 😀 **bold** [a] &amp;"].joined(
        separator: newline)
      let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
      let syntax = try #require(parsed.syntax)
      let paragraph = try #require(parsed.nodes.first { $0.kind == .paragraph })
      #expect(paragraph.range?.start == .init(line: 2, column: continuation.utf8.count + 1))
      let link = try #require(parsed.nodes.first { $0.kind == .link })
      #expect(link.range?.start.line == 2)
      #expect(link.destination == "/target")
      if !prefix.contains("- ") {
        #expect(parsed.html.contains("data-sourcepos=\"2:\(continuation.utf8.count + 1)-2:"))
      } else {
        // Tight native lists intentionally omit paragraph tags/sourcepos.
        #expect(parsed.html.contains("<li data-sourcepos="))
      }
      #expect(try style("bold", source: source, syntax: syntax).tokens.contains(.strong))
      #expect(try style("&amp;", source: source, syntax: syntax).tokens.contains(.entity))
      #expect(
        !(try style("bold", source: source, syntax: syntax).tokens.contains(.referenceDefinition)))
      let withoutSyntax = try await MarkdownProcessor().render(source)
      #expect(withoutSyntax.html == parsed.html)
      #expect(withoutSyntax.nodes == parsed.nodes)
    }
  }

  @Test(
    "Multiline and repeated definitions preserve heading and link ownership",
    arguments: ["\n", "\r\n", "\r"])
  func definitionHeading(_ newline: String) async throws {
    let source = ["[a]:", "  /target", "  \"Title\"", "[a]: /ignored", "**中文** [a] &copy;", "---"]
      .joined(separator: newline)
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let syntax = try #require(parsed.syntax)
    let heading = try #require(parsed.nodes.first { $0.kind == .heading })
    #expect(heading.headingLevel == 2)
    #expect(heading.range?.start == .init(line: 5, column: 1))
    #expect(heading.range?.end.line == 6)
    #expect(parsed.headings.first?.sourceLine == 5)
    #expect(parsed.headings.first?.utf16Offset == (source as NSString).range(of: "**中文**").location)
    #expect(parsed.nodes.first { $0.kind == .link }?.destination == "/target")
    #expect(parsed.html.contains("title=\"Title\""))
    #expect(try style("中文", source: source, syntax: syntax).tokens == [.heading(2), .strong])
    #expect(try style("&copy;", source: source, syntax: syntax).tokens == [.heading(2), .entity])
    #expect(
      !(try style("---", source: source, syntax: syntax).tokens.contains(.referenceDefinition)))
  }

  @Test("Invalid definitions and opaque native blocks cannot create reference scopes")
  func invalidDefinitions() async throws {
    for source in [
      "[a]:", "[a]: <unterminated", "`[a]: /code`", "    [a]: /code", "```\n[a]: /code\n```",
      "<!--\n[a]: /comment\n-->",
    ] {
      let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
      #expect(ranges(.referenceDefinition, in: try #require(parsed.syntax)).isEmpty, "\(source)")
    }
    let source = "---\ntitle: 中文 😀\n---\n\n[a]: /a\n**bold** [a]"
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    #expect(parsed.frontMatter != nil)
    #expect(parsed.nodes.first { $0.kind == .strong }?.range?.start.line == 6)
    #expect(
      try style("bold", source: source, syntax: #require(parsed.syntax)).tokens.contains(.strong))
  }

  @Test("Entity decoding is native, bounded and composes with source ancestry")
  func entities() async throws {
    let source =
      "> **中文 😀 &amp;&copy;** and [label &lt;](https://example.com/?v=&quot;) `&gt;` \\&reg;"
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let syntax = try #require(parsed.syntax)
    let entity = try style("&amp;", source: source, syntax: syntax)
    #expect(entity.tokens == [.blockquote, .strong, .entity])
    #expect(
      try style("&lt;", source: source, syntax: syntax).tokens == [.blockquote, .link, .entity])
    #expect(!(try style("&quot;", source: source, syntax: syntax).tokens.contains(.entity)))
    #expect(!(try style("&gt;", source: source, syntax: syntax).tokens.contains(.entity)))
    #expect(!(try style("&reg;", source: source, syntax: syntax).tokens.contains(.entity)))
    for ampersands in [
      String(repeating: "&", count: 20_000), "&#" + String(repeating: "9", count: 20_000),
    ] {
      let source = ampersands + " &amp;"
      let result = try await MarkdownProcessor().render(source, includeSyntax: true)
      #expect(
        ranges(.entity, in: try #require(result.syntax)) == [
          (source as NSString).range(of: "&amp;")
        ])
    }
  }

  @Test(
    "Footnote definitions retain markers, unused ranges and nested native scopes",
    arguments: ["\n", "\r\n", "\r"])
  func notes(_ newline: String) async throws {
    let source = [
      "> Text[^used].", ">", "> [^used]: **Note &copy;**", "", "[^unused]: Unused.", "",
      "Text[^missing].",
    ].joined(separator: newline)
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let syntax = try #require(parsed.syntax)
    #expect(parsed.nodes.filter { $0.kind == .footnoteDefinition }.count == 1)
    #expect(parsed.nodes.filter { $0.kind == .footnoteReference }.count == 1)
    #expect(try style("[^used]:", source: source, syntax: syntax).tokens == [.blockquote, .note])
    #expect(
      try style("Note", source: source, syntax: syntax).tokens == [.blockquote, .note, .strong])
    #expect(
      try style("&copy;", source: source, syntax: syntax).tokens == [
        .blockquote, .note, .strong, .entity,
      ])
    #expect(try style("[^unused]:", source: source, syntax: syntax).tokens == [.note])
    #expect(
      !(syntax.runs.first {
        NSLocationInRange((source as NSString).range(of: "[^missing]").location, $0.range)
      }?.style.tokens.contains(.note) ?? false))
    #expect(parsed.html.contains("Note ©"))
    #expect(!parsed.html.contains("Unused"))
    let plain = try await MarkdownProcessor().render(source)
    #expect(plain.html == parsed.html)
    #expect(plain.nodes == parsed.nodes)
  }
}
