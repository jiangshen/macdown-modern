import AppKit
import DocumentCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Markdown file drops", .serialized, NativeUIExclusive())
@MainActor
struct DocumentFileDropTests {
  private func pasteboard(_ urls: [URL]) -> NSPasteboard {
    let board = NSPasteboard.withUniqueName()
    board.writeObjects(urls.map { $0 as NSURL })
    return board
  }

  @Test("Only complete local Markdown file batches are accepted")
  func validation() throws {
    let first = URL(fileURLWithPath: "/tmp/中文 #1.MD")
    let second = URL(fileURLWithPath: "/tmp/next.markdown")
    let board = pasteboard([first, second])
    defer { board.releaseGlobally() }
    #expect(MarkdownFileDrop.urls(from: board) == [first, second])
    let mixed = pasteboard([first, URL(fileURLWithPath: "/tmp/photo.png")])
    defer { mixed.releaseGlobally() }
    #expect(MarkdownFileDrop.urls(from: mixed) == nil)
    let remoteURL = try #require(URL(string: "https://example.com/note.md"))
    let remote = pasteboard([remoteURL])
    defer { remote.releaseGlobally() }
    #expect(MarkdownFileDrop.urls(from: remote) == nil)
    let text = NSPasteboard.withUniqueName()
    defer { text.releaseGlobally() }
    text.setString("file:///tmp/note.md", forType: .string)
    #expect(MarkdownFileDrop.urls(from: text) == nil)
    #expect(!MarkdownFileDrop.accepts([]))
  }

  @Test("Dropping multiple Markdown files in the real editor opens references without insertion")
  func editorRouting() throws {
    let urls = [URL(fileURLWithPath: "/tmp/one.md"), URL(fileURLWithPath: "/tmp/two.markdown")]
    let board = pasteboard(urls)
    defer { board.releaseGlobally() }
    let drag = FileDrag(pasteboard: board)
    let document = MarkdownDocument(contents: TextFileContents(text: "original 👩‍💻"))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let manager = UndoManager()
    coordinator.undoManager = manager
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    editor.setSelectedRange(NSRange(location: 2, length: 3))
    var opened: [URL] = []
    editor.fileDrop.openFiles = {
      opened = $0
      return true
    }
    #expect(editor.draggingEntered(drag) == .copy)
    #expect(editor.prepareForDragOperation(drag))
    #expect(editor.performDragOperation(drag))
    #expect(opened == urls)
    #expect(editor.string == "original 👩‍💻")
    #expect(document.revision == 0)
    #expect(editor.selectedRange() == NSRange(location: 2, length: 3))
    #expect(!manager.canUndo)
    drag.draggingSourceOperationMask = .move
    #expect(editor.draggingEntered(drag).isEmpty)
    #expect(!editor.performDragOperation(drag))
  }

  @Test("Native preview drops route files without loading their source into WebKit")
  func previewRouting() {
    let url = URL(fileURLWithPath: "/tmp/one.md")
    let board = pasteboard([url])
    defer { board.releaseGlobally() }
    let drag = FileDrag(pasteboard: board)
    let preview = MarkdownPreviewWebView(
      frame: .zero,
      configuration: NativeMarkdownPreview.configuration(handler: LocalResourceHandler()))
    var opened: [URL] = []
    preview.fileDrop.openFiles = {
      opened = $0
      return true
    }
    #expect(preview.draggingEntered(drag) == .copy)
    #expect(preview.performDragOperation(drag))
    #expect(opened == [url])
    #expect(preview.url == nil)
    let mixed = pasteboard([url, URL(fileURLWithPath: "/tmp/photo.png")])
    defer { mixed.releaseGlobally() }
    #expect(preview.fileDrop.operation(for: FileDrag(pasteboard: mixed)) == nil)
  }

  @Test("Batch opening preserves order, deduplicates references and continues after one file fails")
  func openingFailures() async {
    _ = NSApplication.shared
    let first = URL(fileURLWithPath: "/tmp/first.md")
    let bad = URL(fileURLWithPath: "/tmp/bad.md")
    let last = URL(fileURLWithPath: "/tmp/last.md")
    let opener = DroppedDocumentOpener()
    var attempted: [URL] = []
    await opener.open([first, bad, first, last], from: DocumentWindowAnchor(nil)) { url in
      #expect(opener.isOpening)
      attempted.append(url)
      if url == bad { throw CocoaError(.fileReadNoPermission) }
    }
    #expect(attempted == [first, bad, last])
    #expect(opener.failures.count == 1)
    #expect(opener.failures[0].contains("bad.md"))
    #expect(!opener.isOpening)
  }

  @Test("User cancellation stops the remainder of an open batch")
  func cancellation() async {
    _ = NSApplication.shared
    let opener = DroppedDocumentOpener()
    var count = 0
    await opener.open(
      [URL(fileURLWithPath: "/tmp/first.md"), URL(fileURLWithPath: "/tmp/last.md")],
      from: DocumentWindowAnchor(nil)
    ) { _ in
      count += 1
      throw CocoaError(.userCancelled)
    }
    #expect(count == 1)
    #expect(opener.failures.isEmpty)
    #expect(!opener.isOpening)
  }

  @Test("Dropped new windows join their origin while existing documents keep their group")
  func newWindowPlacement() {
    _ = NSApplication.shared
    let source = NSWindow()
    source.animationBehavior = .none
    let existing = NSWindow()
    existing.animationBehavior = .none
    let created = NSWindow()
    created.animationBehavior = .none
    let url = URL(fileURLWithPath: "/tmp/one.md")
    for window in [source, existing, created] {
      window.isReleasedWhenClosed = false
      DocumentWindowPolicy.configure(window, preferTabs: false)
    }
    defer { for window in [created, existing, source] { window.close() } }
    existing.representedURL = url
    created.representedURL = url
    let anchor = DocumentWindowAnchor(source)
    DroppedDocumentOpener.placeNewWindow(
      at: url, anchor: anchor, existing: [source, existing], windows: [source, existing, created])
    #expect(source.tabGroup === created.tabGroup)
    #expect(source.tabGroup !== existing.tabGroup)
    #expect(source.tabGroup?.selectedWindow === created)
    source.close()
    DroppedDocumentOpener.placeNewWindow(
      at: url, anchor: anchor, existing: [], windows: [existing])
    #expect(anchor.window == nil)
    #expect(existing.tabGroup?.windows.count == 1)
  }
}

/// Native destination methods consume this protocol; file data is supplied by a real
/// private pasteboard. Unused image/promise APIs are deliberately inert in this fixture.
@MainActor
private final class FileDrag: NSObject, NSDraggingInfo {
  let draggingPasteboard: NSPasteboard
  var draggingSourceOperationMask: NSDragOperation = [.copy, .move]
  var draggingDestinationWindow: NSWindow? { nil }
  var draggingLocation: NSPoint { .zero }
  var draggedImageLocation: NSPoint { .zero }
  nonisolated var draggedImage: NSImage? { nil }
  var draggingSource: Any? { nil }
  var draggingSequenceNumber: Int { 1 }
  var draggingFormation: NSDraggingFormation = .default
  var animatesToDestination = false
  var numberOfValidItemsForDrop = 0
  var springLoadingHighlight: NSSpringLoadingHighlight { .none }

  init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }
  func slideDraggedImage(to screenPoint: NSPoint) {}
  nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL)
    -> [String]?
  {
    nil
  }
  func resetSpringLoading() {}
  func enumerateDraggingItems(
    options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?,
    classes classArray: [AnyClass],
    searchOptions: [NSPasteboard.ReadingOptionKey: Any],
    using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
  ) {}
}
