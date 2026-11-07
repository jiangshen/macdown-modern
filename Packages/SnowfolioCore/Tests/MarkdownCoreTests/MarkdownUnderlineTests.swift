import Foundation
import Testing

@testable import MarkdownCore

@Suite("Optional underline dialect")
struct MarkdownUnderlineTests {
  struct Fixtures: Decodable {
    struct Case: Decodable {
      let source: String
      let enabled: Bool
      let html: String
      let nativeHTML: String?
      let nativeBehaviorNote: String?
    }
    let cases: [Case]
  }

  @Test("Both underline choices match original characterization or an explicit native difference")
  func characterized() async throws {
    let url = try #require(Bundle.module.url(forResource: "LegacyUnderline", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    let processor = MarkdownProcessor()
    for fixture in fixtures.cases {
      var options = MarkdownRenderingOptions()
      options.underline = fixture.enabled
      options.rawHTML = true
      options.codeHighlighting = false
      let result = try await processor.render(fixture.source, options: options)
      let actual = result.html.replacingOccurrences(
        of: #" data-sourcepos="[^"]*""#, with: "", options: .regularExpression)
      #expect((fixture.nativeHTML == nil) == (fixture.nativeBehaviorNote == nil))
      #expect(
        actual == (fixture.nativeHTML ?? fixture.html),
        "underline=\(fixture.enabled): \(fixture.source)\n\(actual) != \(fixture.html)")
    }
  }

  @Test("The same processor switches back to standard Markdown without changing source")
  func switching() async throws {
    let source = "_under_ **bold** *italic* __strong__ a_b_c"
    let processor = MarkdownProcessor()
    var options = MarkdownRenderingOptions()
    let standard = try await processor.render(source, options: options, includeSyntax: true)
    options.underline = true
    let underlined = try await processor.render(source, options: options, includeSyntax: true)
    #expect(underlined.html.contains("<u>under</u>"))
    #expect(underlined.html.contains("a<u>b</u>c"))
    #expect(
      underlined.html.contains("<strong>bold</strong> <em>italic</em> <strong>strong</strong>"))
    #expect(underlined.nodes.filter { $0.kind == .underline }.count == 2)
    let restored = try await processor.render(source, includeSyntax: true)
    #expect(restored.html == standard.html)
  }

  @Test("Multiline consumption preserves subsequent native UTF-8 and UTF-16 source positions")
  func positions() async throws {
    let source = "中文 😀 _one\r\ntwo_ **after**\r\n\r\n# _Title_\r\n"
    var options = MarkdownRenderingOptions()
    options.underline = true
    let rendered = try await MarkdownProcessor().render(
      source, options: options, includeSyntax: true)
    let underline = try #require(rendered.nodes.first { $0.kind == .underline })
    #expect(underline.range?.start.line == 1 && underline.range?.start.column == 13)
    #expect(underline.range?.end.line == 2 && underline.range?.end.column == 4)
    let after = try #require(rendered.nodes.first { $0.kind == .strong })
    #expect(after.range?.start.line == 2 && after.range?.start.column == 6)
    let syntax = try #require(rendered.syntax)
    let location = (source as NSString).range(of: "two").location
    #expect(syntax.runs.contains { NSLocationInRange(location, $0.range) && $0.style.underlined })
    #expect(rendered.headings.first?.title == "Title")
    #expect(rendered.headings.first?.sourceLine == 4)
  }
  @Test("References and footnotes remain native, with no nested links or active HTML bypass")
  func scopes() async throws {
    var options = MarkdownRenderingOptions()
    options.underline = true
    let processor = MarkdownProcessor()
    let referenced = try await processor.render(
      "_a [label][ref] note[^1]_\n\n[ref]: https://example.com\n\n[^1]: footnote", options: options)
    #expect(referenced.html.contains("<u>a <a href=\"https://example.com\">label</a>"))
    #expect(referenced.html.contains("footnote"))
    let unsafe = try await processor.render(
      "_<script>alert(1)</script> [link](javascript:alert(1))_", options: options)
    #expect(!unsafe.html.contains("<script>") && !unsafe.html.contains("href=\"javascript:"))
    let nested = try await processor.render(
      "[outer _[inner](https://inner.example)_](https://outer.example)", options: options)
    func hasNestedLinks(_ rendered: RenderedMarkdown) -> Bool {
      for node in rendered.nodes where node.kind == .link {
        var parent = node.parentID
        while let id = parent {
          if rendered.nodes[id].kind == .link { return true }
          parent = rendered.nodes[id].parentID
        }
      }
      return false
    }
    #expect(!hasNestedLinks(nested))
    #expect(nested.html.contains("href=\"https://inner.example\""))
    #expect(nested.html.contains("[outer <u>"))
    options.superscript = true
    let raised = try await processor.render(
      "[outer x^([inner](https://inner.example))](https://outer.example)", options: options)
    #expect(!hasNestedLinks(raised))
    #expect(raised.html.contains("href=\"https://inner.example\""))
  }

  @Test("Huge runs and unmatched spans retain visible content with bounded optional work")
  func bounded() async throws {
    var options = MarkdownRenderingOptions()
    options.underline = true
    let processor = MarkdownProcessor()
    let run = "prefix " + String(repeating: "_", count: 100_000)
    let literal = try await processor.render(run, options: options)
    #expect(literal.html.contains(run))
    let unmatched = "_" + String(repeating: "text ", count: 20_000) + "end_"
    let result = try await processor.render(unmatched, options: options)
    #expect(result.html.contains(unmatched))
    #expect(result.notices.contains(.complexInlineFormatting))
  }

}
