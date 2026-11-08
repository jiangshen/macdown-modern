import AppKit
import DocumentCore
import Testing
import UniformTypeIdentifiers

@testable import SnowfolioUI

@Suite("macOS 27 document adapter", .serialized, NativeUIExclusive())
@MainActor
struct MarkdownDocumentTests {
  @Test(
    "Only source edits and loads advance render revisions; outline navigation does not dirty text")
  func revisions() async throws {
    let document = MarkdownDocument()
    document.acceptNativeEdit("")
    #expect(document.revision == 0)
    document.acceptNativeEdit("# Heading")
    #expect(document.revision == 1)
    #expect(document.loadRevision == 0)
    document.navigate(toUTF16Offset: 2)
    #expect(document.selectionRequest?.offset == 2)
    #expect(document.revision == 1)
    try await document.apply(snapshot: TextFileContents(text: "External"), previous: nil)
    #expect(document.revision == 2)
    #expect(document.loadRevision == 1)
  }

  @Test("Saving an unchanged loaded document retains BOM and line endings")
  func snapshotPreservesBytes() async throws {
    let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("# 中文\r\nbody\r\n".utf8)
    let document = MarkdownDocument(contents: try TextFileContents(decoding: bytes))
    let snapshot = try await document.snapshot(contentType: .plainText)
    #expect(try snapshot.encoded() == bytes)
  }

  @Test("AppKit document saves the current model while retaining the loaded byte format")
  func nativeSnapshotPreservesBytes() throws {
    let original = "# Native 中文 👩‍💻\r\n"
    let bom = Data([0xFF, 0xFE])
    let bytes = bom + (try #require(original.data(using: .utf16LittleEndian)))
    let document = NativeMarkdownDocument()
    try document.read(from: bytes, ofType: "public.plain-text")
    #expect(try document.data(ofType: "public.plain-text") == bytes)
    let model = document.markdownDocument
    #expect(model.text == original)
    model.acceptNativeEdit(original + "e\u{301}")
    let edited = bom + (try #require((original + "e\u{301}").data(using: .utf16LittleEndian)))
    #expect(try document.data(ofType: "public.plain-text") == edited)
    #expect(document.markdownDocument === model)
  }

  @Test("An AppKit read error leaves the last valid snapshot available")
  func nativeFailedReadPreservesSnapshot() throws {
    let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("before\r\n".utf8)
    let document = NativeMarkdownDocument()
    try document.read(from: bytes, ofType: "public.plain-text")
    #expect(throws: TextFileError.invalidTextEncoding(.utf8)) {
      try document.read(from: Data([0xFF]), ofType: "public.plain-text")
    }
    #expect(try document.data(ofType: "public.plain-text") == bytes)
  }

  @Test("Programmatic changes register undo and redo for the native host")
  func undoRedo() async throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "original"))
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    undoManager.beginUndoGrouping()
    document.replaceText(with: "edited 中文", undoManager: undoManager)
    undoManager.endUndoGrouping()
    #expect(document.text == "edited 中文")
    #expect(undoManager.canUndo)
    undoManager.undo()
    #expect(document.text == "original")
    #expect(undoManager.canRedo)
    undoManager.redo()
    #expect(document.text == "edited 中文")
    #expect(
      try await document.snapshot(contentType: .plainText).encoded() == Data("edited 中文".utf8))
  }

  @Test("External changes replace an unedited snapshot")
  func externalReload() async throws {
    let previous = TextFileContents(text: "before")
    let document = MarkdownDocument(contents: previous)
    try await document.apply(snapshot: TextFileContents(text: "external"), previous: previous)
    #expect(document.text == "external")
  }

  @Test("Conflicting external changes never overwrite unsaved local edits")
  func conflicts() async throws {
    let previous = TextFileContents(text: "before")
    let document = MarkdownDocument(contents: previous)
    document.acceptNativeEdit("local")
    await #expect(throws: DocumentMergeError.conflictingExternalChange) {
      try await document.apply(snapshot: TextFileContents(text: "external"), previous: previous)
    }
    #expect(document.text == "local")
  }

  @Test("Identical local and external edits can converge")
  func convergentEdits() async throws {
    let previous = TextFileContents(text: "before")
    let document = MarkdownDocument(contents: previous)
    document.acceptNativeEdit("same")
    try await document.apply(snapshot: TextFileContents(text: "same"), previous: previous)
    #expect(document.text == "same")
  }

  @Test("Unicode normalization changes participate in conflict detection")
  func exactUnicodeComparison() async throws {
    let previous = TextFileContents(text: "cafe\u{301}")
    let document = MarkdownDocument(contents: previous)
    document.acceptNativeEdit("café")
    await #expect(throws: DocumentMergeError.conflictingExternalChange) {
      try await document.apply(snapshot: TextFileContents(text: "remote"), previous: previous)
    }
  }
}
