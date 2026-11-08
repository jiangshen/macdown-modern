import CodeHighlightCore
import Foundation
import Testing

@testable import MarkdownCore

@Suite("Portable code block presentation")
struct CodeBlockPresentationTests {
  @Test("Every pinned grammar retains multiline code and can receive line numbers")
  func grammarCatalog() async throws {
    let catalog = try CodeHighlighter()
    let processor = MarkdownProcessor()
    var options = MarkdownRenderingOptions()
    options.codeLineNumbers = true
    let body = "a = \"中文 👩‍💻<&>\";\n/* comment\nmore */\n\n// &nbsp; &#10; \n"
    for language in catalog.supportedLanguages {
      let source = "```" + language + "\n" + body + "```"
      let result = try await processor.render(source, options: options, includeSyntax: true)
      #expect(result.highlightedCodeBlocks == 1, "\(language)")
      #expect(result.decoratedCodeBlocks == 1, "\(language)")
      #expect(!result.notices.contains(.limitedCodePresentation), "\(language)")
      #expect(
        result.html.components(separatedBy: "class=\"md-code-number\"").count == 6, "\(language)")
      let block = try #require(result.nodes.first { $0.kind == .codeBlock })
      #expect(block.literal == body)
    }
  }

  @Test(
    "Language labels retain the pinned release's human names and aliases",
    arguments: [
      ("html", "HTML"), ("js", "JavaScript"), ("objc", "Objective-C"), ("c++", "C++"),
      ("fsharp", "F#"), ("py", "Python"), ("swift", "Swift"),
      ("unknown-language", "Unknown-language"),
    ])
  func languageNames(_ pair: (String, String)) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.codeBlockAccessory = .language
    let output = try await MarkdownProcessor().render(
      "```" + pair.0 + "\nvalue\n```", options: options)
    #expect(output.html.contains("<div class=\"md-code-label\">" + pair.1 + "</div>"))
    #expect(output.highlightedCodeBlocks == 0 && output.decoratedCodeBlocks == 1)
  }

  @Test("Custom metadata splits only in Custom mode and never introduces markup")
  func customMetadata() async throws {
    let source = "```swift:File <img src=x onerror=bad()>.swift & 中文\nlet value = 42\n```"
    let processor = MarkdownProcessor()
    let original = try await processor.render(source, includeSyntax: true)
    #expect(original.highlightedCodeBlocks == 0 && original.decoratedCodeBlocks == 0)
    var options = MarkdownRenderingOptions()
    options.codeBlockAccessory = .custom
    options.codeLineNumbers = true
    let enabled = try await processor.render(source, options: options, includeSyntax: true)
    #expect(enabled.highlightedCodeBlocks == 1 && enabled.decoratedCodeBlocks == 1)
    #expect(enabled.html.contains("File &lt;img src=x onerror=bad()&gt;.swift &amp; 中文"))
    #expect(!enabled.html.contains("<img") && !enabled.html.contains(" onerror=\""))
    #expect(enabled.nodes == original.nodes && enabled.syntax?.runs == original.syntax?.runs)
    #expect(enabled.html.contains("data-sourcepos=\"1:1-3:3\""))
    #expect(enabled.html.contains("token keyword"))
  }

  @Test("Unknown, unlabelled and indented blocks support numbering without highlighting")
  func plainBlocks() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.codeLineNumbers = true
    let source = "```unknown\n<&中文>\n\nlast\n```\n\n```\nplain\n```\n\n    indented code"
    let output = try await MarkdownProcessor().render(source, options: options)
    #expect(output.highlightedCodeBlocks == 0 && output.decoratedCodeBlocks == 3)
    #expect(output.html.components(separatedBy: "data-code-numbered=\"true\"").count == 4)
    #expect(output.html.components(separatedBy: "class=\"md-code-number\"").count == 6)
    #expect(output.html.contains("&lt;&amp;中文&gt;"))
    #expect(!output.html.contains("<script") && output.notices.isEmpty)
  }

  @Test("Decoration limits retain complete ordinary code and report missing numbering")
  func limits() async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.codeLineNumbers = true
    let body = String(repeating: "value\n", count: 10_001)
    let result = try await MarkdownProcessor().render(
      "```unknown\n" + body + "```", options: options)
    #expect(result.decoratedCodeBlocks == 0)
    #expect(result.notices.contains(.limitedCodePresentation))
    #expect(result.html.components(separatedBy: "value\n").count == 10_002)
    #expect(!result.html.contains("md-code-number"))
    let empty = try await MarkdownProcessor().render("```swift\n```", options: options)
    #expect(!empty.notices.contains(.limitedCodePresentation))
    #expect(!empty.html.contains("md-code-number"))
  }
}
