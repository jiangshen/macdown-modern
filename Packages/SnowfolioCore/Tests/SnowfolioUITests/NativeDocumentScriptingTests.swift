import AppKit
import DocumentCore
import Testing

@testable import SnowfolioUI

@Suite("Native document scripting", .serialized, NativeUIExclusive())
@MainActor
struct NativeDocumentScriptingTests {
  @Test(
    "KVC source replacement retains native dirty, Undo and exact encoded bytes",
    arguments: ["markdown", "scriptingContents"])
  func sourceOwnership(key: String) async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioScriptOwnership-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("script.md")
    let original = "# Original 中文 👩‍💻\r\ne\u{301}\r\n"
    let replacement = "# Script 中文 👩‍💻\r\ne\u{301}\r\n"
    let bom = Data([0xFF, 0xFE])
    let originalBytes = bom + (try #require(original.data(using: .utf16LittleEndian)))
    try originalBytes.write(to: file)
    let document = try NativeMarkdownDocument(
      contentsOf: file, ofType: "net.daringfireball.markdown")
    NSDocumentController.shared.addDocument(document)
    defer { document.close() }
    func expectEdited(_ edited: Bool) async throws {
      // NSDocument's autosaving-safety activity may finish on a later run-loop turn.
      let deadline = ContinuousClock.now.advanced(by: .seconds(3))
      while document.isDocumentEdited != edited, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(document.isDocumentEdited == edited)
    }
    let manager = try #require(document.undoManager)
    manager.groupsByEvent = false
    #expect(!document.isDocumentEdited)
    #expect(document.value(forKey: key) as? String == original)
    document.setValue(replacement, forKey: key)
    #expect(document.markdownDocument.text == replacement)
    try await expectEdited(true)
    #expect(
      try document.data(ofType: "net.daringfireball.markdown")
        == bom + #require(replacement.data(using: .utf16LittleEndian)))
    // An identical assignment must not add a second undo transaction.
    document.setValue(replacement, forKey: key)
    manager.undo()
    #expect(document.markdown == original)
    try await expectEdited(false)
    #expect(try document.data(ofType: "net.daringfireball.markdown") == originalBytes)
    manager.redo()
    #expect(document.markdown == replacement)
    try await expectEdited(true)
  }

  @Test("HTML is initially empty, cached across edits and protected from stale renders")
  func cachedHTML() {
    let document = NativeMarkdownDocument()
    defer { document.close() }
    let model = document.markdownDocument
    #expect(document.value(forKey: "html") as? String == "")
    let firstRevision = model.revision
    model.acceptRenderedHTML("<p>First</p>", sourceRevision: firstRevision)
    #expect(document.html == "<p>First</p>")
    document.markdown = "Second"
    #expect(document.html == "<p>First</p>")
    model.acceptRenderedHTML("<p>Stale</p>", sourceRevision: firstRevision)
    #expect(document.html == "<p>First</p>")
    model.acceptRenderedHTML("<p>Second</p>", sourceRevision: model.revision)
    #expect(document.html == "<p>Second</p>")
  }

  @Test(
    "Script source changes preserve active marked text",
    arguments: ["markdown", "scriptingContents"])
  func markedText(key: String) throws {
    let document = NativeMarkdownDocument()
    defer { document.close() }
    let original = "# Keep original\n"
    try document.read(from: Data(original.utf8), ofType: "public.plain-text")
    let editor = NSTextView(usingTextLayoutManager: true)
    editor.string = original
    document.attachSourceEditor(editor)
    defer { document.detachSourceEditor(editor) }
    editor.setMarkedText(
      "入力", selectedRange: NSRange(location: 2, length: 0),
      replacementRange: NSRange(location: 0, length: 0))
    #expect(editor.hasMarkedText())
    let markedSource = editor.string
    let markedRange = editor.markedRange()
    document.setValue("Must not overwrite composition", forKey: key)
    #expect(document.markdown == original)
    #expect(editor.string == markedSource)
    #expect(editor.markedRange() == markedRange)
    #expect(!document.isDocumentEdited)
  }
}
