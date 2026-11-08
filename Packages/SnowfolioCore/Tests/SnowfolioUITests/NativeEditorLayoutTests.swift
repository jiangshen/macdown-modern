import AppKit
import DocumentCore
import EditorCore
import SwiftUI
import Testing

@testable import SnowfolioUI

@Suite("Native source column layout", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorLayoutTests {
  @Test("Legacy margins and width migrate; fresh profiles retain Snowfolio's existing spacing")
  func preferences() throws {
    let domain = "EditorLayoutTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(fresh.editorLayout == .init())
    defaults.removePersistentDomain(forName: domain)
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: [
        "editorHorizontalInset": 15.0, "editorVerticalInset": 30.0,
        "editorWidthLimited": true, "editorMaximumWidth": 900.0,
      ])
    #expect(
      preferences.editorLayout
        == .init(horizontalInset: 15, verticalInset: 30, widthLimited: true, maximumWidth: 900))
    preferences.editorLayout.widthLimited = false
    preferences.editorLayout.horizontalInset = 8
    preferences.editorLayout.maximumWidth = 700
    let restored = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorWidthLimited": true])
    #expect(restored.editorLayout == preferences.editorLayout)
    #expect(SettingsCatalog.search("side margins").map(\.id) == ["editorHorizontalInset"])
    #expect(SettingsCatalog.search("maximum column").map(\.id) == ["editorMaximumWidth"])
  }

  private struct Fixture: View {
    let document: MarkdownDocument
    let preferences: AppPreferences
    let undo: UndoManager
    let commands: EditorCommandController
    var body: some View {
      NativeMarkdownEditor(
        document: document, layout: preferences.editorLayout,
        commands: commands, hostUndoManager: undo)
    }
  }

  @Test(
    "Resizing and changing margins retains native source, selection and undo; composition defers geometry"
  )
  func nativeGeometry() async throws {
    _ = NSApplication.shared
    let domain = "NativeEditorLayoutTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.editorLayout = .init(
      horizontalInset: 20, verticalInset: 30, widthLimited: true, maximumWidth: 600)
    let source =
      "# 中文 👩‍💻\n\n"
      + String(repeating: "A long writing paragraph with Unicode 中文 and emoji 👩‍💻. ", count: 30)
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let undo = UndoManager()
    undo.groupsByEvent = false
    let commands = EditorCommandController()
    let host = NSHostingController(
      rootView: Fixture(
        document: document, preferences: preferences, undo: undo, commands: commands))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1000, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    func find(_ view: NSView) -> MarkdownTextView? {
      if let editor = view as? MarkdownTextView { return editor }
      return view.subviews.lazy.compactMap(find).first
    }
    try await waitFor(
      "initial column",
      diagnostic: {
        guard let editor = find(host.view) else {
          return "no native editor; host=\(host.view.frame)"
        }
        return
          "frame=\(editor.frame), bounds=\(editor.bounds), inset=\(editor.textContainerInset), container=\(String(describing: editor.textContainer?.containerSize)), preferences=\(String(describing: editor.layoutPreferences))"
      },
      { find(host.view)?.textContainer?.containerSize.width == 600 }
    )
    let editor = try #require(find(host.view))
    #expect(editor.textLayoutManager != nil && editor.undoManager === undo)
    #expect(abs(editor.textContainerOrigin.x + 300 - editor.bounds.midX) < 1)
    #expect(editor.textContainerInset.height == 30)
    window.makeFirstResponder(editor)
    editor.setSelectedRange((source as NSString).range(of: "中文"))
    commands.perform(.bold)
    let changed = document.text
    let revision = document.revision
    let selection = editor.selectedRange()
    for width in [480.0, 1200, 720] {
      window.setContentSize(NSSize(width: width, height: 600))
      try await waitFor("resize \(width)") {
        let expected = min(600, editor.bounds.width - 40)
        return abs(editor.bounds.width - width) < 20
          && abs(editor.textContainer!.containerSize.width - expected) < 1
      }
      #expect(editor.textContainer!.containerSize.width <= 600)
      #expect(
        abs(
          editor.textContainerOrigin.x + editor.textContainer!.containerSize.width / 2
            - editor.bounds.midX) < 1)
    }
    preferences.editorLayout.widthLimited = false
    preferences.editorLayout.horizontalInset = 9
    preferences.editorLayout.verticalInset = 11
    try await waitFor("changed margins") {
      editor.textContainerInset == NSSize(width: 9, height: 11)
    }
    #expect(document.text == changed && document.revision == revision)
    #expect(editor.selectedRange() == selection && find(host.view) === editor)
    undo.undo()
    #expect(document.text == source)
    undo.redo()
    #expect(document.text == changed)
    editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    editor.setMarkedText(
      "拼", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    let marked = editor.string
    let priorInset = editor.textContainerInset
    preferences.editorLayout = .init(
      horizontalInset: 5, verticalInset: 7, widthLimited: true, maximumWidth: 400)
    try await waitFor("pending composition layout") {
      editor.layoutPreferences == preferences.editorLayout
    }
    host.view.layoutSubtreeIfNeeded()
    #expect(editor.textContainerInset == priorInset && editor.string == marked)
    editor.unmarkText()
    try await waitFor("committed composition layout") {
      editor.textContainerInset.height == 7 && editor.textContainer!.containerSize.width == 400
    }
    #expect(!editor.hasMarkedText() && editor.string == marked)
  }

  @Test(
    "The complete workspace retains its reading paragraph through column reflow",
    arguments: [false, true])
  func readingAnchor(linked: Bool) async throws {
    _ = NSApplication.shared
    let domain = "ColumnReadingAnchor." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.synchronizedScrolling = linked
    let source = (1...160).map {
      "Paragraph \($0): " + String(repeating: "A reading line 中文 👩‍💻 with wrapping text. ", count: 8)
        + "\n\n"
    }.joined()
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let host = NSHostingController(
      rootView: DocumentWorkspace(document: document, preferences: preferences))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1200, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    func find(_ view: NSView) -> MarkdownTextView? {
      if let editor = view as? MarkdownTextView { return editor }
      return view.subviews.lazy.compactMap(find).first
    }
    try await waitFor("workspace source") { find(host.view)?.font?.pointSize == 14 }
    let editor = try #require(find(host.view))
    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: 2, length: 5))
    for _ in 0..<3 { editor.doCommand(by: #selector(NSResponder.scrollPageDown(_:))) }
    try await waitFor("source paging") { editor.visibleRect.minY > 500 }
    func paragraphOffset() -> Int {
      let offset = min(
        (editor.string as NSString).length - 1,
        editor.characterIndexForInsertion(
          at: NSPoint(x: editor.textContainerInset.width + 1, y: editor.visibleRect.minY + 1)))
      return (editor.string as NSString).lineRange(for: NSRange(location: offset, length: 0))
        .location
    }
    let anchor = paragraphOffset()
    let selected = editor.selectedRange()
    preferences.editorLayout = .init(
      horizontalInset: 10, verticalInset: 30, widthLimited: true, maximumWidth: 300)
    try await waitFor("narrow source column") { editor.textContainer?.containerSize.width == 300 }
    try await waitFor(
      "narrow column reading paragraph",
      diagnostic: { "before=\(anchor), now=\(paragraphOffset()), y=\(editor.visibleRect.minY)" },
      { paragraphOffset() == anchor })
    preferences.editorLayout.widthLimited = false
    preferences.editorLayout.horizontalInset = 5
    try await waitFor("full source width") { editor.textContainerInset.width == 5 }
    try await waitFor(
      "full column reading paragraph",
      diagnostic: { "before=\(anchor), now=\(paragraphOffset()), y=\(editor.visibleRect.minY)" },
      { paragraphOffset() == anchor })
    #expect(editor.selectedRange() == selected)
    #expect(document.text == source && document.revision == 0)
    #expect(find(host.view) === editor && editor.textLayoutManager != nil)
  }

  private func waitFor(_ stage: String, diagnostic: () -> String = { "" }, _ condition: () -> Bool)
    async throws
  {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    Issue.record("Native editor column layout did not settle: \(stage); \(diagnostic())")
    throw CocoaError(.coderReadCorrupt)
  }
}
