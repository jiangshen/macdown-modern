import AppKit
import DocumentCore
import SwiftUI
import Synchronization
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
      if source(in: content) != nil, preview(in: content) != nil,
        controller.commands.editor != nil, controller.commands.output?.window === window
      {
        break
      }
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
    let screen = try #require(window.screen)
    if screen.visibleFrame.width >= window.frame.width,
      screen.visibleFrame.height >= window.frame.height
    {
      #expect(window.frame.minX >= screen.visibleFrame.minX)
      #expect(window.frame.maxX <= screen.visibleFrame.maxX)
      #expect(window.frame.minY >= screen.visibleFrame.minY)
      #expect(window.frame.maxY <= screen.visibleFrame.maxY)
    }
    #expect(editor.string == original)
    #expect(controller.commands.editor?.coordinator?.editor === editor)
    #expect(controller.commands.output?.window === window)
    #expect(controller.commands.zoom != nil)
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

    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: 2, length: 6))
    let format = NSHostingMenu(
      rootView: MarkdownFormatMenuContent(editor: controller.commands.editor))
    for _ in 0..<100 {
      format.update()
      if format.item(withTitle: "Bold")?.isEnabled == true { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    let bold = try #require(format.item(withTitle: "Bold"))
    #expect(bold.isEnabled)
    format.performActionForItem(at: format.index(of: bold))
    #expect(native.markdownDocument.text == "# **Native** window\n\nShared source and preview.\n")
    manager.undo()
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

  @Test("Native Save As preserves encoding, the original file and the live document location")
  func nativeSaveAs() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioNativeSaveAs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destinationDirectory = directory.appendingPathComponent("Saved copy", isDirectory: true)
    try FileManager.default.createDirectory(
      at: destinationDirectory, withIntermediateDirectories: true)
    let originalURL = directory.appendingPathComponent("original.md")
    let destination = destinationDirectory.appendingPathComponent("renamed.md")
    let text = "# Native Save As 中文 👩‍💻\r\n"
    let bom = Data([0xFF, 0xFE])
    let bytes = bom + (try #require(text.data(using: .utf16LittleEndian)))
    try bytes.write(to: originalURL)
    let document = try NativeMarkdownDocument(contentsOf: originalURL, ofType: "public.plain-text")
    defer { document.close() }
    let model = document.markdownDocument
    let undo = try #require(document.undoManager)
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    model.replaceText(with: text + "Saved e\u{301}\r\n", undoManager: undo)
    undo.endUndoGrouping()
    let revision = model.revision
    let edited = try model.fileContents.encoded()
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      document.save(to: destination, ofType: "public.plain-text", for: .saveAsOperation) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    #expect(document.fileURL == destination)
    #expect(model.fileURL == destination)
    #expect(model.revision == revision)
    #expect(try Data(contentsOf: originalURL) == bytes)
    #expect(try Data(contentsOf: destination) == edited)
    // Let the destination watcher process our own Save As. It must not
    // mistake that write for an external replacement and clear native Undo.
    try await Task.sleep(for: .milliseconds(200))
    #expect(undo.canUndo)
    undo.undo()
    #expect(model.text == text)
    #expect(try document.data(ofType: "public.plain-text") == bytes)
  }

  @Test("A clean native document reloads an uncoordinated atomic replacement")
  func atomicExternalReload() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioNativeAtomicReload-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("document.md")
    let original = Data("# Original 中文 👩‍💻\n".utf8)
    try original.write(to: file)
    let native = try AtomicReloadDocument(contentsOf: file, ofType: "public.plain-text")
    NSDocumentController.shared.addDocument(native)
    native.makeWindowControllers()
    defer { native.close() }
    let model = native.markdownDocument
    #expect(model.text == "# Original 中文 👩‍💻\n")
    #expect(!native.isDocumentEdited)
    #expect(NSFileCoordinator.filePresenters.contains { ($0 as AnyObject) === native })
    // Let the watcher arm, as it does before a real open-panel workflow returns.
    try await Task.sleep(for: .milliseconds(200))
    let notificationsBeforeReplacement = native.changeNotifications
    let replacement = "# External e\u{301}\r\n\r\nReplaced without coordination.\r\n"
    let bytes = Data([0xFF, 0xFE]) + (try #require(replacement.data(using: .utf16LittleEndian)))
    try bytes.write(to: file, options: .atomic)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while model.text != replacement, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(native.changeNotifications > notificationsBeforeReplacement)
    #expect(native.readCount >= 2)
    #expect(model.text == replacement)
    #expect(!native.isDocumentEdited)
    #expect(try Data(contentsOf: file) == bytes)
    #expect(try native.data(ofType: "public.plain-text") == bytes)
  }

  @Test(
    "External atomic replacement preserves unsaved edits and marked text", arguments: [false, true])
  func preservesPendingInput(composing: Bool) async throws {
    _ = NSApplication.shared
    let documentController = NSDocumentController.shared
    let originalDelay = documentController.autosavingDelay
    documentController.autosavingDelay = 30
    defer { documentController.autosavingDelay = originalDelay }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioNativePendingInput-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("document.md")
    let original = "# Keep local source\n"
    try Data(original.utf8).write(to: file)
    let native = try AtomicReloadDocument(contentsOf: file, ofType: "public.plain-text")
    NSDocumentController.shared.addDocument(native)
    native.makeWindowControllers()
    defer { native.close() }
    let model = native.markdownDocument
    let composingEditor = NSTextView(usingTextLayoutManager: true)
    if composing {
      native.attachSourceEditor(composingEditor)
      composingEditor.setMarkedText(
        "入力", selectedRange: NSRange(location: 2, length: 0),
        replacementRange: NSRange(location: 0, length: 0))
      #expect(composingEditor.hasMarkedText())
      #expect(!native.isDocumentEdited)
    } else {
      // This fixture bypasses a real event/Undo transaction, so use the
      // documented NSDocument change API to stage unsaved native state.
      // Actual editor/Undo ownership is exercised by the separate UI methods.
      model.acceptNativeEdit(original + "X")
      native.updateChangeCount(.changeDone)
      #expect(native.isDocumentEdited)
      #expect(try Data(contentsOf: file) == Data(original.utf8))
    }
    try await Task.sleep(for: .milliseconds(200))
    let before = native.changeNotifications
    let external = Data("# External replacement 中文 👩‍💻\n".utf8)
    try external.write(to: file, options: .atomic)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while native.changeNotifications <= before, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(native.changeNotifications > before)
    #expect(native.readCount == 1)
    #expect(model.text == (composing ? original : original + "X"))
    #expect(try Data(contentsOf: file) == external)
    if composing {
      #expect(composingEditor.hasMarkedText())
      composingEditor.unmarkText()
      native.detachSourceEditor(composingEditor)
    }
  }

}

@MainActor
private final class AtomicReloadDocument: NativeMarkdownDocument {
  private nonisolated let counts = Mutex((changes: 0, reads: 0))
  nonisolated var changeNotifications: Int { counts.withLock { $0.changes } }
  nonisolated var readCount: Int { counts.withLock { $0.reads } }

  nonisolated override func presentedItemDidChange() {
    counts.withLock { $0.changes += 1 }
    super.presentedItemDidChange()
  }

  nonisolated override func read(from data: Data, ofType typeName: String) throws {
    counts.withLock { $0.reads += 1 }
    try super.read(from: data, ofType: typeName)
  }
}
