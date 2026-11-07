import Foundation
import MarkdownCore
import RenderingCore
import Testing

@testable import ExportCore

@Suite("Reading stylesheet exports")
struct ReadingStyleExportTests {
  @Test(
    "Every selected reading stylesheet reaches styled HTML; plain export keeps highlighting independent"
  )
  func styles() async throws {
    let repository = ReadingStyleRepository()
    let source = "# Style checkpoint\n\nA **portable** document.\n\n```swift\nlet value = 42\n```"
    for entry in ReadingStyleEntry.all {
      let presentation = try await repository.load(entry.id)
      let style = DocumentStyle(presentation: presentation)
      for styled in [false, true] {
        let output = try await MarkdownExport.build(
          source: source, title: "Style checkpoint", directory: nil, includeStyles: styled,
          style: style)
        #expect(output.document.contains("id=\"document-style\"") == styled)
        #expect(output.document.contains("id=\"code-style\""))
        #expect(output.document.contains("token keyword"))
        #expect(!output.document.contains("<script"))
        #expect(output.document.contains("<body id=\"preview-content\">") == style.usesBodyRoot)
        if styled && !style.css.isEmpty { #expect(output.document.contains(style.css)) }
        #expect(output.fragment.contains("<strong>portable</strong>"))
        #expect(!output.fragment.contains("document-style"))
      }
    }
  }
}
