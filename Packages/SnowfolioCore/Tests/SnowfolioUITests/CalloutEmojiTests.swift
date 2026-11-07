import AppKit
import DocumentCore
import EmojiCore
import Foundation
import MarkdownCore
import Testing

@testable import SnowfolioUI

@Suite("Native callout emoji editing", .serialized)
@MainActor
struct CalloutEmojiTests {
  @Test("The bundled searchable emoji catalog includes complete multi-scalar choices")
  func catalog() async throws {
    let entries = try await EmojiCatalog.load()
    #expect(entries.count > 3000)
    #expect(Set(entries.map(\.glyph)).count == entries.count)
    #expect(entries.contains { $0.glyph == "🎯" && $0.name.contains("bullseye") })
    #expect(entries.contains { $0.glyph == "👩🏽‍💻" })
    #expect(entries.contains { $0.glyph == "🇯🇵" })
    #expect(entries.allSatisfy { !$0.name.isEmpty && !$0.group.isEmpty })
    let invalid = entries.filter { !CalloutMarker.isEmoji($0.glyph) }
    #expect(invalid.isEmpty)
    let displayed = try await EmojiDisplayCatalog.load()
    #expect(displayed.count > 3000)
    #expect(displayed.contains { $0.glyph == "👩🏽‍💻" })
    #expect(displayed.contains { $0.glyph == "🇯🇵" })
  }

  @Test("Preview icon changes use native undo without replacing source or selection")
  func nativeUndo() async throws {
    let source = "# 中文 👩‍💻\r\n> [!NOTE]  \r\n> Body\r\n"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let domain = "CalloutEmojiTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let manager = UndoManager()
    manager.groupsByEvent = false
    let commands = EditorCommandController()
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    coordinator.undoManager = manager
    coordinator.commands = commands
    commands.coordinator = coordinator
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? NSTextView)
    let selection = NSRange(location: (source as NSString).length - 4, length: 2)
    editor.setSelectedRange(selection)
    let callouts = CalloutEditorController()
    callouts.document = document
    callouts.editing = commands
    callouts.preferences = preferences
    let parsed = try await MarkdownProcessor().render(source)
    callouts.setTargets(parsed.nodes, revision: document.revision)
    #expect(callouts.apply(emoji: "🎯", line: 2, revision: document.revision))
    #expect(document.text == source.replacingOccurrences(of: "[!NOTE]", with: "[!NOTE] 🎯"))
    #expect(editor.textLayoutManager != nil)
    #expect(
      editor.selectedRange() == NSRange(location: selection.location + 3, length: selection.length))
    #expect(manager.undoActionName == "Change Callout Emoji")
    manager.undo()
    #expect(document.text.utf8.elementsEqual(source.utf8))
    #expect(editor.selectedRange() == selection)
    manager.redo()
    #expect(document.text.contains("[!NOTE] 🎯"))
    #expect(!callouts.apply(emoji: "💡", line: 2, revision: 0))
    // Even a current source line is not editable if it was not recognized in the parsed tree.
    callouts.setTargets([], revision: document.revision)
    #expect(!callouts.apply(emoji: "💡", line: 2, revision: document.revision))
  }
}
