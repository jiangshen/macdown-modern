import AppKit
import DocumentCore
import SwiftUI
import Testing

@testable import SnowfolioUI

@Suite("TextKit 2 native editor", .serialized, NativeUIExclusive())
@MainActor
struct NativeMarkdownEditorTests {
  @Test("The actual editing surface uses TextKit 2 and native find")
  func nativeSurface() throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "# 中文 👩‍💻"))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scrollView = NativeMarkdownEditor.makeScrollView(
      document: document, coordinator: coordinator)
    let editor = try #require(scrollView.documentView as? NSTextView)
    #expect(editor.textLayoutManager != nil)
    #expect(editor.string == document.text)
    #expect(editor.usesFindBar)
    #expect(!editor.isRichText)
    #expect(editor.allowsUndo)
  }

  @Test("Native typing, undo and redo update the document through one undo manager")
  func nativeUndoRedo() throws {
    let document = MarkdownDocument()
    let manager = UndoManager()
    manager.groupsByEvent = false
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    coordinator.undoManager = manager
    let scrollView = NativeMarkdownEditor.makeScrollView(
      document: document, coordinator: coordinator)
    let editor = try #require(scrollView.documentView as? NSTextView)
    #expect(editor.undoManager === manager)
    manager.beginUndoGrouping()
    editor.insertText("hello 中文", replacementRange: NSRange(location: 0, length: 0))
    manager.endUndoGrouping()
    #expect(document.text == "hello 中文")
    manager.undo()
    #expect(document.text == "")
    #expect(editor.string == "")
    manager.redo()
    #expect(document.text == "hello 中文")
  }

  @Test("Document reflection preserves selection and does not replace marked text")
  func compositionAndSelection() throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "abcdef"))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scrollView = NativeMarkdownEditor.makeScrollView(
      document: document, coordinator: coordinator)
    let editor = try #require(scrollView.documentView as? NSTextView)
    editor.setSelectedRange(NSRange(location: 1, length: 3))
    document.acceptNativeEdit("abcdef more")
    NativeMarkdownEditor.synchronize(scrollView, document: document, coordinator: coordinator)
    #expect(editor.selectedRange() == NSRange(location: 1, length: 3))
    editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 0, length: 0))
    #expect(editor.hasMarkedText())
    let composingText = editor.string
    document.replaceText(with: "external state", undoManager: nil)
    NativeMarkdownEditor.synchronize(scrollView, document: document, coordinator: coordinator)
    #expect(editor.string == composingText)
    #expect(editor.hasMarkedText())
    editor.unmarkText()
  }
  @Test("Restored selections clamp stale offsets and preserve source and undo")
  func restoredSelection() throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "A😀B"))
    let manager = UndoManager()
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    coordinator.undoManager = manager
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    editor.restoreSelection(location: Int.max, length: Int.max)
    #expect(editor.selectedRange() == NSRange(location: 4, length: 0))
    editor.restoreSelection(location: -100, length: Int.max)
    #expect(editor.selectedRange() == NSRange(location: 0, length: 4))
    editor.restoreSelection(location: 2, length: 0)
    #expect(editor.selectedRange() == NSRange(location: 1, length: 0))
    #expect(document.text == "A😀B")
    #expect(!manager.canUndo)
  }

  @Test("Scene selection restoration waits for initial load and does not reset later edits")
  func sceneSelectionRestoration() async throws {
    var stored: Data? = try JSONEncoder().encode(EditorSelectionState(location: 3, length: 2))
    let document = MarkdownDocument()
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    coordinator.selectionStorage = Binding(get: { stored }, set: { stored = $0 })
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    coordinator.restoreSelectionIfNeeded()
    #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
    try await document.apply(snapshot: TextFileContents(text: "abcdef"), previous: nil)
    NativeMarkdownEditor.synchronize(scroll, document: document, coordinator: coordinator)
    coordinator.restoreSelectionIfNeeded()
    #expect(editor.selectedRange() == NSRange(location: 3, length: 2))
    editor.setSelectedRange(NSRange(location: 1, length: 1))
    coordinator.textViewDidChangeSelection(
      Notification(name: NSTextView.didChangeSelectionNotification))
    let captured = try JSONDecoder().decode(EditorSelectionState.self, from: #require(stored))
    #expect(captured == EditorSelectionState(location: 1, length: 1))
    coordinator.restoreSelectionIfNeeded()
    #expect(editor.selectedRange() == NSRange(location: 1, length: 1))
    #expect(document.revision == 1)
    #expect(document.text == "abcdef")
  }

}
