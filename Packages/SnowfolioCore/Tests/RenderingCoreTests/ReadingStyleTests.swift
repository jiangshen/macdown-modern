import Foundation
import Testing

@testable import RenderingCore

@Suite("Portable reading styles")
struct ReadingStyleTests {
  @Test("All six original styles resolve distinctly; None and notebook remain separate")
  func bundled() async throws {
    let repository = ReadingStyleRepository()
    #expect(ReadingStyleEntry.bundled.count == 6)
    #expect(ReadingStyleEntry.all.count == 8)
    var sheets: Set<DocumentStylesheet> = []
    for entry in ReadingStyleEntry.bundled {
      let resolved = try await repository.load(entry.id)
      guard case .stylesheet(let sheet) = resolved else {
        Issue.record("Expected a stylesheet")
        continue
      }
      #expect(!sheet.css.isEmpty)
      sheets.insert(sheet)
      let legacy = try await repository.load("legacy:" + entry.title)
      #expect(legacy == resolved)
      let style = DocumentStyle(presentation: resolved)
      let html = PreviewHTML.document(body: "<h1>Title</h1>", style: style)
      #expect(html.contains("<body id=\"preview-content\"><h1>Title</h1></body>"))
      #expect(style.css == sheet.css && style.usesBodyRoot)
      #expect(!html.contains("--document-font:"))
    }
    #expect(sheets.count == 6)
    let none = try await repository.load("none")
    #expect(DocumentStyle(presentation: none).css.isEmpty)
    #expect(none != (try await repository.load("snowfolio")))
    await #expect(throws: ReadingStyleRepository.Failure.unavailable) {
      try await repository.load("bundled:../unsafe")
    }
  }

  @Test("A CSS snapshot cannot break out of the initial HTML style element")
  func rawTextBoundary() throws {
    let css = "p::after { content: '</style><img id=\"escaped\" src=x><script>bad()</script>'; }"
    let sheet = try DocumentStylesheet(data: Data(css.utf8))
    let style = DocumentStyle(presentation: .stylesheet(sheet))
    let html = PreviewHTML.document(body: "<p>Body</p>", style: style)
    #expect(!html.contains("<img id=\"escaped\""))
    #expect(!html.contains("<script>"))
    #expect(html.contains("\\3c /style>"))
    #expect(style.css == css)
    let plain = PreviewHTML.document(body: "<p>Body</p>", includeStyles: false, style: style)
    #expect(
      !plain.contains("document-style")
        && plain.contains("<body id=\"preview-content\"><p>Body</p>"))
    #expect(throws: DocumentStylesheet.Failure.invalidEncoding) {
      try DocumentStylesheet(data: Data([255]))
    }
    #expect(throws: DocumentStylesheet.Failure.tooLarge) {
      try DocumentStylesheet(data: Data(repeating: 65, count: DocumentStylesheet.maximumBytes + 1))
    }
  }

  @Test("A modified old CSS file is never silently replaced by the bundled version")
  func modifiedLegacy() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let custom = Data("body { color: purple }".utf8)
    try custom.write(to: folder.appendingPathComponent("GitHub2.css"))
    let repository = ReadingStyleRepository(legacyDirectory: folder)
    let edited = try await repository.load("legacy:GitHub2")
    #expect(DocumentStyle(presentation: edited).css == "body { color: purple }")
    #expect(try Data(contentsOf: folder.appendingPathComponent("GitHub2.css")) == custom)
    // An explicit stock choice remains available independently of the old file.
    let stock = try await repository.load("bundled:GitHub2")
    #expect(DocumentStyle(presentation: stock).css.contains("#4183C4"))
    try Data(DocumentStyle(presentation: stock).css.utf8).write(
      to: folder.appendingPathComponent("GitHub2.css"))
    #expect(try await repository.load("legacy:GitHub2") == stock)
    let spaced = try await repository.load("bundled:Clearness Dark")
    try Data(DocumentStyle(presentation: spaced).css.utf8).write(
      to: folder.appendingPathComponent("Clearness Dark.css"))
    #expect(try await repository.load("legacy:Clearness Dark") == spaced)
    for entry in ReadingStyleEntry.bundled {
      let original = DocumentStyle(presentation: try await repository.load(entry.id)).css
      let edited = original + "\n/* User customization retained */\n"
      try Data(edited.utf8).write(
        to: folder.appendingPathComponent(entry.title).appendingPathExtension("css"))
      #expect(
        DocumentStyle(presentation: try await repository.load("legacy:" + entry.title)).css
          == edited)
    }
  }

  @Test("Canonically equivalent Swift strings remain distinct CSS snapshots")
  func exactCSSBytes() throws {
    let first = ".café::after { content: 'é' }"
    let second = ".cafe\u{301}::after { content: 'e\u{301}' }"
    #expect(first == second)
    let a = try DocumentStylesheet(data: Data(first.utf8))
    let b = try DocumentStylesheet(data: Data(second.utf8))
    #expect(a != b)
    #expect(Set([a, b]).count == 2)
    #expect(a.css.utf8.elementsEqual(first.utf8) && b.css.utf8.elementsEqual(second.utf8))
    #expect(
      DocumentStyle(presentation: .stylesheet(a)) != DocumentStyle(presentation: .stylesheet(b)))
  }

}
