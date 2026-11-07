import Foundation
import Testing

@testable import MarkdownCore

@Suite("Physical Markdown source coordinates")
struct MarkdownSourceCoordinateTests {
  @Test(
    "Lazy container continuations and partial tabs retain physical inline byte columns",
    arguments: ["\n", "\r\n", "\r"])
  func containerColumns(_ newline: String) async throws {
    for (prefix, continuation) in [
      ("- first", ""), ("> first", ""), ("> - first", ""),
      ("- first", "\t"), ("1. first", "\t"), ("- first", "  "),
      ("- first", "    "), (">\tfirst", "> "), ("first", "\t"), ("first", "   "),
    ] {
      let marker = "**中文 😀**"
      let source = prefix + newline + continuation + marker + " tail"
      let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
      let strong = try #require(
        parsed.nodes.first { $0.kind == .strong }, "\(source.debugDescription)")
      #expect(
        strong.range?.start == .init(line: 2, column: continuation.utf8.count + 1),
        "\(source.debugDescription): \(String(describing: strong.range))")
      #expect(
        strong.range?.end == .init(line: 2, column: continuation.utf8.count + marker.utf8.count),
        "\(source.debugDescription): \(String(describing: strong.range))")
      let syntax = try #require(parsed.syntax)
      let text = source as NSString
      let expected = text.range(of: marker)
      let actual = syntax.runs.filter { $0.style.tokens.contains(.strong) }.map(\.range)
      #expect(actual == [expected], "\(source.debugDescription): \(actual)")
      #expect(parsed.html.contains("<strong>中文 😀</strong> tail"))
      let plain = try await MarkdownProcessor().render(source)
      #expect(plain.html == parsed.html && plain.nodes == parsed.nodes)
    }
  }

  private func expected(_ marker: String, in source: String) throws -> MarkdownSourceRange {
    let range = try #require(source.range(of: marker))
    let lower = source[..<range.lowerBound].utf8.count
    let upper = source[..<range.upperBound].utf8.count - 1
    let lines = MarkdownSourceMetadata.lineRanges(Array(source.utf8))
    let first = try #require(lines.lastIndex { $0.lowerBound <= lower })
    let last = try #require(lines.lastIndex { $0.lowerBound <= upper })
    return .init(
      start: .init(line: first + 1, column: lower - lines[first].lowerBound + 1),
      end: .init(line: last + 1, column: upper - lines[last].lowerBound + 1))
  }

  private func expect(
    _ kind: MarkdownNodeKind, _ marker: String, source: String, parsed: RenderedMarkdown
  ) throws {
    let node = try #require(
      parsed.nodes.first { $0.kind == kind }, "\(source.debugDescription): \(kind)")
    let wanted = try expected(marker, in: source)
    #expect(
      node.range == wanted,
      "\(source.debugDescription): \(kind), \(String(describing: node.range))")
  }

  @Test("Inline extensions and nested native scopes share the exact physical source columns")
  func extensionColumns() async throws {
    var options = MarkdownRenderingOptions()
    options.underline = true
    options.highlight = true
    options.superscript = true
    options.math = true
    options.inlineDollarMath = true
    options.codeHighlighting = false
    for prefix in ["", "> ", "- ", ">\t", "> - "] {
      for policy in [MarkdownEmphasisPolicy.standard, .allowWithinWords] {
        options.emphasisPolicy = policy
        let source =
          prefix
          + "x _under **bold** &amp;_ *after* ==mark== x^up $x$ [label](https://e.invalid) ![alt](a.png) `literal`"
        let parsed = try await MarkdownProcessor().render(
          source, options: options, includeSyntax: true)
        for (kind, marker) in [
          (MarkdownNodeKind.underline, "_under **bold** &amp;_"), (.strong, "**bold**"),
          (.emphasis, "*after*"), (.highlight, "==mark=="), (.superscript, "^up"),
          (.math(display: false), "$x$"), (.link, "[label](https://e.invalid)"),
          (.image, "![alt](a.png)"), (.inlineCode, "literal"),
        ] { try expect(kind, marker, source: source, parsed: parsed) }
        let entity = (source as NSString).range(of: "&amp;")
        let syntax = try #require(parsed.syntax)
        #expect(syntax.runs.contains { $0.range == entity && $0.style.tokens.contains(.entity) })
      }
    }
  }

  @Test(
    "Recursive and multiline inline contexts preserve both endpoints and following spans",
    arguments: ["\n", "\r\n", "\r"])
  func multilineContexts(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.underline = true
    options.quotedText = true
    options.highlight = true
    options.rawHTML = true
    options.codeHighlighting = false
    for policy in [MarkdownEmphasisPolicy.standard, .allowWithinWords] {
      options.emphasisPolicy = policy
      for (opening, closing, kind) in [
        ("_", "_", MarkdownNodeKind.underline), ("\"", "\"", .quotation),
        ("[", "](https://e.invalid)", .link),
      ] {
        let marker = opening + "start" + newline + "**中文** &amp; end" + closing
        let source = "> before " + marker + " *after*"
        let parsed = try await MarkdownProcessor().render(
          source, options: options, includeSyntax: true)
        try expect(kind, marker, source: source, parsed: parsed)
        try expect(.strong, "**中文**", source: source, parsed: parsed)
        try expect(.emphasis, "*after*", source: source, parsed: parsed)
        let plain = try await MarkdownProcessor().render(source, options: options)
        #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
      }
      let code = "one" + newline + "中文"
      let source = "> before `" + code + "` *after*"
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      try expect(.inlineCode, code, source: source, parsed: parsed)
      try expect(.emphasis, "*after*", source: source, parsed: parsed)
    }
    let tag = "<span" + newline + "class=\"x\">"
    let source = "> before " + tag + "text</span> *after*"
    let parsed = try await MarkdownProcessor().render(source, options: options)
    try expect(.html, tag, source: source, parsed: parsed)
    try expect(.emphasis, "*after*", source: source, parsed: parsed)
  }

}
