import Foundation
import Testing

@testable import MarkdownCore

@Suite("Ordered YAML front matter")
struct MarkdownFrontMatterTests {
  @Test("Literal scalars, nested collections and aliases preserve authored order and escape HTML")
  func orderedMetadata() async throws {
    let source = """
      ---
      title: '<script>Title</script>'
      count: 001
      ready: false
      date: 2026-11-06
      empty:
      author: &author {name: '中文 👩🏽‍💻', role: Writer}
      copied: *author
      tags: [notes, 42, null]
      description: |
        First line
        Second line
      ---
      # Body
      """
    let result = try await MarkdownProcessor().render(source, includeSyntax: true)
    let metadata = try #require(result.frontMatter)
    #expect(result.notices.isEmpty)
    guard case .mapping(let entries) = metadata.values[metadata.root] else {
      Issue.record("Expected ordered mapping")
      return
    }
    let keys = entries.compactMap { entry -> String? in
      if case .scalar(let value) = metadata.values[entry.key] { return value }
      return nil
    }
    #expect(
      keys == [
        "title", "count", "ready", "date", "empty", "author", "copied", "tags", "description",
      ])
    let scalars = entries.prefix(5).compactMap { entry -> String? in
      if case .scalar(let value) = metadata.values[entry.value] { return value }
      return nil
    }
    #expect(scalars == ["<script>Title</script>", "001", "false", "2026-11-06", ""])
    #expect(metadata.html.contains("&lt;script&gt;Title&lt;/script&gt;"))
    #expect(!metadata.html.contains("<script>"))
    #expect(metadata.html.components(separatedBy: "中文 👩🏽‍💻").count == 3)
    #expect(metadata.html.contains("<li>notes</li><li>42</li><li>null</li>"))
    #expect(metadata.html.contains("First line\nSecond line\n"))
    #expect(result.nodes.filter { $0.kind == .frontMatter }.count == 1)
    #expect(result.headings.map(\.title) == ["Body"])
    #expect(result.syntax?.runs.first?.range.location == 0)
  }

  @Test(
    "Metadata masking preserves original Unicode positions and line endings",
    arguments: ["\n", "\r", "\r\n"])
  func originalPositions(_ newline: String) async throws {
    let prefix = ["---", "title: 中文 👩🏽‍💻", "...", ""].joined(separator: newline)
    let source = prefix + "# Heading" + newline + newline + "> [!NOTE] 🎯" + newline + "> Body"
    let result = try await MarkdownProcessor().render(source, includeSyntax: true)
    #expect(result.headings.first?.sourceLine == 4)
    #expect(result.headings.first?.utf16Offset == prefix.utf16.count)
    #expect(result.frontMatter?.utf16Range.length == prefix.utf16.count)
    let callout = try #require(result.nodes.first { $0.callout != nil })
    #expect(callout.range?.start.line == 6)
    #expect(result.html.contains("md-callout"))
    #expect(result.html.contains("id=\"heading\""))
    for node in result.nodes.dropFirst() { #expect(try #require(node.parentID) < node.id) }
  }

  @Test("Invalid, duplicate and undefined-alias YAML stays visible as ordinary Markdown")
  func invalidMetadata() async throws {
    for yaml in ["key: [broken", "key: one\nkey: two", "copy: *missing"] {
      let source = "---\n" + yaml + "\n---\n\n# Kept"
      let result = try await MarkdownProcessor().render(source)
      #expect(result.frontMatter == nil)
      #expect(result.notices == [.invalidFrontMatter])
      #expect(result.html.contains("key") || result.html.contains("missing"))
      #expect(result.headings.last?.title == "Kept")
    }
  }

  @Test(
    "Recursive aliases, excessive nesting and expansion fall back without recursive construction")
  func boundedGraphs() async throws {
    let deep =
      "value: " + String(repeating: "[", count: 100) + "x" + String(repeating: "]", count: 100)
    var bomb = "a: &a [x,x,x,x,x,x,x,x]\n"
    for index in 1...8 {
      let previous = index == 1 ? "a" : "a\(index - 1)"
      bomb +=
        "a\(index): &a\(index) ["
        + Array(repeating: "*" + previous, count: 8).joined(separator: ",") + "]\n"
    }
    for yaml in [
      "value: &cycle [*cycle]", deep, bomb, "text: '" + String(repeating: "x", count: 65_540) + "'",
    ] {
      let result = try await MarkdownProcessor().render("---\n" + yaml + "\n---\n\n# Safe")
      #expect(result.frontMatter == nil)
      #expect(result.notices == [.complexFrontMatter])
      #expect(result.headings.last?.title == "Safe")
    }
  }

  @Test("A delimiter inside a block scalar is not a closing metadata fence")
  func blockScalar() async throws {
    let result = try await MarkdownProcessor().render(
      "---\ntext: |\n  ---\n  Keep this\n---\n\n# Body")
    #expect(result.frontMatter?.html.contains("---\nKeep this\n") == true)
    #expect(result.headings.first?.sourceLine == 7)
  }

  @Test("Disabled and noninitial metadata remains ordinary Markdown")
  func recognition() async throws {
    var options = MarkdownRenderingOptions()
    options.frontMatter = false
    let disabled = try await MarkdownProcessor().render(
      "---\ntitle: Original\n---\n# Body", options: options)
    #expect(disabled.frontMatter == nil)
    #expect(disabled.html.contains("title: Original"))
    for source in [
      "Paragraph\n\n---\ntitle: Later\n---", "---\nUnclosed", "----\ntitle: Not a fence\n---",
    ] {
      #expect(try await MarkdownProcessor().render(source).frontMatter == nil)
    }
  }
}
