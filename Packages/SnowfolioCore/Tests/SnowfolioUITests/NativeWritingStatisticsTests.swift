import AppKit
import DocumentCore
import RenderingCore
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native writing statistics", .serialized, NativeUIExclusive())
@MainActor
struct NativeWritingStatisticsTests {
  enum TestError: Error { case timeout }

  private func waitFor(_ condition: () async throws -> Bool) async throws {
    for _ in 0..<200 {
      if try await condition() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw TestError.timeout
  }

  @Test("Committed DOM snapshots retain styled boundaries, code policy and exact text")
  func domContract() async throws {
    _ = NSApplication.shared
    let html =
      "<p>hel<em>lo</em> &amp; e\u{301} 🧊</p>"
      + "<code><span>two words</span> three</code><code>!!!</code>"
      + "<pre><code>block words\n</code></pre>"
      + "<style>.unused{color:red}</style><script>neverExecuted=true</script><!-- ignored -->"
    let fixture = PreviewFixture()
    defer { fixture.close() }
    fixture.update(html, revision: 1)
    try await waitFor { fixture.statistics.revision == 1 }
    let json = try #require(
      try await fixture.view.callAsyncJavaScript(
        PreviewWritingStatistics.capture, arguments: [:], in: nil, contentWorld: .defaultClient)
        as? String)
    let runs = try JSONDecoder().decode([PreviewTextRun].self, from: Data(json.utf8))
    #expect(
      runs == [
        .init(text: "hel"), .init(text: "lo"), .init(text: " & e\u{301} 🧊"),
        .init(text: "two words", wordGroup: 1), .init(text: " three", wordGroup: 1),
        .init(text: "!!!", wordGroup: 2), .init(text: "block words\n", wordGroup: -1),
      ])
    #expect(
      fixture.statistics.value == .init(words: 4, characters: 42, charactersWithoutSpaces: 36))
    #expect(!fixture.view.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    let scriptState = try await fixture.view.callAsyncJavaScript(
      "return typeof globalThis.neverExecuted;", arguments: [:], in: nil, contentWorld: .page)
    #expect(scriptState as? String == "undefined")
  }

  @Test("Coalesced revisions, disabling and re-enabling never publish stale counts")
  func revisionOwnership() async throws {
    _ = NSApplication.shared
    let fixture = PreviewFixture()
    defer { fixture.close() }
    fixture.update("<p>first value</p>", revision: 1)
    try await waitFor { fixture.statistics.revision == 1 }
    fixture.update("<p>" + String(repeating: "obsolete ", count: 30_000) + "</p>", revision: 2)
    fixture.update("<p>latest</p>", revision: 3)
    try await waitFor { fixture.statistics.revision == 3 }
    #expect(fixture.statistics.value?.words == 1)
    fixture.update("<p>latest</p>", revision: 4)
    try await waitFor { fixture.statistics.revision == 4 }
    fixture.update("<p>newly enabled value</p>", revision: 5, enabled: false)
    #expect(fixture.statistics.value == nil)
    fixture.update("<p>newly enabled value</p>", revision: 5)
    try await waitFor { fixture.statistics.revision == 5 }
    #expect(fixture.statistics.value?.words == 3)
    fixture.coordinator.webViewWebContentProcessDidTerminate(fixture.view)
    #expect(fixture.statistics.value == nil && fixture.statistics.revision == nil)
  }

  @Test("Math, footnotes and isolated diagram labels count their committed text without styles")
  func generatedDOM() async throws {
    _ = NSApplication.shared
    let fixture = PreviewFixture()
    defer { fixture.close() }
    fixture.update(
      "<p>note<sup><a>1</a></sup></p><section><p>footnote text</p></section>"
        + "<span class='katex'><span class='katex-mathml'><math><mi>x</mi></math></span>"
        + "<span class='katex-html' aria-hidden='true'><span>x</span></span></span>"
        + "<div class='md-diagram' data-diagram-key='owned'><template data-snowfolio-diagram>"
        + "<style>.label{fill:red}</style><svg><text>Diagram label</text></svg>"
        + "</template></div>", revision: 1)
    try await waitFor { fixture.statistics.revision == 1 }
    // Like the old DOM counter, math's accessibility and visual nodes both count.
    // Modern diagrams use a shadow root: include its text and exclude its stylesheet.
    #expect(fixture.statistics.value?.words == 8)
    let result = try await fixture.view.callAsyncJavaScript(
      PreviewWritingStatistics.capture, arguments: [:], in: nil, contentWorld: .defaultClient)
    let json = try #require(result as? String)
    #expect(json.contains("Diagram label"))
    #expect(!json.contains("fill:red"))
  }

  @Test("Manual source-only counts follow Render and preserve selection, Undo and encoded bytes")
  func manualWorkspace() async throws {
    _ = NSApplication.shared
    let domain = "WritingStatisticsWorkspace." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.showWritingStatistics = true
    preferences.manualRendering = true
    preferences.syntaxHighlighting = false
    let source = "first word\r\n"
    let bytes = Data([0xff, 0xfe]) + (try #require(source.data(using: .utf16LittleEndian)))
    let document = MarkdownDocument(contents: try TextFileContents(decoding: bytes))
    let state = DocumentWorkspaceState()
    state.mode = .editor
    let commands = NativeWorkspaceCommandContext()
    let undo = UndoManager()
    let host = NSHostingController(
      rootView: NativeDocumentWorkspace(
        document: document, preferences: preferences, state: state, hostUndoManager: undo,
        commandContext: commands, openFile: { _ in }))
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 1000, height: 650),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.contentViewController = host
    window.orderFront(nil)
    defer { window.close() }
    // SwiftUI accessibility identifiers are not NSView identifiers on every OS.
    func popup(in view: NSView) -> NSPopUpButton? {
      if let control = view as? NSPopUpButton,
        control.accessibilityIdentifier() == "writingStatistics"
      {
        return control
      }
      return view.subviews.lazy.compactMap { popup(in: $0) }.first
    }
    try await waitFor {
      popup(in: host.view)?.isEnabled == true && popup(in: host.view)?.title == "2 words"
        && commands.editor?.coordinator?.editor != nil
    }
    let control = try #require(popup(in: host.view))
    #expect(control.title == "2 words")
    let editor = try #require(commands.editor?.coordinator?.editor)
    window.makeFirstResponder(editor)
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    editor.insertText("added", replacementRange: editor.selectedRange())
    editor.breakUndoCoalescing()
    let selection = editor.selectedRange()
    #expect(undo.canUndo)
    try await Task.sleep(for: .milliseconds(450))
    #expect(control.title == "2 words")
    #expect(!document.lastRenderedHTML.contains("added"))
    preferences.manualRendering = false
    try await waitFor { control.title == "3 words" }
    #expect(editor.selectedRange() == selection)
    #expect(undo.canUndo)
    control.selectItem(at: WritingStatisticsMode.charactersWithoutSpaces.rawValue)
    _ = control.sendAction(control.action, to: control.target)
    #expect(preferences.writingStatisticsMode == .charactersWithoutSpaces)
    #expect(editor.selectedRange() == selection)
    undo.undo()
    try await waitFor { document.text == source && control.title == "9 characters without spaces" }
    #expect(try document.fileContents.encoded() == bytes)
    preferences.showWritingStatistics = false
    try await waitFor { popup(in: host.view) == nil }
    #expect(document.text == source && undo.canRedo)
  }

  @MainActor private final class PreviewFixture {
    let coordinator = NativeMarkdownPreview.Coordinator()
    let statistics = DocumentWritingStatistics()
    let view: WKWebView
    let window: NSWindow

    init() {
      view = WKWebView(
        frame: .init(x: 0, y: 0, width: 600, height: 450),
        configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
      view.navigationDelegate = coordinator
      window = NSWindow(
        contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.animationBehavior = .none
      window.contentView = view
      window.orderFront(nil)
    }

    func update(_ html: String, revision: UInt64, enabled: Bool = true) {
      coordinator.update(
        view, html: html, directory: nil, remoteImages: false,
        revision: revision, statistics: enabled ? statistics : nil)
    }

    func close() {
      NativeMarkdownPreview.dismantleNSView(view, coordinator: coordinator)
      window.close()
    }
  }
}
