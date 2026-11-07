import CodeHighlightCore
import Foundation
import Testing

@testable import MarkdownCore

@Suite("Local code highlighting")
struct CodeHighlightingTests {
  @Test("All bundled language grammars initialize and accept code without runtime dependencies")
  func grammarCatalog() throws {
    let engine = try CodeHighlighter()
    #expect(engine.supportedLanguages.count == 292)
    for language in engine.supportedLanguages {
      let result = try #require(try engine.highlight("value = 42;\n", language: language))
      #expect(result.language == language)
      #expect(!result.html.isEmpty)
    }
    #expect(try engine.highlight("plain", language: "unknown-language") == nil)
  }

  @Test(
    "Legacy language aliases resolve to real pinned grammars",
    arguments: [
      ("c++", "cpp"), ("coffee", "coffeescript"), ("coffee-script", "coffeescript"),
      ("cs", "csharp"), ("html", "markup"), ("jl", "julia"), ("js", "javascript"),
      ("json", "json"), ("objective-c", "objectivec"), ("obj-c", "objectivec"),
      ("objc", "objectivec"), ("py", "python"), ("rb", "ruby"), ("sh", "bash"),
      ("xml", "markup"), ("graphviz", "dot"), ("gv", "dot"),
    ])
  func aliases(_ pair: (String, String)) throws {
    let result = try #require(try CodeHighlighter().highlight("value", language: pair.0))
    #expect(result.language == pair.1)
  }

  @Test("Render-only decoration retains original AST, code literals, positions and source syntax")
  func sourceModel() async throws {
    let source =
      "> [!NOTE]\n> ```SWIFT additional info\n> let greeting = \"中文 👩🏽‍💻\"\n> ```\n\n```py\nprint(42)\n```"
    var plainOptions = MarkdownRenderingOptions()
    plainOptions.codeHighlighting = false
    let processor = MarkdownProcessor()
    let plain = try await processor.render(source, options: plainOptions, includeSyntax: true)
    let styled = try await processor.render(source, includeSyntax: true)
    #expect(plain.nodes == styled.nodes)
    #expect(plain.syntax?.runs == styled.syntax?.runs)
    #expect(plain.highlightedCodeBlocks == 0)
    #expect(styled.highlightedCodeBlocks == 2)
    #expect(styled.html.contains("class=\"language-swift\""))
    #expect(styled.html.contains("data-sourcepos=\"2:3-4:5\""))
    #expect(styled.html.contains("token keyword"))
    #expect(styled.html.contains("language-python"))
    #expect(styled.html.contains("<aside"))
    #expect(!plain.html.contains("class=\"token"))
    #expect(plain.html.contains("let greeting = &quot;中文 👩🏽‍💻&quot;"))
  }

  @Test("Unknown, unlabelled and oversized blocks remain escaped, complete ordinary code")
  func fallback() async throws {
    let payload = String(repeating: "<tag>中文\n", count: 10_000)
    let source =
      "```unknown\n<script>untrusted()</script>\n```\n\n```\nplain\n```\n\n```swift\n" + payload
      + "```"
    let rendered = try await MarkdownProcessor().render(source)
    #expect(rendered.highlightedCodeBlocks == 0)
    #expect(rendered.html.contains("&lt;script&gt;untrusted()&lt;/script&gt;"))
    #expect(rendered.html.contains("<code>plain\n</code>"))
    #expect(rendered.html.components(separatedBy: "&lt;tag&gt;中文").count == 10_001)
    #expect(!rendered.html.contains("<script>"))
  }

  @Test("Every bundled theme contains token CSS and the legacy default maps correctly")
  func themes() {
    for theme in CodeHighlightTheme.allCases {
      #expect(theme.css.contains(".token"))
      #expect(!theme.css.contains("</style"))
      #expect(!theme.css.contains("@import"))
    }
    #expect(CodeHighlightTheme.legacyName(nil) == .adaptive)
    #expect(CodeHighlightTheme.legacyName("") == .prism)
    #expect(CodeHighlightTheme.legacyName("Default") == .prism)
    #expect(CodeHighlightTheme.legacyName("default") == .prism)
    #expect(CodeHighlightTheme.legacyName("tomorrow") == .tomorrow)
    #expect(CodeHighlightTheme.legacyName("missing-custom") == .prism)
  }
}
