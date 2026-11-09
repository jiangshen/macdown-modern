import AppKit
import DocumentCore
import EditorCore
import MarkdownCore
import RenderingCore
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native source and preview scrolling", .serialized, NativeUIExclusive())
@MainActor
struct NativeScrollTests {
  enum TestError: Error { case timeout(String) }

  private func evaluate(
    _ script: String, in view: WKWebView, world: WKContentWorld = .defaultClient
  ) async throws -> String {
    try await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: world)
      as? String ?? ""
  }

  private func waitFor(
    _ stage: String = #function, diagnostic: () async throws -> String = { "" },
    _ predicate: () async throws -> Bool
  )
    async throws
  {
    for _ in 0..<160 {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw TestError.timeout(stage + (try await diagnostic()))
  }

  @MainActor
  private final class Fixture {
    let document: MarkdownDocument
    let scrolling = DocumentScrollCoordinator()
    let editorCoordinator: NativeMarkdownEditor.Coordinator
    let scroll: NSScrollView
    let editor: MarkdownTextView
    let sourceWindow: NSWindow
    let previewCoordinator = NativeMarkdownPreview.Coordinator()
    let preview: WKWebView
    let previewWindow: NSWindow
    let undo = UndoManager()
    var sourceData: Data?
    var previewData: Data?

    init(source: String, sourceData: Data? = nil, previewData: Data? = nil, linked: Bool = false)
      throws
    {
      _ = NSApplication.shared
      document = MarkdownDocument(contents: TextFileContents(text: source))
      self.sourceData = sourceData
      self.previewData = previewData
      editorCoordinator = NativeMarkdownEditor.Coordinator(document: document)
      scroll = NativeMarkdownEditor.makeScrollView(
        document: document, coordinator: editorCoordinator)
      editor = try #require(scroll.documentView as? MarkdownTextView)
      sourceWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
        styleMask: .titled, backing: .buffered, defer: false)
      sourceWindow.isReleasedWhenClosed = false
      sourceWindow.contentView = scroll
      preview = WKWebView(
        frame: NSRect(x: 0, y: 0, width: 650, height: 400),
        configuration: NativeMarkdownPreview.configuration(
          handler: previewCoordinator.resources, scrollHandler: previewCoordinator))
      previewWindow = NSWindow(
        contentRect: preview.frame, styleMask: .titled, backing: .buffered, defer: false)
      previewWindow.isReleasedWhenClosed = false
      previewWindow.contentView = preview
      editorCoordinator.undoManager = undo
      sourceWindow.orderFront(nil)
      previewWindow.orderFront(nil)
      editor.setFrameSize(NSSize(width: 600, height: 400))
      editor.textContainer?.containerSize.width = 550
      editor.textLayoutManager?.ensureLayout(
        for: try #require(editor.textLayoutManager?.textContentManager?.documentRange))
      editor.sizeToFit()
      scrolling.configure(
        document: document, linked: linked, mode: .split,
        sourceStorage: Binding(
          get: { [weak self] in self?.sourceData }, set: { [weak self] in self?.sourceData = $0 }),
        previewStorage: Binding(
          get: { [weak self] in self?.previewData }, set: { [weak self] in self?.previewData = $0 })
      )
      scrolling.attachSource(editor)
      editorCoordinator.scrolling = scrolling
      previewCoordinator.scrolling = scrolling
      scrolling.attachPreview(previewCoordinator)
      preview.navigationDelegate = previewCoordinator
    }

    func loadPreview(directory: URL? = nil) async throws {
      let rendered = try await MarkdownProcessor().render(document.text)
      previewCoordinator.update(
        preview, html: rendered.html, directory: directory, remoteImages: false,
        revision: document.revision)
    }

    func close() {
      scrolling.detachSource(editor)
      scrolling.detachPreview(previewCoordinator)
      preview.stopLoading()
      preview.navigationDelegate = nil
      previewCoordinator.resources.cancelAll()
      sourceWindow.close()
      previewWindow.close()
    }
  }

  @Test("Preview input supersedes a queued source move before its next animation frame")
  func queuedSourceMoveAfterPreviewInput() async throws {
    let source = (1...150).map {
      "Paragraph \($0) with **styled** Unicode 中文 😀 and a sentence that wraps in the editor.\n\n"
    }.joined()
    let fixture = try Fixture(source: source, linked: true)
    defer { fixture.close() }
    try await fixture.loadPreview()
    try await waitFor("scroll context") {
      fixture.previewCoordinator.isReadyForScrolling(revision: 0)
    }
    fixture.sourceWindow.makeFirstResponder(fixture.editor)
    fixture.scrolling.sourceEditedOrNavigated()
    let selection = fixture.editor.selectedRange()
    @MainActor final class Completion {
      var inputFinished = false
      var moveFinished = false
      var error: (any Error)?
    }
    let completion = Completion()
    // Queue both IPC calls in one main-actor turn. The native move captures its
    // context before the WebKit input message can be delivered back to AppKit.
    fixture.preview.callAsyncJavaScript(
      "window.dispatchEvent(new Event('wheel')); window.scrollTo(0,2200); window.dispatchEvent(new Event('scroll')); return true;",
      arguments: [:], in: nil, in: .defaultClient
    ) { result in
      if case .failure(let error) = result { completion.error = error }
      completion.inputFinished = true
    }
    fixture.previewCoordinator.moveForScrolling(
      to: MarkdownScrollPosition(line: 240, atTop: false, atBottom: false)
    ) { completion.moveFinished = true }
    try await waitFor("queued callbacks") { completion.inputFinished && completion.moveFinished }
    if let error = completion.error { throw error }
    try await waitFor("preview retains input and moves source") {
      let y = Double(try await evaluate("return String(scrollY);", in: fixture.preview)) ?? -1
      guard let reading = fixture.scrolling.captureSource() else { return false }
      return abs(y - 2200) < 1 && !reading.atTop && reading.offset > 0
    }
    let previewSource = try #require(fixture.scrolling.captureSource())
    fixture.editor.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
    try await waitFor(
      "a later source gesture takes control",
      diagnostic: {
        let web = try await evaluate(
          "return JSON.stringify({y:scrollY, input:globalThis.__snowfolioScroll?.inputEpoch,sourceInput:globalThis.__snowfolioScroll?.sourceInputEpoch,position:globalThis.__snowfolioScroll?.position()});",
          in: fixture.preview)
        return
          " before=\(previewSource), web=\(web), source=\(String(describing: fixture.scrolling.captureSource()))"
      },
      {
        let y = Double(try await evaluate("return String(scrollY);", in: fixture.preview)) ?? -1
        return y > 2300 && (fixture.scrolling.captureSource()?.offset ?? 0) > previewSource.offset
      })
    #expect(fixture.editor.string == source && fixture.document.text == source)
    #expect(fixture.document.revision == 0 && !fixture.undo.canUndo)
    #expect(fixture.editor.selectedRange() == selection)
  }

  @Test("Source reflow keeps its reading target until a new preview gesture supersedes it")
  func reflowRetainsSourceAuthority() async throws {
    let source = (1...150).map {
      "Paragraph \($0) 中文 👩‍💻 " + String(repeating: "A reading line with wrapping text. ", count: 10)
        + "\n\n"
    }.joined()
    let fixture = try Fixture(source: source, linked: true)
    defer { fixture.close() }
    fixture.scrolling.sourceEditedOrNavigated()
    fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 800))
    let before = try #require(fixture.scrolling.captureSource())
    #expect(!before.atTop && before.offset > 0)
    let selection = fixture.editor.selectedRange()
    fixture.scrolling.sourcePresentationWillChange()
    // A delayed WebKit scroll report can arrive while the source is reflowing.
    // It is not new preview input and must not take control of the reading target.
    fixture.scrolling.previewScrolled(
      MarkdownScrollPosition(line: 1, atTop: true), revision: 0,
      programmatic: false, settled: false)
    let retained = try #require(fixture.scrolling.captureSource())
    #expect(retained.offset == before.offset && !retained.atTop)
    // A real gesture has its own input message before the throttled scroll report.
    fixture.scrolling.previewInputBegan(revision: 0)
    fixture.scrolling.previewScrolled(
      MarkdownScrollPosition(line: 1, atTop: true), revision: 0,
      programmatic: false, settled: true)
    #expect(fixture.scrolling.captureSource()?.atTop == true)
    #expect(fixture.editor.selectedRange() == selection)
    #expect(fixture.editor.string == source && fixture.document.text == source)
    #expect(fixture.document.revision == 0 && !fixture.undo.canUndo)
  }

  @Test("Native keyboard paging drives linked preview scrolling without editing or selecting")
  func keyboardPaging() async throws {
    let source = (1...150).map { "Paragraph \($0)\n\n" }.joined()
    let fixture = try Fixture(source: source, linked: true)
    defer { fixture.close() }
    try await fixture.loadPreview()
    try await waitFor { fixture.previewCoordinator.isReadyForScrolling(revision: 0) }
    fixture.sourceWindow.makeFirstResponder(fixture.editor)
    let selection = fixture.editor.selectedRange()
    fixture.editor.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
    try await waitFor {
      try await evaluate("return String(window.scrollY > 200);", in: fixture.preview) == "true"
    }
    #expect(fixture.editor.selectedRange() == selection)
    #expect(fixture.editor.string == source)
    #expect(!fixture.undo.canUndo)
  }

  @Test("A new split workspace shows rendered preview before any layout-mode change")
  func initialSplitPreview() async throws {
    _ = NSApplication.shared
    let source = "# Fresh split preview\n\nThis preview must appear immediately."
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let rendered = try await MarkdownProcessor().render(source)
    let domain = "SplitPreviewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let editing = EditorCommandController()
    let scrolling = DocumentScrollCoordinator()
    scrolling.configure(
      document: document, linked: true, mode: .split,
      sourceStorage: .constant(nil), previewStorage: .constant(nil))
    let controller = NativeDocumentSplit.Controller(
      editor: NativeDocumentSplit.EditorSurface(
        document: document, preferences: preferences,
        commands: editing, undoManager: nil, editorSelection: .constant(nil), scrolling: scrolling),
      preview: NativeDocumentSplit.PreviewSurface(
        html: rendered.html, directory: nil,
        remoteImages: false, revision: 0, scrolling: scrolling, error: .constant(nil)), mode: .split
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 500),
      styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1000, height: 500))
    window.orderFront(nil)
    defer { window.close() }
    func preview(in view: NSView) -> WKWebView? {
      if let web = view as? WKWebView { return web }
      return view.subviews.lazy.compactMap { preview(in: $0) }.first
    }
    try await waitFor("initial split preview") {
      guard let web = preview(in: controller.view), web.bounds.height > 100,
        web.bounds.width > 100, !web.isHiddenOrHasHiddenAncestor
      else { return false }
      return
        (try? await evaluate(
          "return document.querySelector('h1')?.textContent.trim() ?? '';", in: web))
        == "Fresh split preview"
    }
    #expect(editing.coordinator?.editor?.textLayoutManager != nil)
    #expect(document.revision == 0)
  }

  @Test("A document workspace renders a snapshot delivered after its split views are created")
  func deferredWorkspaceSnapshot() async throws {
    _ = NSApplication.shared
    let document = MarkdownDocument()
    let domain = "WorkspacePreviewTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let host = NSHostingController(
      rootView: DocumentWorkspace(document: document, preferences: preferences))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1100, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    func preview(in view: NSView) -> WKWebView? {
      if let web = view as? WKWebView { return web }
      return view.subviews.lazy.compactMap { preview(in: $0) }.first
    }
    try await waitFor("workspace created preview") { preview(in: host.view) != nil }
    try await document.apply(
      snapshot: TextFileContents(
        text: "# Deferred file contents\n\nVisible in the initial split workspace."), previous: nil)
    try await waitFor("deferred workspace preview") {
      guard let web = preview(in: host.view), web.bounds.height > 100, web.bounds.width > 100 else {
        return false
      }
      return
        (try? await evaluate(
          "return document.querySelector('h1')?.textContent.trim() ?? '';", in: web))
        == "Deferred file contents"
    }
    #expect(document.loadRevision == 1)
  }

  @Test("A hidden closing viewport cannot replace the last visible reading position")
  func hiddenViewportPersistence() async throws {
    let source = (1...150).map { "Paragraph \($0)\n\n" }.joined()
    let fixture = try Fixture(source: source)
    defer { fixture.close() }
    fixture.editor.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
    try await waitFor("saved visible source") {
      guard let data = fixture.sourceData else { return false }
      return try JSONDecoder().decode(SourceReadingPosition.self, from: data).offset > 0
    }
    let saved = fixture.sourceData
    fixture.sourceWindow.orderOut(nil)
    fixture.scroll.contentView.scroll(to: .zero)
    fixture.scrolling.layoutChanged()
    await Task.yield()
    fixture.scrolling.flush()
    #expect(fixture.sourceData == saved)
  }

  @Test(
    "Restored source paints through deferred loading, styling and native focus",
    arguments: [false, true])
  func restoredSourcePainting(dark: Bool) async throws {
    let source = (1...120).map {
      "## Note \($0)\n\nA winter thought with **bold words**, plain words across the whole line, 中文 and 😀.\n\n- Read\n- Write\n\n"
    }.joined()
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let domain = "RestoredPaintingTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
    func root(
      document: MarkdownDocument, scrolling: DocumentScrollCoordinator,
      editing: EditorCommandController, saved: Data?, styled: Bool
    ) -> NativeDocumentSplit {
      NativeDocumentSplit(
        document: document, preferences: preferences, editing: editing,
        html: styled ? parsed.html : "", syntax: styled ? parsed.syntax : nil,
        syntaxRevision: styled ? document.revision : nil,
        revision: styled ? document.revision : nil,
        mode: .split, previewError: .constant(nil), editorSelection: .constant(nil),
        scrolling: scrolling, sourceViewportStorage: .constant(saved))
    }
    func window(host: NSViewController) -> NSWindow {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
      window.animationBehavior = .none
      window.isReleasedWhenClosed = false
      window.appearance = appearance
      window.contentViewController = host
      window.setContentSize(NSSize(width: 1000, height: 600))
      window.orderFront(nil)
      return window
    }
    func editor(in view: NSView) -> MarkdownTextView? {
      if let source = view as? MarkdownTextView { return source }
      return view.subviews.lazy.compactMap { editor(in: $0) }.first
    }
    let originalDocument = MarkdownDocument(contents: TextFileContents(text: source))
    let originalScrolling = DocumentScrollCoordinator()
    let originalEditing = EditorCommandController()
    let originalHost = NSHostingController(
      rootView: root(
        document: originalDocument,
        scrolling: originalScrolling, editing: originalEditing, saved: nil, styled: true))
    let originalWindow = window(host: originalHost)
    defer { originalWindow.close() }
    try await waitFor("baseline source layout") {
      guard let view = editor(in: originalHost.view) else { return false }
      return view.bounds.width > 300 && view.visibleRect.height > 400
    }
    let original = try #require(editor(in: originalHost.view))
    original.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
    try await waitFor { originalScrolling.captureSource()?.offset ?? 0 > 0 }
    let saved = try #require(originalScrolling.captureSource())
    let savedData = try JSONEncoder().encode(saved)
    let restoredDocument = MarkdownDocument()
    let restoredScrolling = DocumentScrollCoordinator()
    let restoredEditing = EditorCommandController()
    let restoredHost = NSHostingController(
      rootView: root(
        document: restoredDocument,
        scrolling: restoredScrolling, editing: restoredEditing, saved: savedData, styled: false))
    let restoredWindow = window(host: restoredHost)
    defer { restoredWindow.close() }
    try await waitFor("empty source created") { editor(in: restoredHost.view) != nil }
    try await restoredDocument.apply(snapshot: TextFileContents(text: source), previous: nil)
    await Task.yield()
    restoredHost.rootView = root(
      document: restoredDocument, scrolling: restoredScrolling,
      editing: restoredEditing, saved: savedData, styled: true)
    let restored = try #require(editor(in: restoredHost.view))
    restoredWindow.makeFirstResponder(restored)
    try await waitFor("restored styled reading line") {
      guard let actual = restoredScrolling.captureSource() else { return false }
      return actual.offset == saved.offset && abs(actual.fraction - saved.fraction) < 0.1
    }
    func pixels(in editor: NSTextView, name: String) throws -> Int {
      editor.layoutSubtreeIfNeeded()
      editor.displayIfNeeded()
      let rect = editor.visibleRect
      let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: rect))
      editor.cacheDisplay(in: rect, to: bitmap)
      if let data = bitmap.representation(using: .png, properties: [:]) {
        try data.write(
          to: URL(filePath: "/private/tmp/snowfolio-\(dark ? "dark" : "light")-\(name).png"))
      }
      let background = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
      var ink = 0
      for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
          guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            continue
          }
          let distance =
            abs(color.redComponent - background.redComponent)
            + abs(color.greenComponent - background.greenComponent)
            + abs(color.blueComponent - background.blueComponent)
          if color.alphaComponent > 0.8 && distance > 0.25 { ink += 1 }
        }
      }
      return ink
    }
    let baseline = try pixels(in: original, name: "paged-source")
    let reopened = try pixels(in: restored, name: "restored-source")
    print("Source painting ink samples", dark, baseline, reopened)
    #expect(baseline > 1000)
    #expect(Double(reopened) >= Double(baseline) * 0.9)
    #expect(restored.string == source)
    #expect(restored.textLayoutManager != nil)
    #expect(restoredDocument.revision == 1)
    #expect(restored.selectedRange().location == 0)
  }

  @Test("Source position and fractional visual line restore without touching selection or undo")
  func sourceRestoration() async throws {
    let source = (1...160).map { "Paragraph \($0) 中文 😀\n\n" }.joined()
    let original = try Fixture(source: source)
    defer { original.close() }
    original.scrolling.sourceEditedOrNavigated()
    let offset = (source as NSString).range(of: "Paragraph 40").location
    let layout = try #require(original.editor.textLayoutManager)
    let content = try #require(layout.textContentManager)
    let location = try #require(content.location(content.documentRange.location, offsetBy: offset))
    var lineRect = NSRect.zero
    layout.enumerateTextSegments(in: NSTextRange(location: location), type: .standard, options: [])
    { _, rect, _, _ in
      lineRect = rect.offsetBy(
        dx: original.editor.textContainerOrigin.x, dy: original.editor.textContainerOrigin.y)
      return false
    }
    #expect(lineRect.height > 0)
    let requestedY = lineRect.minY + lineRect.height * 0.25
    original.scroll.contentView.scroll(to: NSPoint(x: 0, y: requestedY))
    let saved = try #require(original.scrolling.captureSource())
    #expect(saved.offset > 0)
    #expect(saved.fraction > 0)
    let data = try JSONEncoder().encode(saved)
    let restored = try Fixture(source: source, sourceData: data)
    defer { restored.close() }
    restored.editor.setSelectedRange(NSRange(location: 2, length: 3))
    do {
      try await waitFor("source restored logical line") {
        guard let actual = restored.scrolling.captureSource() else { return false }
        return actual.offset == saved.offset && abs(actual.fraction - saved.fraction) < 0.1
      }
    } catch {
      print(
        "restore-debug", saved, restored.scrolling.captureSource() as Any,
        original.scroll.contentView.bounds, restored.scroll.contentView.bounds)
      throw error
    }
    // Initial native focus can reveal the caret at the top after restoration.
    restored.scroll.contentView.scroll(to: .zero)
    try await waitFor("reading anchor survives native focus adjustment") {
      restored.scrolling.captureSource()?.offset == saved.offset
    }
    #expect(restored.editor.selectedRange() == NSRange(location: 2, length: 3))
    #expect(restored.editor.string == source)
    #expect(restored.document.revision == 0)
    #expect(!restored.undo.canUndo)
    let restoredLayout = try #require(restored.editor.textLayoutManager)
    let viewport = try #require(restoredLayout.textViewportLayoutController.viewportRange)
    let restoredContent = try #require(restoredLayout.textContentManager)
    let viewportStart = restoredContent.offset(
      from: restoredContent.documentRange.location, to: viewport.location)
    let viewportEnd = restoredContent.offset(
      from: restoredContent.documentRange.location, to: viewport.endLocation)
    #expect(viewportStart <= saved.offset && viewportEnd > saved.offset)
    // A saved coordinate from a longer file is clamped after external shortening.
    let shortened = try Fixture(source: "Short 😀", sourceData: data)
    defer { shortened.close() }
    shortened.scrolling.layoutChanged()
    try await waitFor { shortened.scrolling.captureSource()?.atTop == true }
    #expect(shortened.editor.string == "Short 😀")
    #expect(shortened.scroll.contentView.bounds.minY == 0)
    #expect(
      shortened.editor.selectedRange().location <= (shortened.editor.string as NSString).length)
  }

  @Test("Independent preview position survives reopening and a local-resource context reload")
  func previewRestoration() async throws {
    let source = (1...150).map { "## Section \($0)\n\n> [!NOTE]\n> 内容 😀\n\n- One\n  - Two\n\n" }
      .joined()
    let saved = MarkdownScrollPosition(line: 350.5)
    let fixture = try Fixture(source: source, previewData: JSONEncoder().encode(saved))
    defer { fixture.close() }
    try await fixture.loadPreview()
    try await waitFor { fixture.previewCoordinator.isReadyForScrolling(revision: 0) }
    try await waitFor {
      try await evaluate("return String(window.scrollY > 500);", in: fixture.preview) == "true"
    }
    #expect(fixture.scroll.contentView.bounds.minY == 0)
    let before =
      Double(try await evaluate("return String(window.scrollY);", in: fixture.preview)) ?? 0
    try await fixture.loadPreview(directory: URL(filePath: "/private/tmp"))
    try await waitFor { fixture.previewCoordinator.isReadyForScrolling(revision: 0) }
    try await waitFor {
      abs(
        (Double(try await evaluate("return String(window.scrollY);", in: fixture.preview)) ?? 0)
          - before) < 3
    }
    #expect(fixture.document.revision == 0)
    #expect(!fixture.undo.canUndo)
  }

  @Test("Invalid scene data cannot block linking, and exact bottom positions survive layout")
  func invalidStorageAndEdges() async throws {
    let source = (1...150).map { "Paragraph \($0)\n\n" }.joined()
    let fixture = try Fixture(source: source, sourceData: Data("damaged".utf8), linked: true)
    defer { fixture.close() }
    try await fixture.loadPreview()
    try await waitFor { fixture.previewCoordinator.isReadyForScrolling(revision: 0) }
    try await waitFor("invalid initial top") {
      try await evaluate(
        "return String(window.__snowfolioScroll.position().atTop);", in: fixture.preview) == "true"
    }
    NotificationCenter.default.post(
      name: NSScrollView.willStartLiveScrollNotification, object: fixture.scroll)
    fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 800))
    NotificationCenter.default.post(
      name: NSScrollView.didEndLiveScrollNotification, object: fixture.scroll)
    try await waitFor("link despite damaged storage") {
      try await evaluate("return String(window.scrollY > 300);", in: fixture.preview) == "true"
    }
    await withCheckedContinuation { continuation in
      fixture.previewCoordinator.moveForScrolling(
        to: MarkdownScrollPosition(line: 300, atBottom: true)
      ) { continuation.resume() }
    }
    try await waitFor("programmatic preview bottom") {
      try await evaluate(
        "return String(window.__snowfolioScroll.position().atBottom);", in: fixture.preview)
        == "true"
    }
    try await waitFor("settled preview bottom") {
      guard let data = fixture.previewData else { return false }
      return try JSONDecoder().decode(MarkdownScrollPosition.self, from: data).atBottom
    }
    // Wait for the top scroll event to be acknowledged before moving back down;
    // WebKit correctly coalesces immediate top/bottom changes into one event.
    _ = try await evaluate("window.scrollTo(0, 0); return 'top';", in: fixture.preview)
    try await waitFor("linked source top") { fixture.scrolling.captureSource()?.atTop == true }
    try await waitFor("settled preview top") {
      guard let data = fixture.previewData else { return false }
      return try JSONDecoder().decode(MarkdownScrollPosition.self, from: data).atTop
    }
    _ = try await evaluate(
      "window.scrollTo(0, document.documentElement.scrollHeight); return 'bottom';",
      in: fixture.preview)
    try await waitFor("linked source bottom") {
      fixture.scrolling.captureSource()?.atBottom == true
    }
    #expect(fixture.editor.string == source)
    #expect(!fixture.undo.canUndo)
  }

  @Test(
    "Native panes follow source blocks in both directions without changing source, selection or undo"
  )
  func linkedPanes() async throws {
    _ = NSApplication.shared
    let source = (1...200).map { "Paragraph \($0) 中文 😀\n\n" }.joined()
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let rendered = try await MarkdownProcessor().render(source)
    let scrolling = DocumentScrollCoordinator()
    var sourceData: Data?
    var previewData: Data?
    scrolling.configure(
      document: document, linked: true, mode: .split,
      sourceStorage: Binding(get: { sourceData }, set: { sourceData = $0 }),
      previewStorage: Binding(get: { previewData }, set: { previewData = $0 }))
    let editorCoordinator = NativeMarkdownEditor.Coordinator(document: document)
    let manager = UndoManager()
    editorCoordinator.undoManager = manager
    let scroll = NativeMarkdownEditor.makeScrollView(
      document: document, coordinator: editorCoordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let sourceWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: .titled, backing: .buffered, defer: false)
    sourceWindow.animationBehavior = .none
    sourceWindow.isReleasedWhenClosed = false
    sourceWindow.contentView = scroll
    sourceWindow.orderFront(nil)
    editor.setFrameSize(NSSize(width: 600, height: 8_000))
    editor.textContainer?.containerSize.width = 550
    editor.textLayoutManager?.ensureLayout(
      for: try #require(editor.textLayoutManager?.textContentManager?.documentRange))
    scrolling.attachSource(editor)
    let previewCoordinator = NativeMarkdownPreview.Coordinator()
    previewCoordinator.scrolling = scrolling
    scrolling.attachPreview(previewCoordinator)
    let preview = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 650, height: 400),
      configuration: NativeMarkdownPreview.configuration(
        handler: previewCoordinator.resources, scrollHandler: previewCoordinator))
    preview.navigationDelegate = previewCoordinator
    let previewWindow = NSWindow(
      contentRect: preview.frame, styleMask: .titled, backing: .buffered, defer: false)
    previewWindow.animationBehavior = .none
    previewWindow.isReleasedWhenClosed = false
    previewWindow.contentView = preview
    previewWindow.orderFront(nil)
    defer {
      scrolling.detachSource(editor)
      scrolling.detachPreview(previewCoordinator)
      preview.stopLoading()
      preview.navigationDelegate = nil
      previewCoordinator.resources.cancelAll()
      sourceWindow.close()
      previewWindow.close()
    }
    previewCoordinator.update(
      preview, html: rendered.html, directory: nil, remoteImages: false, revision: 0)
    try await waitFor { previewCoordinator.isReadyForScrolling(revision: 0) }
    editor.setSelectedRange(NSRange(location: 2, length: 3))
    NotificationCenter.default.post(
      name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    scroll.contentView.scroll(to: NSPoint(x: 0, y: 800))
    scroll.reflectScrolledClipView(scroll.contentView)
    NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    try await waitFor {
      try await evaluate("return String(window.scrollY > 300);", in: preview) == "true"
    }
    let sourceBefore = scroll.contentView.bounds.minY
    _ = try await evaluate("window.scrollTo(0, 2500); return 'moved';", in: preview)
    try await waitFor { abs(scroll.contentView.bounds.minY - sourceBefore) > 100 }
    #expect(editor.string == source)
    #expect(document.revision == 0)
    #expect(editor.selectedRange() == NSRange(location: 2, length: 3))
    #expect(!manager.canUndo)
    #expect(editor.textLayoutManager != nil)
    #expect(!preview.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    #expect(
      try await evaluate("return typeof window.__snowfolioScroll;", in: preview, world: .page)
        == "undefined")
    #expect(
      try await evaluate(
        "return typeof window.webkit?.messageHandlers?.snowfolioScroll;", in: preview, world: .page)
        == "undefined")
    scrolling.flush()
    #expect(sourceData != nil)
    #expect(previewData != nil)

    let styles = ReadingStyleRepository()
    for entry in ReadingStyleEntry.all {
      let style = DocumentStyle(presentation: try await styles.load(entry.id))
      previewCoordinator.update(
        preview, html: rendered.html, directory: nil, remoteImages: false, style: style, revision: 0
      )
      try await waitFor("style scroll context") {
        previewCoordinator.isReadyForScrolling(revision: 0)
      }
      NotificationCenter.default.post(
        name: NSScrollView.willStartLiveScrollNotification, object: scroll)
      scroll.contentView.scroll(to: NSPoint(x: 0, y: 800))
      scroll.reflectScrolledClipView(scroll.contentView)
      NotificationCenter.default.post(
        name: NSScrollView.didEndLiveScrollNotification, object: scroll)
      try await waitFor("source drives selected reading style") {
        try await evaluate("return String(window.scrollY>300 && window.scrollY<1800);", in: preview)
          == "true"
      }
      let before = scroll.contentView.bounds.minY
      _ = try await evaluate(
        "window.dispatchEvent(new Event('wheel')); window.scrollTo(0,2500); return 'moved';",
        in: preview)
      try await waitFor("selected reading style drives source") {
        abs(scroll.contentView.bounds.minY - before) > 100
      }
      #expect(editor.string == source && document.revision == 0)
      #expect(editor.selectedRange() == NSRange(location: 2, length: 3) && !manager.canUndo)
    }

    scrolling.configure(
      document: document, linked: false, mode: .split,
      sourceStorage: .constant(nil), previewStorage: .constant(nil))
    let unlinkedY = scroll.contentView.bounds.minY
    _ = try await evaluate("window.scrollTo(0, 1000); return 'moved';", in: preview)
    try await Task.sleep(for: .milliseconds(200))
    #expect(abs(scroll.contentView.bounds.minY - unlinkedY) < 1)

    scrolling.configure(
      document: document, linked: true, mode: .split,
      sourceStorage: .constant(nil), previewStorage: .constant(nil))
    document.acceptNativeEdit(source + "New unrendered text")
    let staleY = scroll.contentView.bounds.minY
    _ = try await evaluate("window.scrollTo(0, 3500); return 'moved';", in: preview)
    try await Task.sleep(for: .milliseconds(200))
    #expect(abs(scroll.contentView.bounds.minY - staleY) < 1)
  }
}
