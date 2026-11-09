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

  @Test("TeX definitions apply to later equations and reset on each document render")
  func documentMacros() async throws {
    let processor = MarkdownProcessor()
    var options = MarkdownRenderingOptions()
    options.math = true
    let definitions = #"\def\field{\mathbb{R}}\newcommand{\squareit}[1]{#1^2}\let\savedField\field"#
    let source = "$$" + definitions + "$$\n\n$$\\savedField + \\squareit{x}$$"
    let result = try await processor.render(source, options: options)
    #expect(result.mathExpressions == 2)
    #expect(result.notices.isEmpty)
    #expect(result.html.contains("mathvariant=\"double-struck\">R"))
    #expect(result.html.contains("<msup>"))
    let moved = try await processor.render("# Before 😀\r\n\r\n" + source, options: options)
    let mathLines = moved.nodes.compactMap { node -> Int? in
      if case .math = node.kind { return node.range?.start.line }
      return nil
    }
    #expect(mathLines == [3, 5])
    #expect(moved.notices.isEmpty && moved.html.contains("data-sourcepos=\"5:1-"))
    let other = try await processor.render(#"$$\field$$"#, options: options)
    #expect(other.notices.contains(.unsupportedMath))
    // A cached document result must replay the same complete definition scope.
    let again = try await processor.render(source, options: options)
    #expect(again.html == result.html && again.notices == result.notices)
    let changed = source.replacingOccurrences(of: #"\mathbb{R}"#, with: #"\mathbb{Z}"#)
    let updated = try await processor.render(changed, options: options)
    #expect(updated.notices.isEmpty)
    #expect(updated.html.contains("mathvariant=\"double-struck\">Z"))
    #expect(!updated.html.contains("mathvariant=\"double-struck\">R"))
    // Removing definitions cannot retain values from a previous render.
    let removed = try await processor.render(#"$$\savedField + \squareit{x}$$"#, options: options)
    #expect(removed.notices.contains(.unsupportedMath))
  }

  @Test("Redefinitions follow source order across inline math and math fences")
  func macroOrder() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let source =
      #"$\newcommand{\value}{A}$ then $\value$."#
      + "\n\n```math\n\\renewcommand{\\value}{B}\n```\n\n"
      + #"$\value$."#
    let result = try await MarkdownProcessor().render(source, options: options)
    #expect(result.mathExpressions == 4)
    #expect(result.notices.isEmpty)
    let before = try #require(result.html.range(of: "<mi>A</mi>"))
    let after = try #require(result.html.range(of: "<mi>B</mi>"))
    #expect(before.lowerBound < after.lowerBound)
  }

  @Test("Cached ordinary formulas do not skip definitions or bypass equation limits")
  func documentMacroConstraints() throws {
    let renderer = MathRenderer()
    let ordinary = MathExpression("x^2", display: false)
    let missing = try renderer.renderDocument([MathExpression(#"\checkpoint"#, display: false)])
    #expect(missing.first?.issue != nil)
    for letter in ["A", "B", "A"] {
      let values = try renderer.renderDocument([
        ordinary, MathExpression("\\newcommand{\\checkpoint}{\(letter)}", display: false),
        MathExpression(#"\checkpoint"#, display: false),
      ])
      #expect(values.count == 3 && values.allSatisfy { $0.issue == nil })
      #expect(values[2].html.contains("<mi>\(letter)</mi>"))
    }
    #expect(try renderer.render(#"\checkpoint"#, display: false).issue != nil)
    let constrained = try renderer.renderDocument([
      MathExpression(#"\newcommand{\badlink}{\href{javascript:alert(1)}{click}}"#, display: false),
      MathExpression(#"\badlink"#, display: false),
      MathExpression(#"\newcommand{\loop}{\loop}\loop"#, display: false),
      MathExpression(String(repeating: "x", count: 16_385), display: false), ordinary,
    ])
    #expect(constrained.count == 5)
    #expect(!constrained[1].html.contains("href="))
    #expect(constrained[2].issue != nil && constrained[3].issue != nil)
    #expect(constrained[4].issue == nil)
    let fresh = try renderer.renderDocument([MathExpression(#"\checkpoint"#, display: false)])
    #expect(fresh.first?.issue != nil)
  }

  @Test("Streaming equations survive cache limits and stop cleanly on a consumer error")
  func streamingEquations() throws {
    let renderer = MathRenderer()
    let expression = MathExpression(
      "\\text{" + String(repeating: "x", count: 10_000) + "}", display: false)
    let expressions = Array(repeating: expression, count: 200)
    var indices: [Int] = []
    try renderer.renderDocument(expressions) { index, result in
      indices.append(index)
      #expect(result.issue == nil && result.html.contains("class=\"katex\""))
    }
    #expect(indices == Array(0..<200))
    struct Stop: Error {}
    var consumed = 0
    #expect(throws: Stop.self) {
      try renderer.renderDocument([
        MathExpression(#"\newcommand{\privateField}{A}"#, display: false),
        MathExpression(#"\privateField"#, display: false),
      ]) { _, _ in
        consumed += 1
        throw Stop()
      }
    }
    #expect(consumed == 1)
    let next = try renderer.renderDocument([MathExpression(#"\privateField"#, display: false)])
    #expect(next.first?.issue != nil)
  }

  @Test("Cached TeX annotations retain exact composed and decomposed UTF8 source")
  func annotationBytes() throws {
    let renderer = MathRenderer()
    let composed = #"\text{é}"#
    let decomposed = "\\text{e\u{301}}"
    for document in [false, true] {
      func render(_ source: String) throws -> RenderedMath {
        if document {
          let values = try renderer.renderDocument([MathExpression(source, display: false)])
          return try #require(values.first)
        }
        return try renderer.render(source, display: false)
      }
      for source in [composed, decomposed] {
        let result = try render(source)
        #expect(result.issue == nil)
        let annotation = "<annotation encoding=\"application/x-tex\">" + source + "</annotation>"
        #expect(Data(result.html.utf8).range(of: Data(annotation.utf8)) != nil)
      }
    }
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

  @Test(
    "Wrapped equations keep native positions for following math and Markdown",
    arguments: ["\n", "\r\n", "\r"])
  func wrappedEquations(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    for (opening, closing, display) in [
      ("$", "$", false), ("$$", "$$", true), (#"\\("#, #"\\)"#, false),
      (#"\("#, #"\)"#, false), (#"\["#, #"\]"#, true), (#"\\["#, #"\\]"#, true),
    ] {
      for (prefix, continuation) in [("", ""), ("> ", "> "), ("- ", "  ")] {
        let before = prefix + "😀 Before "
        let end = continuation + "+c" + closing
        let after = end + " **after** "
        let source =
          before + opening + "a_b" + newline + after + opening + "d" + closing
          + newline + newline + "# Heading 😀"
        let parsed = try await MarkdownProcessor().render(
          source, options: options, includeSyntax: true)
        let equations = parsed.nodes.filter {
          if case .math = $0.kind { return true }
          return false
        }
        #expect(equations.count == 2, "\(source.debugDescription)")
        let first = try #require(equations.first)
        #expect(first.kind == .math(display: display))
        #expect(first.literal == "a_b\n+c")
        #expect(
          first.range
            == .init(
              start: .init(line: 1, column: before.utf8.count + 1),
              end: .init(line: 2, column: end.utf8.count)))
        #expect(
          equations.last?.range
            == .init(
              start: .init(line: 2, column: after.utf8.count + 1),
              end: .init(
                line: 2, column: after.utf8.count + opening.utf8.count + 1 + closing.utf8.count)))
        #expect(
          parsed.nodes.first { $0.kind == .strong }?.range
            == .init(
              start: .init(line: 2, column: end.utf8.count + 2),
              end: .init(line: 2, column: end.utf8.count + 10)))
        #expect(parsed.notices.isEmpty)
        #expect(parsed.headings.first?.sourceLine == 4)
        #expect(
          parsed.headings.first?.utf16Offset == (source as NSString).range(of: "# Heading").location
        )
        let syntax = try #require(parsed.syntax)
        let word = (source as NSString).range(of: "after")
        #expect(
          syntax.runs.first { NSLocationInRange(word.location, $0.range) }?.style.bold == true)
        let body = (source as NSString).range(of: "a_b")
        #expect(
          syntax.runs.first { NSLocationInRange(body.location, $0.range) }?.style.role == .code)
      }
    }
  }

  @Test("Wrapped math does not cross paragraph, list, quote or fenced-code boundaries")
  func wrappedBoundaries() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    for source in [
      "$a\n\nb$", "- $a\n- b$", "> $a\n\nb$", "$a\n```text\nb$\n```",
      "`$a\nb$`", "![$a\nb$](image.png)", "[link](https://example.com/$a$)",
    ] {
      let parsed = try await MarkdownProcessor().render(source, options: options)
      #expect(parsed.mathExpressions == 0, "\(source.debugDescription)")
    }
  }

  @Test("Bracket delimiters preserve TeX escapes and are independent of single-dollar preference")
  func bracketEquations() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    let processor = MarkdownProcessor()
    for (opening, closing, display, legacy) in [
      (#"\("#, #"\)"#, false, false), (#"\["#, #"\]"#, true, false),
      (#"\\("#, #"\\)"#, false, true), (#"\\["#, #"\\]"#, true, true),
    ] {
      let tex = #"\left\{\frac{a_b}{c}\right\}"#
      let body = legacy ? tex.replacingOccurrences(of: #"\"#, with: #"\\"#) : tex
      let source = "😀 Before " + opening + body + closing + " **after** $d$"
      let result = try await processor.render(source, options: options, includeSyntax: true)
      #expect(result.mathExpressions == 1, "\(source.debugDescription)")
      let math = try #require(
        result.nodes.first {
          if case .math = $0.kind { return true }
          return false
        })
      #expect(math.kind == .math(display: display))
      #expect(math.literal == tex)
      #expect(
        math.range
          == .init(
            start: .init(line: 1, column: "😀 Before ".utf8.count + 1),
            end: .init(
              line: 1,
              column: "😀 Before ".utf8.count + opening.utf8.count + body.utf8.count
                + closing.utf8.count)))
      #expect(result.notices.isEmpty)
      #expect(result.html.contains("$d$"))
      #expect(result.html.contains("<strong>after</strong>"))
      #expect(try await processor.render(source).mathExpressions == 0)
    }
  }

  @Test(
    "Bracket math respects native code, alt text, destinations, unmatched delimiters and block boundaries"
  )
  func bracketBoundaries() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    for (opening, closing) in [
      (#"\("#, #"\)"#), (#"\["#, #"\]"#), (#"\\("#, #"\\)"#), (#"\\["#, #"\\]"#),
    ] {
      for source in [
        "`" + opening + "a" + closing + "`",
        "![" + opening + "a" + closing + "](image.png)",
        opening + "a\n\nb" + closing,
        "- " + opening + "a\n- b" + closing,
        "> " + opening + "a\n\nb" + closing,
        opening + "a\n```text\nb" + closing + "\n```",
        "```text\n" + opening + "a" + closing + "\n```",
        opening + "a", "a" + closing,
      ] {
        let result = try await MarkdownProcessor().render(source, options: options)
        #expect(result.mathExpressions == 0, "\(source.debugDescription)")
      }
    }
    for source in [#"\(a\\)"#, #"\\(a\)"#, #"\[a\\]"#, #"\\[a\]"#, #"\\\(a\\\)"#] {
      #expect(try await MarkdownProcessor().render(source, options: options).mathExpressions == 0)
    }
    let unmatched = String(repeating: #"\( unmatched "#, count: 10_000) + "\n\n# After"
    let result = try await MarkdownProcessor().render(unmatched, options: options)
    #expect(result.mathExpressions == 0)
    #expect(result.headings.first?.sourceLine == 3)
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
