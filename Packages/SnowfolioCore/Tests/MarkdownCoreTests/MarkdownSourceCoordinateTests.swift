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

  @Test(
    "Table-cell normalization preserves exact source ranges and code escape boundaries",
    arguments: ["\n", "\r\n", "\r"])
  func tableCells(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    for (headerPrefix, bodyPrefix) in [
      ("", ""), ("> ", "> "), ("- ", "  "),
      ("> ", "  > "), ("- ", "\t"),
    ] {
      for leading in ["", " ", "\t", " \t "] {
        for escapes in [0, 1, 2, 8] {
          let escaped = String(repeating: "a\\|", count: escapes)
          let source = [
            headerPrefix + "|" + leading + escaped + "**Header 😀** | Other |",
            (headerPrefix == "- " ? "  " : headerPrefix) + "|---|---|",
            bodyPrefix + "|" + leading + escaped
              + "**Body 中文** *after* | `\\|` [left\\|right](https://e.invalid) |",
          ].joined(separator: newline)
          let parsed = try await MarkdownProcessor().render(
            source, options: options, includeSyntax: true)
          #expect(parsed.nodes.contains { $0.kind == .table }, "\(source.debugDescription)")
          let rows = parsed.nodes.filter { $0.kind == .tableRow }.compactMap(\.range)
          let physicalLines = source.components(separatedBy: newline)
          let wantedRows = try [
            expected(String(physicalLines[0].dropFirst(headerPrefix.count)), in: source),
            expected(String(physicalLines[2].dropFirst(bodyPrefix.count)), in: source),
          ]
          #expect(rows == wantedRows, "\(source.debugDescription): \(rows)")
          let strong = parsed.nodes.filter { $0.kind == .strong }.compactMap(\.range)
          let wanted = try [
            expected("**Header 😀**", in: source), expected("**Body 中文**", in: source),
          ]
          #expect(strong == wanted, "\(source.debugDescription): \(strong)")
          try expect(.emphasis, "*after*", source: source, parsed: parsed)
          let codeMarker = try expected("`\\|`", in: source)
          let codeNode = try #require(parsed.nodes.first { $0.kind == .inlineCode })
          #expect(
            codeNode.range
              == .init(
                start: .init(line: codeMarker.start.line, column: codeMarker.start.column + 1),
                end: .init(line: codeMarker.end.line, column: codeMarker.end.column - 1)),
            "\(source.debugDescription): \(String(describing: codeNode.range))")
          try expect(.link, "[left\\|right](https://e.invalid)", source: source, parsed: parsed)
          #expect(parsed.nodes.first { $0.kind == .inlineCode }?.literal == "|")
          let syntax = try #require(parsed.syntax)
          let code = (source as NSString).range(of: "`\\|`")
          for offset in code.location..<NSMaxRange(code) {
            #expect(
              syntax.runs.contains {
                NSLocationInRange(offset, $0.range) && $0.style.tokens.contains(.inlineCode)
              })
          }
          let bold = syntax.runs.filter { $0.style.tokens.contains(.strong) }.map(\.range)
          #expect(
            bold == [
              (source as NSString).range(of: "**Header 😀**"),
              (source as NSString).range(of: "**Body 中文**"),
            ])
          let plain = try await MarkdownProcessor().render(source, options: options)
          #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
        }
      }
    }
  }

  @Test("Table cells preserve Swift inline dialects and their nested source ranges")
  func tableInlineDialects() async throws {
    var options = MarkdownRenderingOptions()
    options.underline = true
    options.highlight = true
    options.superscript = true
    options.quotedText = true
    options.codeHighlighting = false
    options.math = true
    options.inlineDollarMath = true
    for policy in [MarkdownEmphasisPolicy.standard, .allowWithinWords] {
      options.emphasisPolicy = policy
      let source =
        "| Header | Other |\n|---|---|\n| a\\|b _under **b\\|old**_ ==mark== x^up $x$ \"quoted\" | Value |"
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      for (kind, marker) in [
        (MarkdownNodeKind.underline, "_under **b\\|old**_"), (.strong, "**b\\|old**"),
        (.highlight, "==mark=="), (.superscript, "^up"), (.math(display: false), "$x$"),
        (.quotation, "\"quoted\""),
      ] { try expect(kind, marker, source: source, parsed: parsed) }
      #expect(parsed.html.contains("<u>under <strong>b|old</strong></u>"))
      #expect(parsed.html.contains("<mark>mark</mark>") && parsed.html.contains("<sup>up</sup>"))
      #expect(parsed.html.contains("<q>quoted</q>"))
    }
  }

  @Test("Sparse table provenance handles long escaped cells and discarded or missing cells")
  func tableRecovery() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let dense =
      "| Header | Other |\n|---|---|\n| " + String(repeating: "a\\|", count: 8192)
      + "**target** | Value |"
    let parsed = try await MarkdownProcessor().render(dense, options: options, includeSyntax: true)
    try expect(.strong, "**target**", source: dense, parsed: parsed)
    for prefix in [
      "| a\\|b | c |\n|---|---|---|", "| a\\|b |\nnot a delimiter",
      "| A | B |\n|---|---|\n| `\\|` |",
      "| A | B |\n|---|---|\n| a\\|b | more | discarded\\|cell |",
    ] {
      let source = prefix + "\n\ncheckpoint **after**"
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      try expect(.strong, "**after**", source: source, parsed: parsed)
      #expect(parsed.html.contains("checkpoint <strong>after</strong>"))
    }
  }

  @Test(
    "A table split from a preceding paragraph preserves literals and exact block and inline ranges",
    arguments: ["\n", "\r\n", "\r"])
  func tableParagraphSplit(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    for (prefix, headerPrefix, bodyPrefix) in [
      ("", "", ""), ("  ", " ", "   "), ("> ", "  > ", "> "),
      ("- ", "  ", "\t"), ("> - ", ">   ", ">   "),
    ] {
      let paragraph = "before **lead 😀** `a\\|b`"
      let header = "| a\\|b **Header 中文** | Other |"
      let body = "| **Body** | Value |"
      let source = [
        prefix + paragraph, headerPrefix + header,
        headerPrefix + "|---|---|", bodyPrefix + body,
      ].joined(separator: newline)
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      try expect(.paragraph, paragraph, source: source, parsed: parsed)
      for marker in ["**lead 😀**", "**Header 中文**", "**Body**"] {
        let wanted = try expected(marker, in: source)
        #expect(
          parsed.nodes.contains { $0.kind == .strong && $0.range == wanted },
          "\(source.debugDescription): \(marker), \(parsed.nodes)")
      }
      let table = try #require(parsed.nodes.first { $0.kind == .table })
      let headerRange = try expected(header, in: source)
      let bodyRange = try expected(body, in: source)
      #expect(
        table.range?.start == headerRange.start && table.range?.end == bodyRange.end,
        "\(source.debugDescription): \(String(describing: table.range))")
      #expect(parsed.nodes.first { $0.kind == .tableRow }?.range == headerRange)
      #expect(
        parsed.html.contains("<code>a\\|b</code>"), "\(source.debugDescription): \(parsed.html)")
      let plain = try await MarkdownProcessor().render(source, options: options)
      #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
    }
  }

  @Test(
    "Split paragraphs retain multiline ranges and ordinary native reference definitions",
    arguments: ["\n", "\r\n", "\r"])
  func tableSplitReferences(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    for (prefix, continuation, headerPrefix) in [
      ("", "", ""), ("  ", " ", "   "), ("> ", "> ", "  > "),
      ("- ", "  ", "\t"), ("> - ", ">   ", ">   "),
    ] {
      for leadingPipe in ["", "| "] {
        let definition = "[target]: /value \"Title\""
        let first = "paragraph **before** [target] &amp; `a\\|b`"
        let second = "more **middle**"
        let header = leadingPipe + "a\\|b **Header 中文** | Other |"
        let body = "| **Body** | Value |"
        let source = [
          prefix + definition, continuation + first, continuation + second,
          headerPrefix + header, headerPrefix + "|---|---|", continuation + body,
        ]
        .joined(separator: newline)
        let parsed = try await MarkdownProcessor().render(
          source, options: options, includeSyntax: true)
        let paragraph = try #require(parsed.nodes.first { $0.kind == .paragraph })
        #expect(
          paragraph.range
            == .init(
              start: try expected(first, in: source).start,
              end: try expected(second, in: source).end), "\(source.debugDescription)")
        for marker in ["**before**", "**middle**", "**Header 中文**", "**Body**"] {
          let wanted = try expected(marker, in: source)
          #expect(
            parsed.nodes.contains { $0.kind == .strong && $0.range == wanted },
            "\(source.debugDescription): \(marker)")
        }
        try expect(.tableRow, header, source: source, parsed: parsed)
        #expect(parsed.nodes.first { $0.kind == .link }?.destination == "/value")
        #expect(
          parsed.html.contains("title=\"Title\"") && parsed.html.contains("<code>a\\|b</code>"))
        let syntax = try #require(parsed.syntax)
        let text = source as NSString
        #expect(
          syntax.runs.contains {
            NSLocationInRange(text.range(of: definition).location, $0.range)
              && $0.style.tokens.contains(.referenceDefinition)
          })
        for marker in ["paragraph", "more", "Header"] {
          #expect(
            !syntax.runs.contains {
              NSLocationInRange(text.range(of: marker).location, $0.range)
                && $0.style.tokens.contains(.referenceDefinition)
            }, "\(source.debugDescription): \(marker)")
        }
        let plain = try await MarkdownProcessor().render(source, options: options)
        #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
      }
    }
  }

  @Test(
    "Definition-only table prefixes resolve and disappear without consuming table scopes",
    arguments: ["\n", "\r\n", "\r"])
  func tableDefinitionOnly(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    for (prefix, continuation) in [("", ""), ("> ", "> "), ("- ", "  ")] {
      let source = [
        prefix + "[target]: /value", continuation + "| [target] **Header** | Other |",
        continuation + "|---|---|", continuation + "| **Body** | Value |",
      ].joined(separator: newline)
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      #expect(!parsed.nodes.contains { $0.kind == .paragraph })
      #expect(parsed.nodes.first { $0.kind == .link }?.destination == "/value")
      try expect(.strong, "**Header**", source: source, parsed: parsed)
      #expect(parsed.nodes.first { $0.kind == .table }?.range?.start.line == 2)
      #expect(!parsed.html.contains("[target]:"))
      let syntax = try #require(parsed.syntax)
      let header = (source as NSString).range(of: "Header").location
      #expect(
        syntax.runs.contains {
          NSLocationInRange(header, $0.range) && $0.style.tokens.contains(.strong)
            && !$0.style.tokens.contains(.referenceDefinition)
        })
      let plain = try await MarkdownProcessor().render(source, options: options)
      #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
    }
  }

  @Test(
    "Split tables inside footnotes keep note ancestry and following ordinary source scopes",
    arguments: ["\n", "\r\n", "\r"])
  func tableSplitFootnote(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.footnotes = true
    let source = [
      "[^a]: [target]: /value", "    before **lead** `a\\|b`",
      "    | [target] **Header** | Other |", "    |---|---|", "    | **Body** | Value |",
      "", "note[^a] and **after**",
    ].joined(separator: newline)
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    for marker in ["**lead**", "**Header**", "**Body**", "**after**"] {
      let wanted = try expected(marker, in: source)
      #expect(
        parsed.nodes.contains { $0.kind == .strong && $0.range == wanted },
        "\(source.debugDescription): \(marker)")
    }
    #expect(parsed.nodes.first { $0.kind == .link }?.destination == "/value")
    #expect(parsed.html.contains("<code>a\\|b</code>"))
    let syntax = try #require(parsed.syntax)
    let text = source as NSString
    for marker in ["lead", "Header", "Body"] {
      #expect(
        syntax.runs.contains {
          NSLocationInRange(text.range(of: marker).location, $0.range)
            && $0.style.tokens.contains(.note) && $0.style.tokens.contains(.strong)
            && !$0.style.tokens.contains(.referenceDefinition)
        })
    }
    let after = text.range(of: "after").location
    #expect(
      syntax.runs.contains {
        NSLocationInRange(after, $0.range) && $0.style.tokens == [.strong]
      })
    let plain = try await MarkdownProcessor().render(source, options: options)
    #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
  }

}
