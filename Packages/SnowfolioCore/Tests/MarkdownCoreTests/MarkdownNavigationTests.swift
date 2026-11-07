import Testing

@testable import MarkdownCore

@Suite("Portable document navigation")
struct MarkdownNavigationTests {
  @Test("Unicode slugs are stable, unique and cannot collide with legacy anchors")
  func uniqueAnchors() async throws {
    let source =
      "# Hello *world*\n# Hello world\n# Hello world-1\n# 中文 👩🏽‍💻\n# !!!\n# toc_0\n# Hello world\n# Preview content\n# Document style\n# Code style"
    let result = try await MarkdownProcessor().render(source)
    #expect(
      result.headings.map(\.anchor) == [
        "hello-world", "hello-world-1", "hello-world-1-1", "中文", "section", "section-toc_0",
        "hello-world-2", "preview-content-1", "document-style-1", "code-style-1",
      ])
    #expect(result.html.contains("<em>world</em>"))
    #expect(result.html.contains("id=\"toc_0\""))
    #expect(result.html.contains("id=\"toc_6\""))
    #expect(result.html.contains("id=\"中文\""))
    let rerendered = try await MarkdownProcessor().render(source)
    #expect(result.headings == rerendered.headings)
  }

  @Test(
    "TOC expands parser-recognized markers into nested escaped links without changing source AST")
  func generatedContents() async throws {
    let source =
      "[TOC]\n\n### First\n\n# Root\n\n#### Deep\n\n## 中 文\n\n# &lt;script&gt;Untrusted&lt;/script&gt;"
    let processor = MarkdownProcessor()
    let result = try await processor.render(source)
    #expect(result.html.contains("<nav class=\"md-toc\""))
    #expect(result.html.contains("href=\"#first\">First</a>"))
    #expect(result.html.contains("href=\"#%E4%B8%AD-%E6%96%87\""))
    #expect(!result.html.contains("<script>"))
    #expect(result.html.contains("&lt;script&gt;"))
    var options = MarkdownRenderingOptions()
    options.tableOfContents = false
    let plain = try await processor.render(source, options: options)
    #expect(plain.nodes == result.nodes)
    #expect(plain.headings == result.headings)
    #expect(plain.html.contains("[TOC]"))
    #expect(!plain.html.contains("<nav"))
  }

  @Test("Escaped, linked and code markers stay literal")
  func literalMarkers() async throws {
    for source in [
      "\\[TOC]", "&#91;TOC]", "`[TOC]`", "```\n[TOC]\n```", "[TOC]\n\n[toc]: https://example.com",
      "Text [TOC]", "[TOC] text",
    ] {
      let result = try await MarkdownProcessor().render(source + "\n\n# Heading")
      #expect(!result.html.contains("<nav"))
    }
  }

  @Test("Multiple markers, skipped levels and markers inside quotes remain well formed")
  func nestedMarkers() async throws {
    let result = try await MarkdownProcessor().render(
      "[TOC]\n\n> [TOC]\n\n### Start\n##### Deeper\n## Earlier\n###### Detail\n# Root")
    #expect(result.html.components(separatedBy: "<nav class=\"md-toc\"").count == 3)
    #expect(result.html.components(separatedBy: "href=\"#root\"").count == 3)
    #expect(result.html.contains("<blockquote"))
  }
}
