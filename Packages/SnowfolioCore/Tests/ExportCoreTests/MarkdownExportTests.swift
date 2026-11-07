import Foundation
import MarkdownCore
import Testing

@testable import ExportCore

@Suite("Portable Markdown export")
struct MarkdownExportTests {
  @Test("Fresh exports honor a changed fence preference without losing code or text")
  func fencedCodePreference() async throws {
    let source = "~~~text\n**body**\n~~~\n\n    indented code"
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let enabled = try await MarkdownExport.build(
      source: source, options: options, title: "Fences", directory: nil)
    #expect(!enabled.fragment.contains("<strong>body</strong>"))
    options.fencedCode = false
    for styled in [false, true] {
      let disabled = try await MarkdownExport.build(
        source: source, options: options, title: "Fences", directory: nil, includeStyles: styled)
      #expect(disabled.fragment.contains("<strong>body</strong>"))
      #expect(disabled.fragment.components(separatedBy: "<pre").count == 2)
      #expect(disabled.fragment.contains("indented code"))
      #expect(!disabled.fragment.contains("language-text"))
      #expect(disabled.document.contains("script-src 'none'"))
    }
  }

  @Test(
    "Styled and plain HTML honor current underline and quotation preferences",
    arguments: [false, true])
  func underlinePreference(styled: Bool) async throws {
    let source = "_Underline checkpoint_ and *italic*; a_b_c. \"Quotation checkpoint\"."
    var options = MarkdownRenderingOptions()
    let standard = try await MarkdownExport.build(
      source: source, options: options, title: "Underline", directory: nil, includeStyles: styled)
    #expect(standard.fragment.contains("<em>Underline checkpoint</em>"))
    #expect(standard.fragment.contains("a_b_c"))
    #expect(standard.fragment.contains("&quot;Quotation checkpoint&quot;"))
    options.underline = true
    options.quotedText = true
    let enabled = try await MarkdownExport.build(
      source: source, options: options, title: "Underline", directory: nil, includeStyles: styled)
    #expect(enabled.fragment.contains("<u>Underline checkpoint</u>"))
    #expect(enabled.fragment.contains("<em>italic</em>"))
    #expect(enabled.fragment.contains("a<u>b</u>c"))
    #expect(enabled.fragment.contains("<q>Quotation checkpoint</q>"))
    #expect(enabled.document.contains("script-src 'none'"))
    #expect(!enabled.document.contains("<script"))
    #expect(enabled.document.contains("id=\"document-style\"") == styled)
  }

  @Test(
    "Styled and plain HTML preserve all three word-formatting policies", arguments: [false, true])
  func intrawordPreference(styled: Bool) async throws {
    let source = "a_b_c a*b*c a**b**c a==b==c a~~b~~c"
    var options = MarkdownRenderingOptions()
    options.highlight = true
    for policy in MarkdownEmphasisPolicy.allCases {
      options.emphasisPolicy = policy
      let output = try await MarkdownExport.build(
        source: source, options: options, title: "Word formatting", directory: nil,
        includeStyles: styled)
      switch policy {
      case .standard:
        #expect(output.fragment.contains("a_b_c a<em>b</em>c"))
      case .allowWithinWords:
        #expect(output.fragment.contains("a<em>b</em>c a<em>b</em>c a<strong>b</strong>c"))
        #expect(output.fragment.contains("a<mark>b</mark>c a<del>b</del>c"))
      case .avoidWithinWords:
        #expect(output.fragment.contains(source))
      }
      #expect(output.document.contains("script-src 'none'"))
      #expect(output.document.contains("id=\"document-style\"") == styled)
    }
  }

  @Test("Math exports carry accessible equations and all fonts without executable scripts")
  func mathExport() async throws {
    var options = MarkdownRenderingOptions()
    options.math = true
    let result = try await MarkdownExport.build(
      source: "```math\n\\frac{1}{2}+\\sqrt{x}\n```", options: options,
      title: "Offline math", directory: nil, includeStyles: false)
    #expect(result.fragment.contains("<math"))
    #expect(result.fragment.contains("data-snowfolio-math"))
    #expect(result.fragment.contains("data:font/woff2;base64,"))
    #expect(result.document.contains("id=\"math-style\""))
    #expect(result.document.contains("data:font/woff2;base64,"))
    #expect(result.document.contains("Permission is hereby granted"))
    #expect(!result.document.contains("url(fonts/"))
    #expect(!result.document.contains("<script"))
    #expect(result.document.contains("script-src 'none'"))
    #expect(!result.document.contains("id=\"document-style\""))
  }

  @Test("HTML escapes the document title and respects styled versus plain output")
  func documentEnvelope() async throws {
    let styled = try await MarkdownExport.build(
      source: "# Hello\n\n**world**", title: "<Title> & \"Name\"", directory: nil)
    #expect(styled.document.contains("<title>&lt;Title&gt; &amp; &quot;Name&quot;</title>"))
    #expect(styled.document.contains("<style id=\"document-style\">"))
    #expect(styled.fragment.contains("<strong>world</strong>"))
    #expect(!styled.fragment.contains("<!doctype"))
    let plain = try await MarkdownExport.build(
      source: "# Hello", title: "Plain", directory: nil, includeStyles: false)
    #expect(!plain.document.contains("<style id=\"document-style\">"))
    #expect(plain.document.contains("script-src 'none'"))
  }

  @Test("Local Markdown images are embedded and exports stay usable away from the source folder")
  func embeddedImage() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    try bytes.write(to: directory.appendingPathComponent("ice image.png"))
    let result = try await MarkdownExport.build(
      source: "![Ice](ice%20image.png)\n\n`![literal](missing.png)`", title: "Ice",
      directory: directory)
    #expect(result.document.contains("data:image/png;base64,\(bytes.base64EncodedString())"))
    #expect(result.document.contains("![literal](missing.png)"))
    let output = directory.appendingPathComponent("export.html")
    try await result.writeHTML(to: output)
    #expect(try Data(contentsOf: output) == Data(result.document.utf8))
  }

  @Test("Vector images embed without relaxing raw HTML or dangerous-link filtering")
  func embeddedSVG() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let svg =
      "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20'><rect width='20' height='20' fill='blue'/></svg>"
    try Data(svg.utf8).write(to: directory.appendingPathComponent("ice.svg"))
    let result = try await MarkdownExport.build(
      source: "![Ice](ice.svg)\n\n<script>alert(1)</script>\n\n[bad](javascript:alert(1))",
      title: "Vector", directory: directory)
    #expect(result.fragment.contains("data:image/svg+xml;base64,"))
    #expect(!result.fragment.contains("mdexportasset:"))
    #expect(!result.fragment.contains("<script>"))
    #expect(!result.fragment.contains("href=\"javascript:"))
  }

  @Test("An inaccessible local image fails export without silently producing a broken replacement")
  func missingImage() async {
    await #expect(throws: (any Error).self) {
      try await MarkdownExport.build(
        source: "![missing](missing.png)", title: "Missing",
        directory: FileManager.default.temporaryDirectory)
    }
  }

  @Test("Copyable HTML retains image references without requiring the image file")
  func unembeddedHTML() async throws {
    let result = try await MarkdownExport.build(
      source: "![missing](missing.png)", title: "Copy",
      directory: FileManager.default.temporaryDirectory, embedLocalImages: false)
    #expect(result.fragment.contains("src=\"missing.png\""))
  }

  @Test("HTML resource strings cannot inject attributes through destination transformation")
  func destinationEscaping() async throws {
    let result = try await MarkdownProcessor().render("![image](safe.png)") { _, _ in
      "image.png\" onerror=\"alert(1)"
    }
    #expect(!result.html.contains(" onerror=\""))
    #expect(result.html.contains("%22"))
  }
  @Test("Callouts export as semantic HTML with or without document styles")
  func calloutExport() async throws {
    let source = "> [!IMPORTANT]\n> Keep **Unicode 中文** and `code`."
    let styled = try await MarkdownExport.build(source: source, title: "Callout", directory: nil)
    #expect(styled.document.contains(".md-callout"))
    #expect(styled.fragment.contains("<aside class=\"md-callout md-callout-important\""))
    #expect(styled.fragment.contains("<strong>Unicode 中文</strong>"))
    let plain = try await MarkdownExport.build(
      source: source, title: "Callout", directory: nil, includeStyles: false)
    #expect(!plain.document.contains("<style"))
    #expect(plain.fragment == styled.fragment)
    var options = MarkdownRenderingOptions()
    options.alerts = false
    let disabled = try await MarkdownExport.build(
      source: source, options: options, title: "Callout", directory: nil)
    #expect(!disabled.fragment.contains("<aside"))
    #expect(disabled.fragment.contains("[!IMPORTANT]"))
  }

  @Test("Code highlighting exports as portable markup and styles independently of document styling")
  func codeHighlighting() async throws {
    let source = "```swift\nlet greeting = \"Hello\"\n```"
    let styled = try await MarkdownExport.build(source: source, title: "Code", directory: nil)
    let codeOnly = try await MarkdownExport.build(
      source: source, title: "Code", directory: nil, includeStyles: false)
    #expect(styled.fragment == codeOnly.fragment)
    #expect(codeOnly.fragment.contains("token keyword"))
    #expect(codeOnly.document.contains("<style id=\"code-style\">"))
    #expect(!codeOnly.document.contains("<style id=\"document-style\">"))
    #expect(!codeOnly.document.contains("<script"))
    #expect(codeOnly.document.contains("script-src 'none'"))
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    let plain = try await MarkdownExport.build(
      source: source, options: options, title: "Code", directory: nil, includeStyles: false)
    #expect(!plain.document.contains("<style"))
    #expect(!plain.fragment.contains("token keyword"))
    #expect(plain.fragment.contains("let greeting = &quot;Hello&quot;"))
  }

  @Test("Properties, heading IDs and TOC links are preserved in standalone exports")
  func metadataNavigation() async throws {
    let source = "---\ntitle: '<b>Kept literal</b>'\n---\n\n[TOC]\n\n# Heading\n\n## 中文"
    let output = try await MarkdownExport.build(source: source, title: "Metadata", directory: nil)
    #expect(output.fragment.contains("md-frontmatter"))
    #expect(output.fragment.contains("&lt;b&gt;Kept literal&lt;/b&gt;"))
    #expect(output.fragment.contains("href=\"#heading\""))
    #expect(output.fragment.contains("id=\"heading\""))
    #expect(output.fragment.contains("id=\"toc_1\""))
    #expect(!output.document.contains("<script"))
    var options = MarkdownRenderingOptions()
    options.frontMatter = false
    options.tableOfContents = false
    let plain = try await MarkdownExport.build(
      source: source, options: options, title: "Metadata", directory: nil, includeStyles: false)
    #expect(!plain.fragment.contains("md-frontmatter"))
    #expect(!plain.fragment.contains("md-toc"))
    #expect(plain.fragment.contains("[TOC]"))
  }

}

extension MarkdownExportTests {
  @Test("Portable output retains standard nested emphasis and literal overlong references")
  func commonmarkCorrections() async throws {
    let source = "****important**** and &#00000065; *€*word"
    for styled in [false, true] {
      let result = try await MarkdownExport.build(
        source: source, title: "Conformance", directory: nil, includeStyles: styled)
      #expect(result.fragment.contains("<strong><strong>important</strong></strong>"))
      #expect(result.document.contains("&amp;#00000065; *€*word"))
    }
  }
}
