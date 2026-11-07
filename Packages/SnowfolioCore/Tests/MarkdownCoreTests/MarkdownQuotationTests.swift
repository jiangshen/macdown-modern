import Foundation
import Testing

@testable import MarkdownCore

@Suite("Optional quoted-text dialect")
struct MarkdownQuotationTests {
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

  @Test("Both quote choices match original characterization or an explicit native difference")
  func characterized() async throws {
    let url = try #require(Bundle.module.url(forResource: "LegacyQuotation", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    let processor = MarkdownProcessor()
    for fixture in fixtures.cases {
      var options = MarkdownRenderingOptions()
      options.quotedText = fixture.enabled
      options.rawHTML = true
      options.codeHighlighting = false
      let result = try await processor.render(fixture.source, options: options)
      let actual = result.html.replacingOccurrences(
        of: #" data-sourcepos="[^"]*""#, with: "", options: .regularExpression)
      #expect((fixture.nativeHTML == nil) == (fixture.nativeBehaviorNote == nil))
      #expect(
        actual == (fixture.nativeHTML ?? fixture.html),
        "quote=\(fixture.enabled): \(fixture.source)\nActual: \(actual)Expected: \(fixture.html)")
    }
  }
  @Test("Quotation options compose, switch independently and keep following source coordinates")
  func switchingAndPositions() async throws {
    let source = "中文 😀 \"  one\r\ntwo  \" **after**\r\n\r\n# \"Title\""
    let processor = MarkdownProcessor()
    let original = try await processor.render(source, includeSyntax: true)
    var options = MarkdownRenderingOptions()
    options.quotedText = true
    let result = try await processor.render(source, options: options, includeSyntax: true)
    let quote = try #require(result.nodes.first { $0.kind == .quotation })
    #expect(quote.range?.start.line == 1 && quote.range?.start.column == 13)
    #expect(quote.range?.end.line == 2 && quote.range?.end.column == 6)
    #expect(result.nodes.first { $0.kind == .strong }?.range?.start.column == 8)
    #expect(result.headings.first?.title == "Title")
    #expect(result.headings.first?.sourceLine == 4)
    let syntax = try #require(result.syntax)
    let offset = (source as NSString).range(of: "two").location
    #expect(syntax.runs.contains { NSLocationInRange(offset, $0.range) && $0.style.role == .quote })
    let restored = try await processor.render(source, includeSyntax: true)
    #expect(restored.html == original.html)
    options.underline = true
    options.highlight = true
    options.superscript = true
    options.smartPunctuation = true
    let combined = try await processor.render(
      "\"_under_ ==mark== x^(2 + 1) don't -- wait...\"", options: options)
    #expect(combined.html.contains("<q><u>under</u> <mark>mark</mark> x<sup>2 + 1</sup>"))
    #expect(combined.html.contains("don’t – wait…</q>"))
  }

  @Test("References, image descriptions and security boundaries stay native inside quotations")
  func scopes() async throws {
    var options = MarkdownRenderingOptions()
    options.quotedText = true
    let processor = MarkdownProcessor()
    let result = try await processor.render(
      "\"a [label][ref] note[^1]\"\n\n[ref]: https://example.com\n\n[^1]: footnote",
      options: options)
    #expect(result.html.contains("<q>a <a href=\"https://example.com\">label</a>"))
    #expect(result.html.contains("footnote"))
    let unsafe = try await processor.render(
      "\"<script>alert(1)</script> [bad](javascript:alert(1))\"", options: options)
    #expect(!unsafe.html.contains("<script>"))
    #expect(!unsafe.html.contains("href=\"javascript:"))
    let nested = try await processor.render(
      "[outer \"[inner](https://inner.example)\"](https://outer.example)", options: options)
    for node in nested.nodes where node.kind == .link {
      var parent = node.parentID
      while let id = parent {
        #expect(nested.nodes[id].kind != .link)
        parent = nested.nodes[id].parentID
      }
    }
    options.smartPunctuation = true
    let unmatched = try await processor.render("before \"unclosed", options: options)
    #expect(unmatched.html.contains("“unclosed"))
    #expect(!unmatched.html.contains("<q>"))
    options.tables = false
    options.strikethrough = false
    options.taskLists = false
    options.autolinks = false
    let isolated = try await processor.render("prefix \"quote\" suffix", options: options)
    #expect(isolated.html.contains("prefix <q>quote</q> suffix"))
  }

  @Test("Long quote runs and oversized spans remain visible with bounded compatibility work")
  func bounded() async throws {
    var options = MarkdownRenderingOptions()
    options.quotedText = true
    let source = "\"" + String(repeating: "text ", count: 20_000) + "end\""
    let rendered = try await MarkdownProcessor().render(source, options: options)
    #expect(!rendered.html.contains("<q>"))
    #expect(rendered.html.contains("end&quot;"))
    #expect(rendered.notices.contains(.complexInlineFormatting))
    let run = String(repeating: "\"", count: 100_000)
    let literal = try await MarkdownProcessor().render(run, options: options)
    #expect(literal.html.components(separatedBy: "&quot;").count == 100_001)
  }

}
