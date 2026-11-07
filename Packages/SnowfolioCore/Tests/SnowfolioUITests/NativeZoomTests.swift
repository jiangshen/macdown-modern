import AppKit
import DocumentCore
import MarkdownCore
import RenderingCore
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native reading magnification", .serialized, NativeUIExclusive())
@MainActor
struct NativeZoomTests {
  enum TestError: Error { case timeout(String) }

  private func waitFor(_ stage: String, _ predicate: () async throws -> Bool) async throws {
    for _ in 0..<200 {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw TestError.timeout(stage)
  }

  private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let match = view as? T { return match }
    return view.subviews.lazy.compactMap { find(type, in: $0) }.first
  }

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
      as? String ?? ""
  }

  private final class ZoomTestWindow: NSWindow {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
  }

  private func makeWindow(_ content: NSViewController) -> ZoomTestWindow {
    let window = ZoomTestWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = content
    window.setContentSize(NSSize(width: 1200, height: 600))
    window.orderFront(nil)
    return window
  }

  @Test("A complete workspace zooms existing views without changing text, selection or undo")
  func workspace() async throws {
    _ = NSApplication.shared
    let domain = "WorkspaceZoomTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = (1...150).map {
      "Paragraph \($0) with **styled** Unicode 中文 😀 and a longer sentence that wraps in the editor.\n\n"
    }.joined()
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let zoom = DocumentZoomController()
    let host = NSHostingController(
      rootView:
        DocumentWorkspace(document: document, preferences: preferences, zoom: zoom))
    let window = makeWindow(host)
    let undo = window.history
    undo.groupsByEvent = false
    defer { window.close() }
    try await waitFor("native views") {
      find(MarkdownTextView.self, in: host.view) != nil
        && find(WKWebView.self, in: host.view) != nil
    }
    let editor = try #require(find(MarkdownTextView.self, in: host.view))
    let web = try #require(find(WKWebView.self, in: host.view))
    try await waitFor("rendered preview") {
      try await evaluate("return String(document.querySelectorAll('p').length);", in: web) == "150"
    }
    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: 0, length: 9))
    editor.commandController?.perform(.bold)
    #expect(undo.canUndo)
    let text = document.text
    let revision = document.revision
    let selection = editor.selectedRange()
    for _ in 0..<3 { editor.doCommand(by: #selector(NSResponder.scrollPageDown(_:))) }
    try await waitFor("linked paging") {
      try await evaluate("return String(window.scrollY > 500);", in: web) == "true"
    }
    func topParagraph() -> String {
      let offset = min(
        (editor.string as NSString).length - 1,
        editor.characterIndexForInsertion(
          at: NSPoint(x: editor.textContainerInset.width + 1, y: editor.visibleRect.minY + 1)))
      let line = (editor.string as NSString).lineRange(for: NSRange(location: offset, length: 0))
      return "\(line.location):" + (editor.string as NSString).substring(with: line)
    }
    let anchor = topParagraph()
    #expect(editor.visibleRect.minY > 500)
    zoom.zoomIn()
    zoom.zoomIn()
    zoom.zoomIn()
    try await waitFor("150 percent") { editor.font?.pointSize == 21 && web.pageZoom == 1.5 }
    try await waitFor("source reading anchor") { topParagraph() == anchor }
    #expect(find(MarkdownTextView.self, in: host.view) === editor)
    #expect(find(WKWebView.self, in: host.view) === web)
    #expect(editor.selectedRange() == selection)
    #expect(document.text == text && document.revision == revision)
    #expect(preferences.editorFontSize == 14 && preferences.documentTextSize == 16)
    #expect(undo.canUndo)
    let nativePreview = try #require(web.navigationDelegate as? NativeMarkdownPreview.Coordinator)
    try await waitFor("zoom scroll context") {
      nativePreview.isReadyForScrolling(revision: document.revision)
    }
    // A preview-led scroll remains the driver while both panes reflow.
    _ = try await evaluate(
      "window.dispatchEvent(new Event('wheel')); window.scrollTo(0,2200); window.dispatchEvent(new Event('scroll')); return 'moved';",
      in: web)
    try await waitFor("preview-led source") { topParagraph() != anchor }
    let previewLine = try #require(
      Double(
        try await evaluate(
          "return String(globalThis.__snowfolioScroll.position().line);", in: web)))
    zoom.zoomOut()
    try await waitFor("preview-led zoom") { editor.font?.pointSize == 17.5 && web.pageZoom == 1.25 }
    try await waitFor("preview-led anchor") {
      let actual =
        Double(
          try await evaluate(
            "return String(globalThis.__snowfolioScroll.position().line);", in: web)) ?? 0
      return abs(actual - previewLine) < 0.2
    }
    preferences.previewFollowsEditorFont = true
    preferences.editorFontSize = 28
    try await waitFor("relative preview font") {
      editor.font?.pointSize == 35 && web.pageZoom == 2.5
    }
    #expect(document.text == text && editor.selectedRange() == selection)
    #expect(
      try await evaluate("return getComputedStyle(document.body).fontSize;", in: web) == "16px")
    zoom.reset()
    try await waitFor("actual size") { editor.font?.pointSize == 28 && web.pageZoom == 2 }
    undo.undo()
    try await waitFor("undo survives") { document.text == source && editor.string == source }
    undo.redo()
    try await waitFor("redo survives") { document.text == text && editor.string == text }
  }

  @Test("Preview zoom preserves a DOM reading anchor through rapid requests and navigation")
  func previewAnchor() async throws {
    _ = NSApplication.shared
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 500),
      configuration: NativeMarkdownPreview.configuration(
        handler: coordinator.resources,
        scrollHandler: coordinator))
    web.navigationDelegate = coordinator
    let host = NSViewController()
    host.view = web
    let window = makeWindow(host)
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.close()
    }
    let html = (1...160).map {
      "<p data-sourcepos='\($0):1-\($0):40'>Paragraph \($0) with a long reading line 中文 😀</p>"
    }.joined()
    coordinator.update(web, html: html, directory: nil, remoteImages: false, revision: 0)
    try await waitFor("preview ready") {
      (try? await evaluate("return String(document.querySelectorAll('p').length);", in: web))
        == "160"
    }
    _ = try await evaluate(
      "globalThis.savedNode=document.querySelector('p'); globalThis.__snowfolioScroll.scrollToPosition(45.25,false,false); return 'moved';",
      in: web)
    coordinator.update(
      web, html: html, directory: nil, remoteImages: false, revision: 0, zoomScale: 1.5)
    coordinator.update(
      web, html: html, directory: nil, remoteImages: false, revision: 0, zoomScale: 3)
    coordinator.update(
      web, html: html, directory: nil, remoteImages: false, revision: 0, zoomScale: 0.8)
    try await waitFor("latest zoom") { web.pageZoom == 0.8 }
    try await waitFor("DOM anchor") {
      try await evaluate(
        "return String(Math.abs(globalThis.__snowfolioScroll.position().line-45.25)<0.15);", in: web
      ) == "true"
    }
    #expect(
      try await evaluate(
        "return String(globalThis.savedNode === document.querySelector('p'));", in: web) == "true")
    #expect(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    // A gesture after capture must supersede a pending old viewport anchor.
    let epoch = try #require(
      Int(
        try await evaluate(
          "return String(globalThis.__snowfolioScroll.inputEpoch);", in: web)))
    _ = try await evaluate(
      "window.dispatchEvent(new Event('wheel')); globalThis.__snowfolioScroll.scrollToPosition(60.25,false,false); return 'moved';",
      in: web)
    _ = try await web.callAsyncJavaScript(
      PreviewZoom.restore,
      arguments: [
        "line": 45.25, "atTop": false, "atBottom": false, "fraction": 0.1,
        "inputEpoch": epoch,
      ], in: nil, contentWorld: .defaultClient)
    #expect(
      try await evaluate(
        "return String(Math.abs(globalThis.__snowfolioScroll.position().line-60.25)<0.15);",
        in: web) == "true")
    coordinator.update(
      web, html: html, directory: nil, remoteImages: false, revision: 0, zoomScale: 2)
    let newHTML = "<h1 id='new'>New generation</h1>" + html
    coordinator.update(
      web, html: newHTML, directory: URL(filePath: "/private/tmp"),
      remoteImages: false, revision: 1, zoomScale: 1.25)
    try await waitFor("navigation and pending zoom") {
      guard web.pageZoom == 1.25 else { return false }
      return try await evaluate(
        "return document.querySelector('#new')?.textContent ?? '';", in: web) == "New generation"
    }
    coordinator.update(
      web, html: newHTML, directory: URL(filePath: "/private/tmp"),
      remoteImages: false, revision: 1, zoomScale: .nan)
    try await waitFor("invalid scale") { web.pageZoom == 1 }
  }

  @Test("A preview without the linking bootstrap retains its normalized reading position")
  func fallback() async throws {
    _ = NSApplication.shared
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 500),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    web.navigationDelegate = coordinator
    let host = NSViewController()
    host.view = web
    let window = makeWindow(host)
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      window.close()
    }
    let html = (1...100).map { "<p>Paragraph \($0)</p>" }.joined()
    coordinator.update(web, html: html, directory: nil, remoteImages: false)
    try await waitFor("fallback content") {
      (try? await evaluate("return String(document.querySelectorAll('p').length);", in: web))
        == "100"
    }
    _ = try await evaluate(
      "window.scrollTo(0,(document.documentElement.scrollHeight-innerHeight)*0.4); return 'moved';",
      in: web)
    coordinator.update(web, html: html, directory: nil, remoteImages: false, zoomScale: 2)
    try await waitFor("fallback zoom") { web.pageZoom == 2 }
    try await waitFor("fallback position") {
      try await evaluate(
        "return String(Math.abs(scrollY/(document.documentElement.scrollHeight-innerHeight)-0.4)<0.01);",
        in: web) == "true"
    }
  }
}
