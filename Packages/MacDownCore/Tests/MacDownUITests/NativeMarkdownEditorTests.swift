import AppKit
import DocumentCore
import Testing

@testable import MacDownUI

@Suite("TextKit 2 native editor", .serialized)
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
}
