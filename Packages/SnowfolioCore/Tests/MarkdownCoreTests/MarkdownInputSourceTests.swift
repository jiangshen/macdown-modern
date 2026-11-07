import Foundation
import Testing

@testable import MarkdownCore

@Suite("Native input normalization source coordinates")
struct MarkdownInputSourceTests {
  private func expected(_ marker: String, source: String) throws -> MarkdownSourceRange {
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

  @Test(
    "Native NUL replacement retains physical strong and block bounds",
    arguments: ["\n", "\r\n", "\r"])
  func strong(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    for nulls in [1, 2, 8] {
      for (prefix, suffix) in [
        ("before", " tail"), ("> before", " tail"), ("# before", " tail"),
        ("- first" + newline, " tail"), ("- first" + newline + "\t", " tail"),
        ("| Header | Other |" + newline + "|---|---|" + newline + "| before", " tail | Value |"),
        ("literal � before", " tail"),
      ] {
        let marker = "**中文 😀**"
        let source = prefix + String(repeating: "\0", count: nulls) + " " + marker + suffix
        let parsed = try await MarkdownProcessor().render(
          source, options: options, includeSyntax: true)
        #expect(
          parsed.nodes.first { $0.kind == .strong }?.range
            == (try expected(marker, source: source)), "\(source.debugDescription)")
        let syntax = try #require(parsed.syntax)
        #expect(
          syntax.runs.filter { $0.style.tokens.contains(.strong) }.map(\.range)
            == [(source as NSString).range(of: marker)], "\(source.debugDescription)")
        let lines = MarkdownSourceMetadata.lineRanges(Array(source.utf8))
        for node in parsed.nodes {
          if let range = node.range, range.end.line > 0, range.end.line <= lines.count {
            #expect(
              range.end.column <= lines[range.end.line - 1].count,
              "\(source.debugDescription): \(node)")
          }
        }
        let plain = try await MarkdownProcessor().render(source, options: options)
        #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
      }
    }
  }

  @Test("NULs within source spans retain literal replacement characters and code delimiters")
  func interiors() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    for (source, marker, kind) in [
      ("before **a\0�b** tail", "**a\0�b**", MarkdownNodeKind.strong),
      ("before `a\0�b` tail", "a\0�b", .inlineCode),
      ("before\0 https://example.com tail", "https://example.com", .link),
      ("before\0 user&#64;example.com tail", "user&#64;example.com", .link),
    ] {
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      #expect(
        parsed.nodes.first { $0.kind == kind }?.range == (try expected(marker, source: source)),
        "\(source.debugDescription)")
      #expect(parsed.html.contains("�"))
      let plain = try await MarkdownProcessor().render(source, options: options)
      #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
    }
  }

  private func expectNode(
    _ kind: MarkdownNodeKind, marker: String, source: String, parsed: RenderedMarkdown
  ) throws {
    let wanted = try expected(marker, source: source)
    #expect(
      parsed.nodes.contains { $0.kind == kind && $0.range == wanted },
      "\(source.debugDescription): \(marker)")
  }

  @Test(
    "NUL projections compose with reference removal, table splitting and escaped cells",
    arguments: ["\n", "\r\n", "\r"])
  func referenceTables(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let label = "tar\0get"
    let definition = "[\(label)]: /value \"Ti\0tle\""
    for (prefix, continuation) in [("", ""), ("> ", "> "), ("- ", "  "), ("> - ", ">   ")] {
      for onlyDefinition in [false, true] {
        var rows = [prefix + definition]
        if !onlyDefinition { rows.append(continuation + "before\0 **lead 中文** `a\\|b`") }
        rows += [
          continuation + "| a\\|b\0 [\(label)] **Header 😀** | Other |",
          continuation + "|---|---|", continuation + "| \0**Body** | Value |",
        ]
        let source = rows.joined(separator: newline)
        let parsed = try await MarkdownProcessor().render(
          source, options: options, includeSyntax: true)
        #expect(parsed.nodes.first { $0.kind == .link }?.destination == "/value")
        #expect(parsed.html.contains("title=\"Ti�tle\""))
        #expect(!parsed.html.contains("[tar"))
        for marker in (onlyDefinition ? [] : ["**lead 中文**"]) + ["**Header 😀**", "**Body**"] {
          try expectNode(.strong, marker: marker, source: source, parsed: parsed)
        }
        let syntax = try #require(parsed.syntax)
        let text = source as NSString
        let definitionRange = text.range(of: definition)
        for offset in definitionRange.location..<NSMaxRange(definitionRange) {
          #expect(
            syntax.runs.contains {
              NSLocationInRange(offset, $0.range)
                && $0.style.tokens.contains(.referenceDefinition)
            }, "\(source.debugDescription): \(offset)")
        }
        for marker in ["Header", "Body"] {
          #expect(
            !syntax.runs.contains {
              NSLocationInRange(text.range(of: marker).location, $0.range)
                && $0.style.tokens.contains(.referenceDefinition)
            })
        }
        let plain = try await MarkdownProcessor().render(source, options: options)
        #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
      }
    }
  }

  @Test(
    "NUL note labels and bodies keep note ancestry and ordinary text independent",
    arguments: ["\n", "\r\n", "\r"])
  func footnotes(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.footnotes = true
    options.codeHighlighting = false
    let source = [
      "[^a\0b]: [target]: /value \"Ti\0tle\"", "    before\0 **lead** `a\\|b`",
      "    | [target] \0**Header** | Other |", "    |---|---|", "    | \0**Body** | Value |",
      "", "note[^a\0b] and \0**after**",
    ].joined(separator: newline)
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    let syntax = try #require(parsed.syntax)
    let text = source as NSString
    for marker in ["**lead**", "**Header**", "**Body**", "**after**"] {
      try expectNode(.strong, marker: marker, source: source, parsed: parsed)
      let offset = text.range(of: marker).location
      let tokens = try #require(
        syntax.runs.first { NSLocationInRange(offset, $0.range) }?.style.tokens)
      #expect(tokens.contains(.strong))
      #expect(tokens.contains(.note) == (marker != "**after**"))
      #expect(!tokens.contains(.referenceDefinition))
    }
    #expect(parsed.nodes.first { $0.kind == .link }?.destination == "/value")
    let plain = try await MarkdownProcessor().render(source, options: options)
    #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
  }

  @Test("Native input expansion composes with recursive inline dialect and math ranges")
  func inlineDialects() async throws {
    var options = MarkdownRenderingOptions()
    options.underline = true
    options.highlight = true
    options.superscript = true
    options.quotedText = true
    options.math = true
    options.inlineDollarMath = true
    options.codeHighlighting = false
    for prefix in ["before\0 ", "> before\0 ", "| Header | Other |\n|---|---|\n| a\\|b\0 "] {
      let source =
        prefix + "_under\0 **bold 中文**_ ==mark\0== x^up $x$ \"quoted\0\" tail"
        + (prefix.hasPrefix("|") ? " | Value |" : "")
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      for (kind, marker) in [
        (MarkdownNodeKind.underline, "_under\0 **bold 中文**_"),
        (.strong, "**bold 中文**"), (.highlight, "==mark\0=="), (.superscript, "^up"),
        (.math(display: false), "$x$"), (.quotation, "\"quoted\0\""),
      ] {
        try expectNode(kind, marker: marker, source: source, parsed: parsed)
      }
      let plain = try await MarkdownProcessor().render(source, options: options)
      #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
    }
  }

  @Test(
    "NUL expansion spans feed boundaries and leaves physical CRLF and terminal positions intact")
  func feedBoundaries() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let marker = "**中文 😀**"
    let sources =
      [0, 65_534, 65_535, 65_536, 65_537, 131_071].map {
        String(repeating: "x", count: $0) + "\0\0 " + marker + " tail\0"
      } + [
        String(repeating: "x", count: 65_535) + "\r\n\0 " + marker + "\0",
        "\0\r\n" + marker + "\r\n\0\0", marker + "\0",
      ]
    for source in sources {
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      try expectNode(.strong, marker: marker, source: source, parsed: parsed)
      #expect(
        try #require(parsed.syntax).runs.filter { $0.style.tokens.contains(.strong) }.map(\.range)
          == [(source as NSString).range(of: marker)])
      let plain = try await MarkdownProcessor().render(source, options: options)
      #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
    }
  }

}
