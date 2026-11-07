import Testing

@testable import MarkdownCore

@Suite("CommonMark and GFM rendering")
struct MarkdownProcessorTests {
  @Test("Standard markup renders through a maintained engine")
  func standardMarkdown() async throws {
    let result = try await MarkdownProcessor().render(
      "# Hello *world*\n\nA **bold** [link](https://example.com).\n")
    #expect(result.html.contains("<em>world</em>"))
    #expect(result.html.contains("<strong>bold</strong>"))
    #expect(result.html.contains("href=\"https://example.com\""))
    #expect(result.headings.first?.title == "Hello world")
    #expect(result.headings.first?.sourceLine == 1)
    #expect(result.nodes.contains { $0.kind == .emphasis })
  }

  @Test("GFM tables, task lists, strike and autolinks are available")
  func gfm() async throws {
    let result = try await MarkdownProcessor().render(
      """
      | Name | Value |
      | --- | --- |
      | a | b |

      - [x] Done
      - [ ] Open

      ~~removed~~ https://example.com
      """)
    #expect(result.html.contains("<table"))
    #expect(result.html.contains("type=\"checkbox\""))
    #expect(result.html.contains("checked"))
    #expect(result.html.contains("<del>removed</del>"))
    #expect(result.html.contains("href=\"https://example.com\""))
    #expect(result.nodes.contains { $0.kind == .table })
  }

  @Test("Code and unsafe links are escaped in the default renderer")
  func safeOutput() async throws {
    let result = try await MarkdownProcessor().render(
      """
      ```html
      <script>alert('code')</script>
      ```

      [bad](javascript:alert(1))

      <script>alert('raw')</script>
      """)
    #expect(result.html.contains("&lt;") && result.html.contains("script"))
    #expect(!result.html.contains("href=\"javascript:"))
    #expect(!result.html.contains("<script>"))
    #expect(result.html.contains("raw HTML omitted"))
  }

  @Test("Raw HTML is explicit and footnotes use parser support")
  func extensions() async throws {
    var options = MarkdownRenderingOptions()
    options.rawHTML = true
    let result = try await MarkdownProcessor().render(
      "<details><summary>Title</summary>Body</details>\n\nNote[^1].\n\n[^1]: Footnote text\n",
      options: options)
    #expect(result.html.contains("<details>"))
    #expect(result.html.contains("footnote"))
    #expect(result.html.contains("Footnote text"))
  }

  @Test("Optional GFM extensions respect disabled choices")
  func disabledExtensions() async throws {
    var options = MarkdownRenderingOptions()
    options.tables = false
    options.strikethrough = false
    options.taskLists = false
    options.autolinks = false
    let result = try await MarkdownProcessor().render(
      "~~text~~ https://example.com\n\n- [x] Done\n\n| a | b |\n|---|---|\n|1|2|", options: options)
    #expect(!result.html.contains("<del>"))
    #expect(!result.html.contains("<table"))
    #expect(!result.html.contains("type=\"checkbox\""))
    #expect(!result.html.contains("href="))
  }

  @Test("Source locations use UTF-8 columns and retain tree relationships")
  func sourcePositions() async throws {
    let result = try await MarkdownProcessor().render("# 中文 👩‍💻\n\n## Next\n")
    #expect(result.headings.map(\.sourceLine) == [1, 3])
    #expect(result.html.contains("data-sourcepos=\"1:1-1:"))
    #expect(result.nodes.first?.parentID == nil)
    for node in result.nodes.dropFirst() {
      #expect(node.parentID != nil)
      #expect((node.parentID ?? 0) < node.id)
    }
  }

  @Test("Outline offsets map CR, LF, CRLF and non-BMP text to native UTF-16 positions")
  func outlineOffsets() async throws {
    let result = try await MarkdownProcessor().render("# 中文 👩‍💻\r\nBody\r## Two\n### Three")
    #expect(result.headings.map(\.sourceLine) == [1, 3, 4])
    #expect(result.headings.map(\.utf16Offset) == [0, 17, 24])
  }

  @Test("A cancelled request does not publish a render")
  func cancellation() async {
    let worker = Task {
      try Task.checkCancellation()
      return try await MarkdownProcessor().render(
        String(repeating: "# Heading\n\nBody\n", count: 10_000))
    }
    worker.cancel()
    await #expect(throws: CancellationError.self) { try await worker.value }
  }
}
