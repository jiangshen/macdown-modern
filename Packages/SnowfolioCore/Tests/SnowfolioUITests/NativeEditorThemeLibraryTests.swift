import AppKit
import DocumentCore
import EditorCore
import SwiftUI
import Testing

@testable import SnowfolioUI

@Suite("Live editor theme choices", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorThemeLibraryTests {
  private enum Failure: Error { case timeout }

  private func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<160 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw Failure.timeout
  }

  @Test("All bundled and imported choices update the existing editor and preserve native history")
  func liveChoices() async throws {
    _ = NSApplication.shared
    let domain = "LiveThemeChoices." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defaults.set("automatic", forKey: "editorThemeSelection")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(domain)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: domain)
      try? FileManager.default.removeItem(at: root)
    }
    let repo = EditorThemeRepository(directory: root.appendingPathComponent("Library"))
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: [:], editorThemeRepository: repo)
    let source = "1. First\r\n2. Second\r\n\r\n- 中文 😀\r\n"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let commands = EditorCommandController()
    let undo = UndoManager()
    undo.groupsByEvent = false
    let host = NSHostingController(
      rootView: NativeDocumentSplit.EditorSurface(
        document: document, preferences: preferences, commands: commands,
        undoManager: undo, editorSelection: .constant(nil)))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.orderFront(nil)
    defer { window.close() }
    try await waitFor { commands.coordinator?.editor != nil }
    await preferences.editorThemes.loadIfNeeded()
    let editor = try #require(commands.coordinator?.editor)
    let font = try #require(editor.font)
    let paper = editor.backgroundColor
    let selected = NSRange(location: 3, length: 5)
    editor.setSelectedRange(selected)
    for choice in EditorThemeEntry.bundled {
      await preferences.editorThemes.select(choice.id)
      let theme = try #require(preferences.editorThemes.theme)
      let expected = NativeEditorTheme(theme, font: font, zoom: 1)
      let desiredFont = expected.baseAttributes[.font] as? NSFont
      try await waitFor {
        editor.font == desiredFont && editor.backgroundColor == (expected.backgroundColor ?? paper)
      }
      #expect(commands.coordinator?.editor === editor)
      #expect(editor.selectedRange() == selected)
      #expect(editor.string.utf8.elementsEqual(source.utf8) && document.revision == 0)
      #expect(!undo.canUndo && !undo.canRedo)
    }
    window.makeFirstResponder(editor)
    commands.perform(.bold)
    let modified = document.text
    let selection = editor.selectedRange()
    let revision = document.revision
    #expect(modified != source && undo.canUndo)
    let custom = root.appendingPathComponent("Glacier.style")
    let bytes = Data("editor\nforeground: 112233\nbackground: e0efff\nfont-size: 24px\n".utf8)
    try bytes.write(to: custom)
    let inspected = try await preferences.editorThemes.inspect(custom)
    try await preferences.editorThemes.importTheme(inspected)
    try await waitFor { editor.font?.pointSize == 24 }
    #expect(editor.string == modified && editor.selectedRange() == selection)
    #expect(document.revision == revision && undo.canUndo && !undo.canRedo)
    await preferences.editorThemes.select("automatic")
    try await waitFor { editor.font == font && editor.backgroundColor == paper }
    #expect(editor.selectedRange() == selection && document.revision == revision)
    undo.undo()
    #expect(document.text.utf8.elementsEqual(source.utf8) && editor.string == source)
    undo.redo()
    #expect(document.text == modified && editor.string == modified)
    #expect(try Data(contentsOf: custom) == bytes)
  }
}
