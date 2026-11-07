import Testing

@testable import MarkdownCore

@Suite("Optional Markdown callouts")
struct MarkdownCalloutTests {
  @Test("All five marker types decorate safe Markdown", arguments: MarkdownCallout.allCases)
  func kinds(_ kind: MarkdownCallout) async throws {
    let marker = "[!\(kind.rawValue.uppercased())]"
    let result = try await MarkdownProcessor().render(
      "> \(marker)\n> Read **世界 👩‍💻** and [a link](https://example.com).\n")
    #expect(result.html.contains("<aside class=\"md-callout md-callout-\(kind.rawValue)\""))
    #expect(result.html.contains("\(kind.title)</span>"))
    #expect(result.html.contains("<strong>世界 👩‍💻</strong>"))
    #expect(result.html.contains("href=\"https://example.com\""))
    #expect(!result.html.contains(marker))
    #expect(!result.html.contains("role=\"alert\""))
    let quote = try #require(result.nodes.first(where: { $0.kind == .blockquote }))
    #expect(quote.callout == kind)
    #expect(quote.range?.start.line == 1)
    #expect(quote.range?.end.line == 2)
    #expect(result.nodes.contains { $0.literal == marker })
  }

  @Test(
    "Literal markers and nested quotes remain normal Markdown",
    arguments: [
      "> A normal quote\n> [!NOTE]\n> More text",
      "> [!DANGER]\n> Unknown kind",
      "> [!NOTE] custom title\n> Not the documented syntax",
      "> \\[!NOTE]\n> An escaped marker",
      "> &#91;!NOTE]\n> Entity-escaped marker",
      "> `[!NOTE]`\n> Inline code",
      "> **[!NOTE]**\n> Formatted marker",
      "```markdown\n> [!NOTE]\n> A code example\n```",
      "    > [!NOTE]\n    > Indented code",
      "> Outer\n>\n> > [!NOTE]\n> > Nested quote",
      "- Item\n\n  > [!NOTE]\n  > Quote inside a list",
      "[!NOTE]: https://example.com\n\n> [!NOTE]\n> A reference link",
    ])
  func literalMarkers(_ source: String) async throws {
    let result = try await MarkdownProcessor().render(source)
    #expect(!result.html.contains("md-callout"))
    #expect(result.nodes.allSatisfy { $0.callout == nil })
  }

  @Test("Disabling callouts preserves the complete source AST and ordinary quote output")
  func disabled() async throws {
    let source = "> [!TIP]\n> A paragraph.\n>\n> ## A heading\n>\n> - A list item\n"
    var options = MarkdownRenderingOptions()
    options.alerts = false
    let plain = try await MarkdownProcessor().render(source, options: options)
    let decorated = try await MarkdownProcessor().render(source)
    #expect(plain.html.contains("<blockquote"))
    #expect(plain.html.contains("[!TIP]"))
    #expect(!plain.html.contains("md-callout"))
    #expect(decorated.html.contains("<aside"))
    #expect(decorated.html.contains("<h2"))
    #expect(decorated.html.contains("<ul"))
    #expect(decorated.headings == plain.headings)
    #expect(decorated.nodes.count == plain.nodes.count)
    for (before, after) in zip(plain.nodes, decorated.nodes) {
      #expect(after.id == before.id)
      #expect(after.parentID == before.parentID)
      #expect(after.kind == before.kind)
      #expect(after.literal == before.literal)
      #expect(after.range == before.range)
    }
  }

  @Test(
    "Empty marker paragraphs and newline forms do not lose subsequent content",
    arguments: ["\n", "\r\n", "\r"])
  func lineEndings(_ newline: String) async throws {
    let source = [
      "> [!NOTE]  ", "> Unicode 中文", ">", "> A second paragraph", "", "> [!TIP]", "",
      "# Afterwards",
    ].joined(separator: newline)
    let result = try await MarkdownProcessor().render(source)
    #expect(result.nodes.filter { $0.callout != nil }.count == 2)
    #expect(result.html.contains("Unicode 中文"))
    #expect(result.html.contains("A second paragraph"))
    #expect(!result.html.contains("[!TIP]"))
    #expect(result.html.contains("data-sourcepos=\"1:1-4:"))
    #expect(result.headings.last?.sourceLine == 8)
  }

  @Test("Trusted wrappers do not relax HTML, image or link escaping")
  func safeChildren() async throws {
    let result = try await MarkdownProcessor().render(
      """
      > [!WARNING]
      > <script>alert('raw')</script>
      >
      > [bad](javascript:alert(1)) and ![image](safe.png)
      >
      > ```html
      > <img src=x onerror='alert(1)'>
      > ```
      """)
    #expect(result.html.contains("<aside"))
    #expect(!result.html.contains("<script>"))
    #expect(!result.html.contains("href=\"javascript:"))
    #expect(result.html.contains("&lt;") && result.html.contains("img"))
    #expect(result.html.contains("src=\"safe.png\""))
  }
}
