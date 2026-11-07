import Foundation
import Testing

@testable import MarkdownCore

@Suite("Optional inline dialects")
struct MarkdownInlineExtensionTests {
  struct Fixtures: Decodable {
    struct Case: Decodable {
      let option: String
      let source: String
      let html: String
    }
    let cases: [Case]
  }

  @Test("Characterized legacy highlight and superscript output is retained")
  func characterized() async throws {
    let url = try #require(Bundle.module.url(forResource: "LegacyInline", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    for fixture in fixtures.cases {
      var options = MarkdownRenderingOptions()
      options.highlight = fixture.option == "highlight"
      options.superscript = fixture.option == "superscript"
      options.rawHTML = true
      let result = try await MarkdownProcessor().render(fixture.source, options: options)
      let normalized = result.html.replacingOccurrences(
        of: #" data-sourcepos="[^"]*""#, with: "", options: .regularExpression
      ).trimmingCharacters(in: .whitespacesAndNewlines)
      let expected = fixture.html.replacingOccurrences(of: " </p>", with: "</p>")
      #expect(normalized == expected, "\(fixture.source): \(normalized) != \(fixture.html)")
    }
  }

  @Test("Extensions default off, enable independently, and leave literal scopes intact")
  func boundaries() async throws {
    let source =
      "==highlight== x^2 `==code== ^2` ![==alt== ^2](image.png) [link](https://example.com/==path==/^2)"
    let plain = try await MarkdownProcessor().render(source)
    #expect(!plain.html.contains("<mark>") && !plain.html.contains("<sup>"))
    var options = MarkdownRenderingOptions()
    options.highlight = true
    let marked = try await MarkdownProcessor().render(source, options: options)
    #expect(marked.html.contains("<mark>highlight</mark>"))
    #expect(!marked.html.contains("<sup>"))
    options.highlight = false
    options.superscript = true
    let raised = try await MarkdownProcessor().render(source, options: options)
    #expect(!raised.html.contains("<mark>"))
    #expect(raised.html.contains("x<sup>2</sup>"))
    options.highlight = true
    let both = try await MarkdownProcessor().render(source, options: options)
    #expect(both.html.contains("<code>==code== ^2</code>"))
    #expect(both.html.contains("alt=\"==alt== ^2\""))
    #expect(both.html.contains("https://example.com/==path==/%5E2"))
    let fence = try await MarkdownProcessor().render(
      "```text\n==literal== x^2\n```", options: options)
    #expect(!fence.html.contains("<mark>") && !fence.html.contains("<sup>"))
  }

  @Test(
    "Nested inline children, shared references, footnotes and native Markdown remain structured")
  func nesting() async throws {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    let source =
      "==a^(b^2) *styled*== and x^([link][ref]). Note[^1].\n\n[ref]: https://example.com\n\n[^1]: footnote"
    let result = try await MarkdownProcessor().render(source, options: options)
    #expect(result.html.contains("<mark>a<sup>b<sup>2</sup></sup> <em>styled</em></mark>"))
    #expect(result.html.contains("https://example.com"))
    #expect(result.html.contains("footnote"))
    #expect(result.nodes.contains { $0.kind == .highlight })
    #expect(result.nodes.filter { $0.kind == .superscript }.count >= 2)
    let references = try await MarkdownProcessor().render(
      "x^([link][ref])\n\n[ref]: https://example.com", options: options)
    #expect(references.html.contains("<sup><a href=\"https://example.com\">link</a></sup>"))
  }

  @Test("Unicode, multiline parenthesized superscripts and CRLF keep following source coordinates")
  func positions() async throws {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    let source = "中文 😀 ==mark== x^(one\r\ntwo) **after**\r\n\r\n# Heading ==title==\r\n"
    let result = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    let mark = try #require(result.nodes.first { $0.kind == .highlight })
    #expect(mark.range?.start.line == 1 && mark.range?.start.column == 13)
    #expect(mark.range?.end.column == 20)
    let sup = try #require(result.nodes.first { $0.kind == .superscript })
    #expect(sup.range?.start.line == 1 && sup.range?.end.line == 2)
    let after = try #require(result.nodes.first { $0.kind == .strong })
    #expect(after.range?.start.line == 2 && after.range?.start.column == 6)
    #expect(result.headings.first?.title == "Heading title")
    #expect(
      result.headings.first?.utf16Offset == (source as NSString).range(of: "# Heading").location)
  }

  @Test("Malformed and deep input retains source instead of reproducing legacy deletion bugs")
  func malformed() async throws {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    for source in ["x^()", "x^(unclosed", "==unclosed", "== =="] {
      let result = try await MarkdownProcessor().render(source, options: options)
      #expect(!result.html.contains("<sup></sup>"))
      #expect(result.html.contains(source), "\(source)")
    }
    let deep = "x" + String(repeating: "^x", count: 5000)
    let result = try await MarkdownProcessor().render(deep, options: options)
    #expect(result.notices.contains(.complexInlineFormatting))
    #expect(result.html.contains("^x^x"))
    let unmatched = try await MarkdownProcessor().render(
      String(repeating: "== source ", count: 10_000) + "^2", options: options)
    #expect(unmatched.html.contains("source"))
  }

  @Test("Inline extensions keep unsafe HTML and destinations under the same renderer policy")
  func security() async throws {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    let result = try await MarkdownProcessor().render(
      "==<script>alert(1)</script>== x^([bad](javascript:alert(1)))", options: options)
    #expect(!result.html.contains("<script>"))
    #expect(!result.html.contains("href=\"javascript:"))
    #expect(result.html.contains("<mark>"))
    #expect(result.html.contains("<sup>"))
  }
}

extension MarkdownInlineExtensionTests {
  @Test("Native inline transformations preserve text across mixed malformed delimiters")
  func malformedCorpus() async throws {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    var state: UInt64 = 0x51F010
    let alphabet = Array("^()=*_[]`\\ ")
    func fragment() -> String {
      var value = ""
      for _ in 0..<32 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        value.append(alphabet[Int(state % UInt64(alphabet.count))])
      }
      return value
    }
    let processor = MarkdownProcessor()
    for _ in 0..<500 {
      let source = "begin" + fragment() + "middle" + fragment() + "checkpoint"
      let result = try await processor.render(source, options: options)
      #expect(result.html.contains("begin"))
      if !result.html.contains("middle") || !result.html.contains("checkpoint") {
        let plain = try await processor.render(source)
        #expect(Bool(false), "Source: \(source)\nBaseline: \(plain.html)\nExtended: \(result.html)")
      }
      #expect(result.html.contains("middle"))
      #expect(result.html.contains("checkpoint"))
    }
    let oversized = try await processor.render(
      String(repeating: "^", count: 100_000) + "checkpoint", options: options)
    #expect(oversized.notices.contains(.complexInlineFormatting))
    #expect(oversized.html.contains("checkpoint"))
  }

  @Test("Inline dialects compose with front matter, callouts, math and shared references")
  func composition() async throws {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    options.math = true
    options.inlineDollarMath = true
    let result = try await MarkdownProcessor().render(
      """
      ---
      title: ==literal==
      ---
      > [!NOTE]
      > ==Highlighted $x^2$== and x^([link][ref]).

      [ref]: https://example.com
      """, options: options)
    #expect(result.frontMatter != nil)
    #expect(result.html.contains("==literal=="))
    #expect(result.mathExpressions == 1)
    #expect(result.html.contains("md-callout-note"))
    #expect(result.html.contains("<mark>Highlighted "))
    #expect(result.html.contains("<sup><a href=\"https://example.com\">link</a></sup>"))
    #expect(result.notices.isEmpty)
  }
}

extension MarkdownInlineExtensionTests {
  @Test("Attributed-string-like input follows ordinary Markdown without swallowing trailing text")
  func nativeAttributeRegression() async throws {
    let source = "Before ^[label][missing] after checkpoint"
    let result = try await MarkdownProcessor().render(source)
    #expect(result.html.contains(source))
    let link = try await MarkdownProcessor().render("Before ^[label](annotation) after checkpoint")
    #expect(link.html.contains("^<a href=\"annotation\">label</a> after checkpoint"))
    #expect(!link.nodes.contains { $0.kind == .other("attribute") })
    var options = MarkdownRenderingOptions()
    options.superscript = true
    let raised = try await MarkdownProcessor().render(
      "x^[link][ref]\n\n[ref]: https://example.com", options: options)
    #expect(raised.html.contains("x<sup><a href=\"https://example.com\">link</a></sup>"))
    let escaped = try await MarkdownProcessor().render(#"\[^2"#, options: options)
    #expect(escaped.html.contains("[<sup>2</sup>"))
  }
}
