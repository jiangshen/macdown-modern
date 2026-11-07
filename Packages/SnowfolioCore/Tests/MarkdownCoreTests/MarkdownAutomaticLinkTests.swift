import Foundation
import Testing

@testable import MarkdownCore

@Suite("Automatic link source coordinates")
struct MarkdownAutomaticLinkTests {
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

  private func ranges(_ token: MarkdownSyntaxToken, syntax: MarkdownSyntax) -> [NSRange] {
    var result: [NSRange] = []
    for run in syntax.runs where run.style.tokens.contains(token) {
      if let last = result.last, NSMaxRange(last) == run.range.location {
        result[result.count - 1].length += run.range.length
      } else {
        result.append(run.range)
      }
    }
    return result
  }

  private func check(
    _ markers: [String], source: String, options: MarkdownRenderingOptions,
    token: MarkdownSyntaxToken, labels: [String]? = nil
  ) async throws {
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    let links = parsed.nodes.filter { $0.kind == .link }
    #expect(links.count == markers.count, "\(source.debugDescription)")
    if let labels { try #require(labels.count == markers.count) }
    for (index, pair) in zip(links, markers).enumerated() {
      let (link, marker) = pair
      #expect(
        link.range == (try expected(marker, source: source)),
        "\(source.debugDescription): \(marker): \(String(describing: link.range))")
      let child = try #require(parsed.nodes.first { $0.parentID == link.id && $0.kind == .text })
      #expect(
        child.range == (try expected(labels?[index] ?? marker, source: source)),
        "\(source.debugDescription): \(marker)")
    }
    let syntax = try #require(parsed.syntax)
    #expect(
      ranges(token, syntax: syntax) == markers.map { (source as NSString).range(of: $0) },
      "\(source.debugDescription)")
    let plain = try await MarkdownProcessor().render(source, options: options)
    #expect(plain.html == parsed.html && plain.nodes == parsed.nodes)
  }

  @Test(
    "Native URL and www links use their exact contextual byte columns",
    arguments: ["\n", "\r\n", "\r"])
  func urls(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.underline = true
    options.quotedText = true
    for marker in ["https://example.com/中文", "www.example.com", "http://example.com/a_(b)"] {
      for (prefix, suffix) in [
        ("before ", " after"), ("before &amp; ", " after"), ("before \\* ", " after"),
        ("- first" + newline, " after"), ("- first" + newline + "\t", " after"),
        ("> first" + newline, " after"), ("> - first" + newline + ">   ", " after"),
        ("# before ", " after"), ("> before \"", "\" after"),
        ("| Header | Other |" + newline + "|---|---|" + newline + "| a\\|b ", " after | Value |"),
      ] {
        try await check(
          [marker], source: prefix + marker + suffix, options: options, token: .automaticURL)
      }
    }
  }

  @Test(
    "Native email partitions preserve literals, entities, containers and repeated source ranges",
    arguments: ["\n", "\r\n", "\r"])
  func emails(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.underline = true
    for marker in [
      "user@example.com", "user&#64;example.com", "us&#101;r@example.com",
      "user\\_name@example.com",
    ] {
      for (prefix, suffix) in [
        ("before ", " after"), ("before &amp; ", " after"), ("before \\* ", " after"),
        ("- first" + newline, " after"), ("- first" + newline + "\t", " after"),
        ("> first" + newline, " after"), ("# before ", " after"), ("> before _", "_ after"),
        ("| Header | Other |" + newline + "|---|---|" + newline + "| a\\|b ", " after | Value |"),
      ] {
        try await check(
          [marker], source: prefix + marker + suffix, options: options, token: .automaticEmail)
      }
    }
    try await check(
      ["one@example.com", "two@example.org", "three&#64;example.net"],
      source: "one@example.com and &amp; two@example.org; then three&#64;example.net after",
      options: options, token: .automaticEmail)
  }
  @Test("URL rewinding does not leave stale source spans on surrounding text")
  func urlTextFragments() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let source = "lead https://example.com tail www.example.org end"
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    for marker in ["lead ", " tail ", " end"] {
      let node = try #require(parsed.nodes.first { $0.kind == .text && $0.literal == marker })
      #expect(node.range == (try expected(marker, source: source)), "\(marker.debugDescription)")
    }
    let bare = try await MarkdownProcessor().render("https://example.com", options: options)
    #expect(
      bare.nodes.filter { $0.kind == .text && $0.literal == "" }.allSatisfy { $0.range == nil })
  }

  @Test(
    "Email provenance retains protocol, multi-character entity and footnote boundaries",
    arguments: ["\n", "\r\n", "\r"])
  func emailDialects(_ newline: String) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.footnotes = true
    options.smartPunctuation = true
    for marker in [
      "mailto:user@example.com", "&fjlig;user@example.com",
      "user&lowbar;name@example.com",
    ] {
      try await check(
        [marker], source: "before ... " + marker + " after", options: options,
        token: .automaticEmail)
    }
    // Native GFM recognizes only the address after an uppercase protocol prefix.
    try await check(
      ["User@example.com"], source: "before ... MAILTO:User@example.com after",
      options: options, token: .automaticEmail)
    try await check(
      ["xmpp:user@example.com/resource"],
      source: "before xmpp:user@example.com/resource after", options: options, token: .automaticURL)
    try await check(
      ["user&#64;example.com"],
      source: ["[^a]: before user&#64;example.com after", "", "note[^a] **outside**"].joined(
        separator: newline),
      options: options, token: .automaticEmail)
    try await check(
      ["[user@example.com](https://example.org)"],
      source: "before [user@example.com](https://example.org) after", options: options,
      token: .link,
      labels: ["user@example.com"]
    )
  }

  @Test("Repeated email partitions in an escaped cell retain first and last source positions")
  func repeatedCell() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let markers = (0..<2048).map { "user\($0)@example.com" }
    let source =
      "| Header | Other |\n|---|---|\n| " + String(repeating: "a\\|", count: 8192)
      + markers.joined(separator: " ") + " after | Value |\n\n**outside**"
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    let links = parsed.nodes.filter { $0.kind == .link }
    #expect(links.count == markers.count)
    #expect(links.first?.range == (try expected(markers[0], source: source)))
    #expect(links.last?.range == (try expected(markers[markers.count - 1], source: source)))
    let syntax = try #require(parsed.syntax)
    let spans = ranges(.automaticEmail, syntax: syntax)
    #expect(spans.count == markers.count)
    #expect(spans.first == (source as NSString).range(of: markers[0]))
    #expect(spans.last == (source as NSString).range(of: markers[markers.count - 1]))
    #expect(
      parsed.nodes.first { $0.kind == .strong }?.range
        == (try expected("**outside**", source: source)))
    let plain = try await MarkdownProcessor().render(source, options: options)
    #expect(plain.nodes == parsed.nodes && plain.html == parsed.html)
  }

  @Test("Discarded footnote groups cannot supply source ranges for a remaining identical email")
  func unusedFootnote() async throws {
    var options = MarkdownRenderingOptions()
    options.footnotes = true
    options.codeHighlighting = false
    let source = "[^unused]: user@example.com\n\nuser@example.com"
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    let links = parsed.nodes.filter { $0.kind == .link }
    #expect(links.count == 1)
    #expect(
      links.first?.range == .init(start: .init(line: 3, column: 1), end: .init(line: 3, column: 16))
    )
    let syntax = try #require(parsed.syntax)
    #expect(
      ranges(.automaticEmail, syntax: syntax) == [
        (source as NSString).range(of: "user@example.com", options: .backwards)
      ])
  }

}
