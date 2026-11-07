import Foundation
import Testing

@testable import MarkdownCore

@Suite("Independent intraword formatting")
struct MarkdownIntrawordTests {
  struct Fixtures: Decodable {
    struct Case: Decodable {
      let source: String
      let underline: Bool
      let policy: MarkdownEmphasisPolicy
      let html: String
      let nativeHTML: String?
      let nativeBehaviorNote: String?
    }
    let cases: [Case]
  }

  @Test("Both original word-formatting choices retain all enabled emphasis marker families")
  func characterized() async throws {
    let url = try #require(Bundle.module.url(forResource: "LegacyIntraword", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    let processor = MarkdownProcessor()
    for fixture in fixtures.cases {
      var options = MarkdownRenderingOptions()
      options.emphasisPolicy = fixture.policy
      options.underline = fixture.underline
      options.highlight = true
      options.strikethrough = true
      options.rawHTML = true
      options.codeHighlighting = false
      let result = try await processor.render(fixture.source, options: options)
      let actual = result.html.replacingOccurrences(
        of: #" data-sourcepos="[^"]*""#, with: "", options: .regularExpression)
      #expect((fixture.nativeHTML == nil) == (fixture.nativeBehaviorNote == nil))
      #expect(
        actual == (fixture.nativeHTML ?? fixture.html),
        "\(fixture.policy) underline=\(fixture.underline): \(fixture.source)\n\(actual) != \(fixture.html)"
      )
    }
  }
  @Test("Standard mode remains native while both original choices switch all marker families")
  func switching() async throws {
    let source = "a*b*c a_b_c a**b**c a__b__c a==b==c a~~b~~c"
    let processor = MarkdownProcessor()
    var options = MarkdownRenderingOptions()
    options.highlight = true
    let standard = try await processor.render(source, options: options, includeSyntax: true)
    #expect(standard.html.contains("a<em>b</em>c a_b_c"))
    for policy in [MarkdownEmphasisPolicy.allowWithinWords, .avoidWithinWords] {
      options.emphasisPolicy = policy
      let parsed = try await processor.render(source, options: options, includeSyntax: true)
      if policy == .allowWithinWords {
        #expect(parsed.html.contains("a<em>b</em>c a<em>b</em>c"))
        #expect(parsed.html.contains("a<strong>b</strong>c a<strong>b</strong>c"))
        #expect(parsed.html.contains("a<mark>b</mark>c a<del>b</del>c"))
      } else {
        #expect(parsed.html.contains(source))
        #expect(!parsed.html.contains("<em>") && !parsed.html.contains("<strong>"))
        #expect(!parsed.html.contains("<mark>") && !parsed.html.contains("<del>"))
      }
    }
    options.emphasisPolicy = .standard
    let restored = try await processor.render(source, options: options, includeSyntax: true)
    #expect(restored.html == standard.html)
    options.emphasisPolicy = .allowWithinWords
    options.underline = true
    let underlined = try await processor.render("a_b_c", options: options)
    #expect(underlined.html.contains("a<u>b</u>c"))
  }

  @Test("Word spans preserve UTF-8 source coordinates and UTF-16 syntax positions")
  func positions() async throws {
    let source = "中文 😀 a_b_c **after**\r\n# Tail"
    var options = MarkdownRenderingOptions()
    options.emphasisPolicy = .allowWithinWords
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    let emphasis = try #require(parsed.nodes.first { $0.kind == .emphasis })
    #expect(emphasis.range?.start.line == 1 && emphasis.range?.start.column == 14)
    #expect(emphasis.range?.end.column == 16)
    #expect(parsed.nodes.first { $0.kind == .strong }?.range?.start.column == 19)
    #expect(parsed.headings.first?.sourceLine == 2)
    #expect(parsed.headings.first?.utf16Offset == 23)
    let syntax = try #require(parsed.syntax)
    let offset = (source as NSString).range(of: "b").location
    #expect(syntax.runs.contains { NSLocationInRange(offset, $0.range) && $0.style.italic })
  }

  @Test(
    "Word choices compose with quotes, superscripts, callouts, math and references",
    arguments: [MarkdownEmphasisPolicy.allowWithinWords, .avoidWithinWords])
  func scopes(policy: MarkdownEmphasisPolicy) async throws {
    var options = MarkdownRenderingOptions()
    options.emphasisPolicy = policy
    options.underline = true
    options.quotedText = true
    options.highlight = true
    options.superscript = true
    options.math = true
    let source = """
      > [!NOTE]
      > _callout_ and "a_b_c" and x^(2 + 1).

      `a*b*c` and [**label**][ref] with note[^1].

      ```math
      a_b^2
      ```

      [ref]: https://example.com

      [^1]: Footnote checkpoint.
      """
    let parsed = try await MarkdownProcessor().render(source, options: options)
    #expect(parsed.html.contains("md-callout-note"))
    #expect(parsed.html.contains("<u>callout</u>"))
    #expect(parsed.html.contains("<sup>2 + 1</sup>"))
    #expect(parsed.html.contains("<code>a*b*c</code>"))
    #expect(parsed.html.contains("<a href=\"https://example.com\"><strong>label</strong></a>"))
    #expect(parsed.html.contains("Footnote checkpoint"))
    #expect(parsed.html.contains("<math"))
    #expect(
      parsed.html.contains(policy == .allowWithinWords ? "<q>a<u>b</u>c</q>" : "<q>a_b_c</q>"))
  }

  @Test("Compatibility spans cannot bypass native HTML, destination or link nesting policy")
  func security() async throws {
    var options = MarkdownRenderingOptions()
    options.emphasisPolicy = .allowWithinWords
    options.highlight = true
    let processor = MarkdownProcessor()
    let unsafe = try await processor.render(
      "**<script>alert(1)</script>** and ==[bad](javascript:alert(1))==", options: options)
    #expect(!unsafe.html.contains("<script>"))
    #expect(!unsafe.html.contains("href=\"javascript:"))
    let nested = try await processor.render(
      "[outer **[inner](https://inner.example)**](https://outer.example)", options: options)
    for node in nested.nodes where node.kind == .link {
      var parent = node.parentID
      while let id = parent {
        #expect(nested.nodes[id].kind != .link)
        parent = nested.nodes[id].parentID
      }
    }
  }

  @Test("Mixed malformed markers retain every source letter in both modes")
  func malformedAndBounds() async throws {
    let alphabet = Array("ab*_~= `\n")
    var seed: UInt64 = 0x534E_4F57_464F_4C49
    let processor = MarkdownProcessor()
    for policy in [MarkdownEmphasisPolicy.allowWithinWords, .avoidWithinWords] {
      var options = MarkdownRenderingOptions()
      options.emphasisPolicy = policy
      options.highlight = true
      options.codeHighlighting = false
      // Keep random fence labels from legitimately consuming source letters as metadata.
      options.fencedCode = false
      for sample in 0..<100 {
        options.underline = sample.isMultiple(of: 2)
        var source = ""
        for _ in 0..<256 {
          seed = seed &* 6_364_136_223_846_793_005 &+ 1
          source.append(alphabet[Int(seed >> 32) % alphabet.count])
        }
        let parsed = try await processor.render(source, options: options)
        let text = parsed.nodes.filter { [.text, .inlineCode, .codeBlock].contains($0.kind) }
          .compactMap(\.literal).joined()
        #expect(
          text.filter { $0 == "a" || $0 == "b" } == source.filter { $0 == "a" || $0 == "b" },
          "policy=\(policy) sample=\(sample) source=\(source.debugDescription) html=\(parsed.html.debugDescription)"
        )
      }
      let run = "prefix " + String(repeating: "*", count: 100_000)
      let literal = try await processor.render(run, options: options)
      #expect(literal.html.contains(run), "Large inline run remains literal")
      let oversized = "**" + String(repeating: "body ", count: 20_000) + "end**"
      let fallback = try await processor.render(oversized, options: options)
      #expect(fallback.html.contains(oversized), "Oversized body remains literal")
      #expect(fallback.notices.contains(.complexInlineFormatting))
    }
  }

}
