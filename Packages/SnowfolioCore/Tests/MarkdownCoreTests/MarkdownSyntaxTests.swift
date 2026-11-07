import Foundation
import Testing

@testable import MarkdownCore

@Suite("Markdown source syntax")
struct MarkdownSyntaxTests {
  private func style(at text: String, in source: String, syntax: MarkdownSyntax) throws
    -> MarkdownSyntaxStyle
  {
    let range = (source as NSString).range(of: text)
    #expect(range.location != NSNotFound)
    return try #require(syntax.runs.first { NSLocationInRange(range.location, $0.range) }?.style)
  }

  @Test(
    "Nested source styles compose and preserve Unicode positions", arguments: ["\n", "\r\n", "\r"])
  func nestedStyles(_ newline: String) async throws {
    let source = [
      "# 中文 👩🏽‍💻", "", "**bold *italic*** and `**literal**` plus [link](https://example.com).", "",
      "~~gone~~", "", "> A quote", "", "- Item", "", "<!-- comment -->",
    ].joined(separator: newline)
    let result = try await MarkdownProcessor().render(source, includeSyntax: true)
    let syntax = try #require(result.syntax)
    #expect(try style(at: "中文", in: source, syntax: syntax).bold)
    #expect(try style(at: "中文", in: source, syntax: syntax).role == .heading)
    #expect(try style(at: "italic", in: source, syntax: syntax).bold)
    #expect(try style(at: "italic", in: source, syntax: syntax).italic)
    #expect(try style(at: "**literal**", in: source, syntax: syntax).role == .code)
    #expect(!(try style(at: "**literal**", in: source, syntax: syntax).bold))
    #expect(try style(at: "link", in: source, syntax: syntax).role == .link)
    #expect(try style(at: "gone", in: source, syntax: syntax).strikethrough)
    #expect(try style(at: "A quote", in: source, syntax: syntax).role == .quote)
    #expect(try style(at: "-", in: source, syntax: syntax).role == .marker)
    #expect(try style(at: "comment", in: source, syntax: syntax).role == .comment)
    for (index, run) in syntax.runs.enumerated() {
      #expect(run.range.length > 0)
      #expect(NSMaxRange(run.range) <= source.utf16.count)
      if index > 0 { #expect(NSMaxRange(syntax.runs[index - 1].range) <= run.range.location) }
      for boundary in [run.range.location, NSMaxRange(run.range)]
      where boundary < source.utf16.count {
        #expect(!(0xDC00...0xDFFF).contains((source as NSString).character(at: boundary)))
      }
    }
  }

  @Test("Indented/fenced code cannot style its literal Markdown as emphasis")
  func literalCode() async throws {
    let source = "\t**indented**\n\n```markdown\n# **literal**\n```\n\nNormal **emphasis**"
    let result = try await MarkdownProcessor().render(source, includeSyntax: true)
    let syntax = try #require(result.syntax)
    #expect(try style(at: "indented", in: source, syntax: syntax).role == .code)
    #expect(try style(at: "literal", in: source, syntax: syntax).role == .code)
    #expect(!(try style(at: "literal", in: source, syntax: syntax).bold))
    #expect(try style(at: "emphasis", in: source, syntax: syntax).bold)
  }

  @Test("Syntax generation is opt-in and does not change rendered/exported HTML")
  func optionalPresentation() async throws {
    let source = "# Heading\n\n**bold**"
    let plain = try await MarkdownProcessor().render(source)
    let styled = try await MarkdownProcessor().render(source, includeSyntax: true)
    #expect(plain.syntax == nil)
    #expect(styled.syntax != nil)
    #expect(plain.html == styled.html)
    #expect(plain.nodes == styled.nodes)
  }

  @Test("Many styled spans on one long Unicode line retain correct final positions")
  func longLine() async throws {
    let source = String(repeating: "**👩🏽‍💻 中文** ", count: 2000) + "*final*"
    let result = try await MarkdownProcessor().render(source, includeSyntax: true)
    let syntax = try #require(result.syntax)
    #expect(syntax.runs.count >= 2000)
    #expect(try style(at: "final", in: source, syntax: syntax).italic)
    #expect(NSMaxRange(try #require(syntax.runs.last).range) == source.utf16.count)
  }
}
