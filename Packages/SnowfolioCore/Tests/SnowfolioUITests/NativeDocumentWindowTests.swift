import AppKit
import DocumentCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native document workspace window", .serialized, NativeUIExclusive())
@MainActor
struct NativeDocumentWindowTests {
  @Test("The complete native workspace keeps document, editor and Undo ownership together")
  func nativeOwnership() async throws {
    _ = NSApplication.shared
    let domain = "NativeDocumentWindowTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let native = NativeMarkdownDocument()
    let original = "# Native window\n\nShared source and preview.\n"
    let bytes = Data(original.utf8)
    try native.read(from: bytes, ofType: "public.plain-text")
    let controller = NativeDocumentWindowController(
      document: native, preferences: preferences, state: native.workspaceState)
    native.addWindowController(controller)
    let window = try #require(controller.window)
    window.animationBehavior = .none
    window.orderFront(nil)
    defer { native.close() }
    func source(in view: NSView) -> MarkdownTextView? {
      if let editor = view as? MarkdownTextView { return editor }
      return view.subviews.lazy.compactMap { source(in: $0) }.first
    }
    func preview(in view: NSView) -> WKWebView? {
      if let web = view as? WKWebView { return web }
      return view.subviews.lazy.compactMap { preview(in: $0) }.first
    }
    let content = try #require(window.contentView)
    for _ in 0..<200 {
      if source(in: content) != nil, preview(in: content) != nil { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    let editor = try #require(source(in: content))
    _ = try #require(preview(in: content))
    #expect(window.windowController === controller)
    #expect(controller.document as? NSDocument === native)
    #expect(window.contentMinSize.width >= 720)
    #expect(window.contentMinSize.height >= 360)
    #expect(content.bounds.width >= 720)
    #expect(content.bounds.height >= 360)
    #expect(editor.string == original)
    let manager = try #require(native.undoManager)
    #expect(editor.undoManager === manager)
    manager.groupsByEvent = false
    manager.beginUndoGrouping()
    editor.insertText("X", replacementRange: NSRange(location: original.utf16.count, length: 0))
    manager.endUndoGrouping()
    #expect(native.markdownDocument.text == original + "X")
    manager.undo()
    #expect(native.markdownDocument.text == original)
    #expect(editor.string == original)
    #expect(try native.data(ofType: "public.plain-text") == bytes)
  }

  @Test("Native restoration callbacks recover workspace state without replacing source")
  func nativeRestoration() throws {
    _ = NSApplication.shared
    let source = NativeMarkdownDocument()
    source.workspaceState.mode = .preview
    source.workspaceState.zoomPercent = 125
    source.workspaceState.editorSelection = Data([1, 2, 3])
    source.workspaceState.sourceViewport = Data([4, 5, 6])
    source.workspaceState.previewViewport = Data([7, 8, 9])
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    source.encodeRestorableState(with: coder)
    coder.finishEncoding()

    let restored = NativeMarkdownDocument()
    let bytes = Data("# Keep document bytes\r\n".utf8)
    try restored.read(from: bytes, ofType: "public.plain-text")
    let model = restored.markdownDocument
    let revision = model.revision
    let decoder = try NSKeyedUnarchiver(forReadingFrom: coder.encodedData)
    decoder.requiresSecureCoding = true
    defer { decoder.finishDecoding() }
    restored.restoreState(with: decoder)
    #expect(restored.workspaceState.mode == .preview)
    #expect(restored.workspaceState.zoomPercent == 125)
    #expect(restored.workspaceState.editorSelection == source.workspaceState.editorSelection)
    #expect(restored.workspaceState.sourceViewport == source.workspaceState.sourceViewport)
    #expect(restored.workspaceState.previewViewport == source.workspaceState.previewViewport)
    #expect(model.revision == revision)
    #expect(try restored.data(ofType: "public.plain-text") == bytes)
  }

}
