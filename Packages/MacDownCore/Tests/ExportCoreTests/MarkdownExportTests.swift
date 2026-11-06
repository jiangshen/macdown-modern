import Foundation
import MarkdownCore
import Testing

@testable import ExportCore

@Suite("Portable Markdown export")
struct MarkdownExportTests {
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

}
