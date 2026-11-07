import Foundation
import MarkdownCore
import RenderingCore
import Testing

@testable import ExportCore

@Suite("Fresh HTML template exports")
struct HTMLTemplateExportTests {
  @Test(
    "Styles and code highlighting remain independent export choices", arguments: [false, true],
    [false, true])
  func options(styled: Bool, highlighted: Bool) async throws {
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = highlighted
    let export = try await MarkdownExport.build(
      source: "# Fresh 中文\n\n```swift\nlet value = 42\n```", options: options,
      title: "</title><script>bad()</script>", directory: nil, includeStyles: styled)
    #expect(export.document.hasPrefix("<!DOCTYPE html>"))
    #expect(export.document.contains("id=\"document-style\"") == styled)
    #expect(export.document.contains("id=\"code-style\"") == highlighted)
    #expect(export.fragment.contains("token keyword") == highlighted)
    #expect(export.fragment.contains("Fresh 中文"))
    #expect(!export.document.contains("<script>"))
    #expect(
      export.document.contains("<title>&lt;/title&gt;&lt;script&gt;bad()&lt;/script&gt;</title>"))
    let policy = try #require(export.document.range(of: "Content-Security-Policy"))
    let title = try #require(export.document.range(of: "<title>"))
    #expect(policy.lowerBound < title.lowerBound)
  }

  @Test(
    "Unavailable names never fall back to another template",
    arguments: ["", "Missing", "../Default", "default"])
  func unavailable(_ name: String) async throws {
    await #expect(throws: HTMLExportTemplate.Failure.unavailable) {
      try await MarkdownExport.build(
        source: "Body", title: "Title", directory: nil, templateName: name)
    }
  }
}
