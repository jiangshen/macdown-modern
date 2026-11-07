import AppKit
import DocumentCore
import EditorCore
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native pane ordering", .serialized)
@MainActor
struct NativePaneOrderTests {
  enum TestError: Error { case timeout }

  private func waitFor(_ predicate: () async throws -> Bool) async throws {
    for _ in 0..<160 {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw TestError.timeout
  }

  private func webView(in view: NSView) -> WKWebView? {
    if let web = view as? WKWebView { return web }
    return view.subviews.lazy.compactMap { webView(in: $0) }.first
  }

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
      as? String ?? ""
  }

  @Test("The persisted preference updates the complete workspace without replacing document views")
  func workspacePreference() async throws {
    _ = NSApplication.shared
    let domain = "PaneOrderWorkspaceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = "# Pane order\n\nThe same native document stays open."
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let host = NSHostingController(
      rootView: DocumentWorkspace(document: document, preferences: preferences))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1100, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    func editor(in view: NSView) -> MarkdownTextView? {
      if let source = view as? MarkdownTextView { return source }
      return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }
    try await waitFor { editor(in: host.view) != nil && webView(in: host.view) != nil }
    let originalEditor = try #require(editor(in: host.view))
    let originalPreview = try #require(webView(in: host.view))
    originalEditor.setSelectedRange(NSRange(location: 2, length: 4))
    func isRight() -> Bool {
      originalEditor.convert(originalEditor.bounds, to: host.view).minX
        > originalPreview.convert(originalPreview.bounds, to: host.view).minX
    }
    #expect(!isRight())
    preferences.editorOnRight = true
    try await waitFor { isRight() }
    #expect(defaults.bool(forKey: "editorOnRight"))
    #expect(editor(in: host.view) === originalEditor)
    #expect(webView(in: host.view) === originalPreview)
    #expect(originalEditor.selectedRange() == NSRange(location: 2, length: 4))
    preferences.editorOnRight = false
    try await waitFor { !isRight() }
    #expect(document.text == source)
    #expect(document.revision == 0)
  }

  @Test(
    "Swapping and hidden-pane changes preserve the native views, width, reading positions and undo",
    arguments: [false, true])
  func paneLifetime(initialRight: Bool) async throws {
    _ = NSApplication.shared
    let domain = "PaneOrderTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = "word\n\n" + (1...150).map { "Paragraph \($0) with Unicode 中文 😀\n\n" }.joined()
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let commands = EditorCommandController()
    let undo = UndoManager()
    undo.groupsByEvent = false
    let editorSurface = NativeDocumentSplit.EditorSurface(
      document: document, preferences: preferences,
      commands: commands, undoManager: undo, editorSelection: .constant(nil))
    let previewSurface = NativeDocumentSplit.PreviewSurface(
      html: (1...150).map { "<p>Preview paragraph \($0)</p>" }.joined(), directory: nil,
      remoteImages: false, error: .constant(nil))
    let controller = NativeDocumentSplit.Controller(
      editor: editorSurface, preview: previewSurface,
      mode: .split, editorOnRight: initialRight)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1000, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    try await waitFor { commands.coordinator?.editor != nil && webView(in: controller.view) != nil }
    let editor = try #require(commands.coordinator?.editor)
    let web = try #require(webView(in: controller.view))
    try await waitFor {
      try await evaluate("return String(document.querySelectorAll('p').length);", in: web) == "150"
    }
    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: 0, length: 4))
    commands.perform(.bold)
    #expect(undo.canUndo)
    let modified = document.text
    let selection = editor.selectedRange()
    controller.view.layoutSubtreeIfNeeded()
    let available = controller.splitView.bounds.width - controller.splitView.dividerThickness
    controller.splitView.setPosition(initialRight ? available - 360 : 360, ofDividerAt: 0)
    controller.view.layoutSubtreeIfNeeded()
    let width = controller.editorHost.view.frame.width
    let location = (editor.string as NSString).range(of: "Paragraph 40").location
    editor.scrollRangeToVisible(NSRange(location: location, length: 0))
    _ = try await evaluate("window.scrollTo(0, 700); return 'moved';", in: web)
    let sourceY = editor.visibleRect.minY
    let previewY = try await evaluate("return String(window.scrollY);", in: web)
    #expect(sourceY > 100)
    func editorIsRight() -> Bool {
      controller.editorHost.view.convert(
        controller.editorHost.view.bounds, to: controller.splitView
      ).minX
        > controller.previewHost.view.convert(
          controller.previewHost.view.bounds, to: controller.splitView
        ).minX
    }
    #expect(editorIsRight() == initialRight)

    controller.setEditorOnRight(!initialRight)
    controller.view.layoutSubtreeIfNeeded()
    #expect(editorIsRight() != initialRight)
    #expect(abs(controller.editorHost.view.frame.width - width) < 1)
    #expect(commands.coordinator?.editor === editor)
    #expect(webView(in: controller.view) === web)
    #expect(window.firstResponder === editor)
    #expect(editor.selectedRange() == selection)
    #expect(abs(editor.visibleRect.minY - sourceY) < 1)
    #expect(try await evaluate("return String(window.scrollY);", in: web) == previewY)

    controller.setMode(.preview, editing: commands)
    controller.setEditorOnRight(initialRight)
    #expect(controller.splitViewItem(for: controller.editorHost)?.isCollapsed == true)
    #expect(controller.splitViewItem(for: controller.previewHost)?.isCollapsed == false)
    controller.setMode(.split, editing: commands)
    #expect(window.makeFirstResponder(web))
    let focusedPreview = try #require(window.firstResponder as? NSView)
    #expect(focusedPreview.isDescendant(of: controller.previewHost.view))
    controller.setMode(.editor, editing: commands)
    #expect(window.firstResponder === editor)
    controller.setEditorOnRight(!initialRight)
    #expect(controller.splitViewItem(for: controller.editorHost)?.isCollapsed == false)
    #expect(controller.splitViewItem(for: controller.previewHost)?.isCollapsed == true)
    controller.setMode(.split, editing: commands)
    controller.view.layoutSubtreeIfNeeded()
    #expect(abs(controller.editorHost.view.frame.width - width) < 1)
    #expect(commands.coordinator?.editor === editor)
    #expect(webView(in: controller.view) === web)
    #expect(editor.selectedRange() == selection)
    #expect(document.text == modified)
    undo.undo()
    #expect(document.text == source)
    undo.redo()
    #expect(document.text == modified)
    #expect(editor.textLayoutManager != nil)
    #expect(
      NSImage(
        systemSymbolName: WorkspaceMode.editor.symbol(editorOnRight: true),
        accessibilityDescription: nil) != nil)
  }
}
