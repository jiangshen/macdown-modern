import Foundation
import Testing

@testable import MarkdownCore

@Suite("Fenced code preference")
struct MarkdownFenceTests {
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

  @Test("Fence choices retain characterized cases and explicit CommonMark differences")
  func characterized() async throws {
    let url = try #require(Bundle.module.url(forResource: "LegacyFences", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    for fixture in fixtures.cases {
      var options = MarkdownRenderingOptions()
      options.fencedCode = fixture.enabled
      options.codeHighlighting = false
      options.strikethrough = false
      options.rawHTML = true
      let result = try await MarkdownProcessor().render(fixture.source, options: options)
      let actual = result.html.replacingOccurrences(
        of: #" data-sourcepos="[^"]*""#, with: "", options: .regularExpression
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)
      // CommonMark folds inline-code line endings to spaces, unlike Hoedown.
      // Preserve exact block text, including indented code, and all other markup.
      #expect((fixture.nativeHTML == nil) == (fixture.nativeBehaviorNote == nil))
      var expected = (fixture.nativeHTML ?? fixture.html).trimmingCharacters(
        in: .whitespacesAndNewlines)
      if !fixture.enabled, !expected.contains("<pre>") {
        let regex = try NSRegularExpression(
          pattern: "<code>(.*?)</code>", options: .dotMatchesLineSeparators)
        for match in regex.matches(
          in: expected, range: NSRange(expected.startIndex..., in: expected)
        ).reversed() {
          let text = (expected as NSString).substring(with: match.range(at: 1))
          var folded = text.replacingOccurrences(of: "\n", with: " ")
          if folded.hasPrefix(" "), folded.hasSuffix(" "), folded.contains(where: { $0 != " " }) {
            folded.removeFirst()
            folded.removeLast()
          }
          expected = (expected as NSString).replacingCharacters(
            in: match.range(at: 1), with: folded)
        }
      }
      #expect(
        actual == expected, "fences=\(fixture.enabled): \(fixture.source)\n\(actual) != \(expected)"
      )
    }
  }

  @Test("The same processor switches both fence characters without losing indented or inline code")
  func switching() async throws {
    let processor = MarkdownProcessor()
    for marker in ["```", "~~~"] {
      let source = "\(marker)text\n**body**\n\(marker)\n\n    indented\n\n`inline`"
      var options = MarkdownRenderingOptions()
      options.codeHighlighting = false
      let enabled = try await processor.render(source, options: options, includeSyntax: true)
      #expect(enabled.nodes.filter { $0.kind == .codeBlock }.count == 2)
      #expect(!enabled.html.contains("<strong>body</strong>"))
      options.fencedCode = false
      let disabled = try await processor.render(source, options: options, includeSyntax: true)
      #expect(disabled.nodes.filter { $0.kind == .codeBlock }.count == 1)
      #expect(disabled.html.contains("indented") && disabled.html.contains("<code>inline</code>"))
      if marker == "~~~" { #expect(disabled.html.contains("<strong>body</strong>")) }
      let restored = try await processor.render(source, options: .init(), includeSyntax: true)
      #expect(restored.nodes.filter { $0.kind == .codeBlock }.count == 2)
      #expect(disabled.syntax != nil && restored.syntax != nil)
    }
  }

  @Test("Disabling fences prevents fenced math/diagrams while preserving ordinary inline math")
  func specialRenderers() async throws {
    var options = MarkdownRenderingOptions()
    options.fencedCode = false
    options.math = true
    options.inlineDollarMath = true
    options.mermaid = true
    options.graphviz = true
    for kind in ["math", "mermaid", "dot"] {
      let result = try await MarkdownProcessor().render("```\(kind)\nx^2\n```", options: options)
      #expect(result.mathExpressions == 0 && result.diagrams == 0)
      #expect(result.highlightedCodeBlocks == 0)
      #expect(!result.nodes.contains { $0.kind == .codeBlock })
      #expect(result.html.contains("x^2") && result.notices.isEmpty)
    }
    let inline = try await MarkdownProcessor().render("$x^2$", options: options)
    #expect(inline.mathExpressions == 1)
  }

  @Test("Native malformed-fence handling and following Unicode coordinates remain correct")
  func boundaries() async throws {
    let source = "~~~text\r\n**中文 👩‍💻**\r\n~~~\r\n\r\n# After\r\n"
    var options = MarkdownRenderingOptions()
    options.fencedCode = false
    let result = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    #expect(result.nodes.contains { $0.kind == .strong && $0.range?.start.line == 2 })
    #expect(result.headings.first?.sourceLine == 5)
    #expect(
      result.headings.first?.utf16Offset == (source as NSString).range(of: "# After").location)
    #expect(
      result.syntax?.runs.allSatisfy { NSMaxRange($0.range) <= (source as NSString).length } == true
    )
    let open = try await MarkdownProcessor().render("~~~text\nUnclosed")
    #expect(open.nodes.contains { $0.kind == .codeBlock })
    let literal = try await MarkdownProcessor().render("~~~text\nUnclosed", options: options)
    #expect(!literal.nodes.contains { $0.kind == .codeBlock })
    #expect(literal.html.contains("~~~text") && literal.html.contains("Unclosed"))
  }
}
