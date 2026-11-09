import AppKit
import DocumentCore
import EditorCore
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
    let previewView = try #require(preview(in: content))
    #expect(previewView.window === window)
    #expect(!previewView.isHiddenOrHasHiddenAncestor)
    #expect(previewView.visibleRect.width > 0)
    #expect(previewView.visibleRect.height > 0)
    #expect(content.bounds.contains(previewView.convert(previewView.bounds, to: content)))
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
    for _ in 0..<200 {
      if native.html.contains("Native window") { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(native.html.contains("Native window"))
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

  @Test("Native restoration reopens independent real source and preview reading positions")
  func nativeViewportRestoration() async throws {
    _ = NSApplication.shared
    let domain = "NativeViewportRestoration.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.synchronizedScrolling = false
    let text = (1...160).map { "## Section \($0) 中文 👩‍💻\r\n\r\nParagraph e\u{301}.\r\n\r\n" }.joined()
    let bytes = Data([0xFF, 0xFE]) + (try #require(text.data(using: .utf16LittleEndian)))
    func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
      if let result = view as? T { return result }
      return view.subviews.lazy.compactMap { find(type, in: $0) }.first
    }
    func ready(_ condition: () async throws -> Bool) async throws {
      let deadline = ContinuousClock.now.advanced(by: .seconds(5))
      while try await !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(25))
      }
      try #require(await condition())
    }
    func open(_ document: NativeMarkdownDocument) throws -> NativeDocumentWindowController {
      let controller = NativeDocumentWindowController(
        document: document, preferences: preferences, state: document.workspaceState)
      document.addWindowController(controller)
      let window = try #require(controller.window)
      window.animationBehavior = .none
      window.orderFront(nil)
      return controller
    }
    func previewY(_ web: WKWebView) async throws -> Double {
      try await web.callAsyncJavaScript(
        "return window.scrollY;", arguments: [:], in: nil, contentWorld: .defaultClient)
        as? Double ?? -1
    }
    let original = NativeMarkdownDocument()
    try original.read(from: bytes, ofType: "public.plain-text")
    defer { original.close() }
    let controller = try open(original)
    try await ready { controller.commands.editor?.coordinator?.scrolling != nil }
    let content = try #require(controller.window?.contentView)
    let editor = try #require(find(MarkdownTextView.self, in: content))
    let web = try #require(find(WKWebView.self, in: content))
    let scrolling = try #require(controller.commands.editor?.coordinator?.scrolling)
    let scroll = try #require(editor.enclosingScrollView)
    try await ready {
      guard original.html.contains("Section 160") else { return false }
      return (try? await previewY(web)) == 0
    }
    controller.window?.makeFirstResponder(editor)
    let selection = NSRange(location: 3, length: 5)
    editor.setSelectedRange(selection)
    NotificationCenter.default.post(
      name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 1400))
    scroll.reflectScrolledClipView(scroll.contentView)
    NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    let sourcePosition = try #require(scrolling.captureSource())
    #expect(!sourcePosition.atTop && sourcePosition.offset > 0)
    _ = try await web.callAsyncJavaScript(
      "window.dispatchEvent(new Event('wheel')); window.scrollTo(0, 2800); window.dispatchEvent(new Event('scroll')); return true;",
      arguments: [:], in: nil, contentWorld: .defaultClient)
    try await ready { original.workspaceState.previewViewport != nil }
    scrolling.flush()
    let sourceData = try #require(original.workspaceState.sourceViewport)
    let previewData = try #require(original.workspaceState.previewViewport)
    let previewPosition = try JSONDecoder().decode(MarkdownScrollPosition.self, from: previewData)
    #expect(previewPosition.line > 0 && !previewPosition.atTop)
    let originalPreviewY = try await previewY(web)
    #expect(originalPreviewY > 1000)
    #expect(scrolling.captureSource()?.offset == sourcePosition.offset)
    #expect(editor.selectedRange() == selection)
    let coder = NSKeyedArchiver(requiringSecureCoding: true)
    original.encodeRestorableState(with: coder)
    coder.finishEncoding()
    original.close()

    let restored = NativeMarkdownDocument()
    try restored.read(from: bytes, ofType: "public.plain-text")
    defer { restored.close() }
    let loadedRevision = restored.markdownDocument.revision
    let decoder = try NSKeyedUnarchiver(forReadingFrom: coder.encodedData)
    decoder.requiresSecureCoding = true
    restored.restoreState(with: decoder)
    decoder.finishDecoding()
    #expect(restored.workspaceState.sourceViewport == sourceData)
    #expect(restored.workspaceState.previewViewport == previewData)
    let reopened = try open(restored)
    try await ready { reopened.commands.editor?.coordinator?.scrolling != nil }
    let restoredContent = try #require(reopened.window?.contentView)
    let restoredEditor = try #require(find(MarkdownTextView.self, in: restoredContent))
    let restoredPreview = try #require(find(WKWebView.self, in: restoredContent))
    let restoredScrolling = try #require(reopened.commands.editor?.coordinator?.scrolling)
    try await ready {
      guard let position = restoredScrolling.captureSource() else { return false }
      return position.offset == sourcePosition.offset
        && abs(position.fraction - sourcePosition.fraction) < 0.1
    }
    try await ready { abs((try await previewY(restoredPreview)) - originalPreviewY) < 3 }
    #expect(restoredEditor.selectedRange() == selection)
    #expect(restoredEditor.string == text)
    #expect(restored.markdownDocument.revision == loadedRevision)
    #expect(restored.undoManager?.canUndo == false)
    #expect(!restored.isDocumentEdited)
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
    // AppKit may finish the reload before the directory-monitor callback is
    // delivered. Require both observations within the same existing deadline.
    while model.text != replacement || native.changeNotifications <= notificationsBeforeReplacement,
      ContinuousClock.now < deadline
    {
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
