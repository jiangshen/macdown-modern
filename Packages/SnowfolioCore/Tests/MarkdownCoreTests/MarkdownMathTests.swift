import Foundation
import MathCore
import Testing

@testable import MarkdownCore

@Suite("Offline TeX equations")
struct MarkdownMathTests {
  @Test(
    "Pinned engine produces accessible fractions, sums and matrices",
    arguments: [
      #"\frac{a_b}{c^2}"#, #"\sum_{n=1}^{\infty}\frac{1}{n^2}=\frac{\pi^2}{6}"#,
      #"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#, #"\int_0^1 x^2\,dx=\frac13"#,
    ])
  func engine(_ source: String) throws {
    let renderer = MathRenderer()
    let result = try renderer.render(source, display: true)
    #expect(result.issue == nil)
    #expect(result.html.contains("<math"))
    #expect(result.html.contains("application/x-tex"))
    #expect(result.html.contains("katex-html"))
    #expect(result.html.contains("aria-hidden=\"true\""))
    #expect(!result.html.contains("<script"))
  }

  @Test("Unsafe and unsupported input stays inert, bounded and isolated between expressions")
  func constraints() throws {
    let renderer = MathRenderer()
    let invalid = try renderer.render(
      #"\notASupportedCommand{<script>alert('x')</script>}"#, display: false)
    #expect(invalid.issue != nil)
    #expect(invalid.html.contains("&lt;script&gt;"))
    #expect(!invalid.html.contains("<script"))
    let link = try renderer.render(#"\href{javascript:alert(1)}{click}"#, display: false)
    #expect(!link.html.contains("href="))
    let image = try renderer.render(
      #"\includegraphics{https://example.com/private.png}"#, display: false)
    #expect(!image.html.contains("<img"))
    let loop = try renderer.render(#"\def\loop{\loop}\loop"#, display: false)
    #expect(loop.issue != nil)
    _ = try renderer.render(#"\gdef\privateMacro{secret}\privateMacro"#, display: false)
    #expect(try renderer.render(#"\privateMacro"#, display: false).issue != nil)
    #expect(try renderer.render(String(repeating: "x", count: 16_385), display: false).issue != nil)
    #expect(try renderer.render("x^2", display: false).issue == nil)
  }

  @Test("Math is optional and its AST ranges retain Unicode and newline coordinates")
  func parser() async throws {
    let source =
      "中文 😀 $$\\frac{a_b}{c^2}$$ and $x_1$.\r\n\r\n# Heading 😀\r\n\r\n```math\r\n\\begin{aligned}a&=b\\\\c&=d\\end{aligned}\r\n```\r\n"
    let processor = MarkdownProcessor()
    let disabled = try await processor.render(source)
    #expect(disabled.mathExpressions == 0)
    #expect(!disabled.html.contains("class=\"katex"))
    var options = MarkdownRenderingOptions()
    options.math = true
    let displayOnly = try await processor.render(source, options: options)
    #expect(displayOnly.mathExpressions == 2)
    #expect(displayOnly.html.contains("$x_1$"))
    options.inlineDollarMath = true
    let result = try await processor.render(source, options: options, includeSyntax: true)
    #expect(result.mathExpressions == 3)
    let equations = result.nodes.filter {
      if case .math = $0.kind { return true }
      return false
    }
    #expect(equations.count == 3)
    #expect(equations.first?.literal == #"\frac{a_b}{c^2}"#)
    #expect(equations.first?.range?.start.line == 1)
    #expect(equations.first?.range?.start.column == 13)
    #expect(equations.first?.range?.end.line == 1)
    #expect(result.headings.first?.sourceLine == 3)
    #expect(
      result.headings.first?.utf16Offset == (source as NSString).range(of: "# Heading").location)
    #expect(!result.html.contains("<em>"))
    #expect(result.notices.isEmpty)
    #expect(result.syntax?.runs.contains { $0.style.role == .code } == true)
  }

  @Test("CommonMark keeps code, destinations, image alt, escaped dollars and currency literal")
  func boundaries() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let source =
      #"`$code$` ![$alt$](photo.png) [link](https://example.com/$path$) \$escaped\$ costs $5 and $10. $$$triple$$$"#
    let result = try await MarkdownProcessor().render(source, options: options)
    #expect(result.mathExpressions == 0)
    #expect(result.html.contains("<code>$code$</code>"))
    #expect(result.html.contains("alt=\"$alt$\""))
    #expect(result.html.contains("href=\"https://example.com/$path$\""))
    let fence = try await MarkdownProcessor().render("```text\n$$literal$$\n```", options: options)
    #expect(fence.mathExpressions == 0)
    let fallback = try await MarkdownProcessor().render(
      #"$$\notSupported{<b>}$$"#, options: options)
    #expect(fallback.notices.contains(.unsupportedMath))
    #expect(fallback.html.contains("&lt;b&gt;"))
    #expect(!fallback.html.contains("<b>"))
  }

  @Test(
    "Native display delimiters preserve multiline TeX and following blocks",
    arguments: [
      "$$\n\\frac{a_b}{c}\n\n+x^2\n$$\n\n# After",
      "\\[\n\\frac{a_b}{c}\n\\]\n\n# After",
      "\\\\[\n\\frac{a_b}{c}\n\\\\]\n\n# After",
      "> $$\n> \\frac{a_b}{c}\n> $$\n\n# After",
      "- $$\n  \\frac{a_b}{c}\n  $$\n\n# After",
      "```text\n$$\n```\n\n$$\n\\frac{a_b}{c}\n$$\n\n# After",
    ])
  func displayBlocks(_ source: String) async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    let result = try await MarkdownProcessor().render(source, options: options)
    #expect(result.mathExpressions == 1)
    #expect(result.notices.isEmpty)
    #expect(result.html.contains("class=\"katex"))
    #expect(result.headings.last?.title == "After")
    #expect(
      result.nodes.contains {
        if case .math(display: true) = $0.kind { return $0.literal?.contains("a_b") == true }
        return false
      })
  }

  @Test("Legacy doubled-backslash inline syntax keeps TeX punctuation and source positions")
  func legacyInline() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    let result = try await MarkdownProcessor().render(
      #"Before \\(\frac{a_b}{c}\\) after."#, options: options)
    #expect(result.mathExpressions == 1)
    #expect(result.notices.isEmpty)
    let math = result.nodes.first { $0.kind == .math(display: false) }
    #expect(math?.literal == #"\frac{a_b}{c}"#)
    #expect(math?.range?.start.column == 8)
    #expect(result.html.contains("Before "))
    #expect(result.html.contains(" after."))
    let unmatched = try await MarkdownProcessor().render(
      "$$\na_b\n\n# Still Markdown", options: options)
    #expect(unmatched.mathExpressions == 0)
    #expect(unmatched.headings.first?.title == "Still Markdown")
    let scoped = try await MarkdownProcessor().render(
      "> $$\n> a_b\n\n# Outside quote\n\n$$", options: options)
    #expect(scoped.headings.first?.title == "Outside quote")
    #expect(scoped.notices.contains(.unsupportedMath))
  }

  @Test("Long unmatched delimiters preserve text and following source positions")
  func unmatched() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let source = String(repeating: "$ unmatched ", count: 10_000) + "\n\n# Still here"
    let result = try await MarkdownProcessor().render(source, options: options)
    #expect(result.mathExpressions == 0)
    #expect(result.headings.first?.sourceLine == 3)
    #expect(result.html.contains("Still here"))
    let multiline = try await MarkdownProcessor().render("$$\na_b\n$$", options: options)
    #expect(multiline.mathExpressions == 1)
    #expect(multiline.nodes.contains { $0.kind == .math(display: true) && $0.range?.end.line == 3 })
  }
}
