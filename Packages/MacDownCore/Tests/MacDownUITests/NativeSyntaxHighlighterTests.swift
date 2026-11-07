import AppKit
import DocumentCore
import MarkdownCore
import Testing

@testable import MacDownUI

@Suite("Native temporary syntax presentation", .serialized)
@MainActor
struct NativeSyntaxHighlighterTests {
  private func renderedColor(at offset: Int, in editor: NSTextView) throws -> NSColor? {
    let manager = try #require(editor.textLayoutManager)
    let content = try #require(manager.textContentManager)
    editor.window?.contentView?.layoutSubtreeIfNeeded()
    manager.textViewportLayoutController.layoutViewport()
    manager.ensureLayout(for: content.documentRange)
    editor.displayIfNeeded()
    var found: NSColor?
    manager.enumerateRenderingAttributes(from: content.documentRange.location, reverse: false) {
      _, attributes, range in
      let first = content.offset(from: content.documentRange.location, to: range.location)
      let last = content.offset(from: content.documentRange.location, to: range.endLocation)
      if offset >= first, offset < last {
        found = attributes[.foregroundColor] as? NSColor
        return false
      }
      return true
    }
    return found
  }

  @Test("Styling changes rendering but never storage, source, selection or native undo")
  func temporaryPresentation() async throws {
    let source = "# 中文 👩🏽‍💻\n\n**bold *italic*** and `code`"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let manager = UndoManager()
    manager.groupsByEvent = false
    coordinator.undoManager = manager
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .titled,
      backing: .buffered, defer: false)
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    let selection = (source as NSString).range(of: "中文")
    editor.setSelectedRange(selection)
    let before = try #require(editor.textStorage).copy() as? NSAttributedString
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let font = try #require(editor.font)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: document.revision, enabled: true, font: font,
      document: document)
    let italicOffset = (source as NSString).range(of: "italic").location
    let shown = try #require(try renderedColor(at: italicOffset, in: editor))
    #expect(shown == NSColor.systemPink)
    #expect(editor.font == font)
    #expect(editor.textStorage?.isEqual(to: try #require(before)) == true)
    #expect(editor.string.utf8.elementsEqual(source.utf8))
    #expect(document.revision == 0)
    #expect(editor.selectedRange() == selection)
    #expect(!manager.canUndo)
    #expect(editor.textLayoutManager != nil)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: false, font: font, document: document)
    #expect(try renderedColor(at: italicOffset, in: editor) == nil)
    withExtendedLifetime(scroll) {}
  }

  @Test("Stale snapshots and marked text cannot apply source styles")
  func staleAndComposition() async throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "**bold**"))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .titled,
      backing: .buffered, defer: false)
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    let parsed = try await MarkdownProcessor().render(document.text, includeSyntax: true)
    let font = try #require(editor.font)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font, document: document)
    editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 2, length: 4))
    let composing = editor.string
    #expect(editor.hasMarkedText())
    #expect(try renderedColor(at: 2, in: editor) == nil)
    #expect(editor.string == composing)
    #expect(editor.hasMarkedText())
    editor.unmarkText()
    #expect(try renderedColor(at: 2, in: editor) == nil)
    withExtendedLifetime(scroll) {}
  }
}
