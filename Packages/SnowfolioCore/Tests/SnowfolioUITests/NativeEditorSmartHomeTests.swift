import AppKit
import DocumentCore
import EditorCore
import Testing

@testable import SnowfolioUI

@Suite("Native smart line start", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorSmartHomeTests {
  @Test("Legacy Smart Home imports explicit choices and persists through reopen")
  func preferences() throws {
    let domain = "SmartHomeTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(!fresh.smartHome && !fresh.editorBehavior.smartHome)
    defaults.removePersistentDomain(forName: domain)
    let imported = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorSmartHome": true])
    #expect(imported.smartHome && imported.editorBehavior.smartHome)
    imported.smartHome = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorSmartHome": true])
    #expect(!reopened.smartHome && !reopened.editorBehavior.smartHome)
    #expect(SettingsCatalog.search("smart line start").map(\.id) == ["editorSmartHome"])
  }

  @MainActor
  private struct Fixture {
    let document: MarkdownDocument
    let coordinator: NativeMarkdownEditor.Coordinator
    let editor: MarkdownTextView
    let window: NSWindow
    let undo: UndoManager

    func close() {
      coordinator.highlighter.detach()
      editor.delegate = nil
      window.close()
    }
  }

  private func fixture(_ source: String, width: CGFloat = 400, font: NSFont) throws -> Fixture {
    _ = NSApplication.shared
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    coordinator.behavior.smartHome = true
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    editor.font = font
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.contentView = scroll
    window.orderFront(nil)
    window.makeFirstResponder(editor)
    scroll.layoutSubtreeIfNeeded()
    let manager = try #require(editor.textLayoutManager)
    let content = try #require(manager.textContentManager)
    manager.ensureLayout(for: content.documentRange)
    return Fixture(
      document: document, coordinator: coordinator, editor: editor, window: window, undo: undo)
  }

  @Test(
    "Two-step navigation preserves Unicode, CRLF and existing native undo",
    arguments: [false, true])
  func navigation(proportional: Bool) throws {
    let font = try #require(NSFont(name: proportional ? "Helvetica" : "Menlo-Regular", size: 28))
    let source = "前置 👩‍💻\r\n\t\u{00A0}  First 👩‍💻\r\nTail"
    let fixture = try fixture(source, font: font)
    defer { fixture.close() }
    let editor = fixture.editor
    editor.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
    fixture.undo.beginUndoGrouping()
    editor.insertText("x", replacementRange: editor.selectedRange())
    fixture.undo.endUndoGrouping()
    let changed = editor.string
    let revision = fixture.document.revision
    let word = (changed as NSString).range(of: "First")
    editor.setSelectedRange(NSRange(location: NSMaxRange(word), length: 0))
    editor.doCommand(by: #selector(NSResponder.moveToLeftEndOfLine(_:)))
    #expect(editor.selectedRange() == NSRange(location: word.location, length: 0))
    editor.doCommand(by: #selector(NSResponder.moveToLeftEndOfLine(_:)))
    let lineStart = LegacyLineLookup(changed).newlineBefore(word.location) + 1
    #expect(editor.selectedRange() == NSRange(location: lineStart, length: 0))
    #expect(editor.string == changed && fixture.document.text == changed)
    #expect(fixture.document.revision == revision && editor.textLayoutManager != nil)
    fixture.undo.undo()
    #expect(editor.string == source && fixture.document.text == source)
    fixture.undo.redo()
    #expect(editor.string == changed && fixture.document.text == changed)
  }

  @Test("Wrapped rows and disabled Smart Home retain native movement")
  func wrappedRows() throws {
    let source = "    " + String(repeating: "A long wrapped paragraph 中文. ", count: 30)
    let fixture = try fixture(
      source, width: 260, font: .monospacedSystemFont(ofSize: 18, weight: .regular))
    defer { fixture.close() }
    let editor = fixture.editor
    let caret = NSRange(location: 200, length: 0)
    fixture.coordinator.behavior.smartHome = false
    editor.setSelectedRange(caret)
    editor.doCommand(by: #selector(NSResponder.moveToLeftEndOfLine(_:)))
    let native = editor.selectedRange()
    #expect(native.location > 4 && native.location < caret.location)
    fixture.coordinator.behavior.smartHome = true
    editor.setSelectedRange(caret)
    editor.doCommand(by: #selector(NSResponder.moveToLeftEndOfLine(_:)))
    #expect(editor.selectedRange() == native)
    #expect(editor.string == source && fixture.document.revision == 0 && !fixture.undo.canUndo)
  }

  @Test("Composition and selection-extension commands remain native")
  func composition() throws {
    let fixture = try fixture("    中文", font: .monospacedSystemFont(ofSize: 14, weight: .regular))
    defer { fixture.close() }
    let editor = fixture.editor
    editor.setSelectedRange(NSRange(location: 6, length: 0))
    #expect(
      !fixture.coordinator.textView(
        editor, doCommandBy: #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:))))
    fixture.undo.beginUndoGrouping()
    defer { fixture.undo.endUndoGrouping() }
    editor.setMarkedText(
      "拼", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
    let marked = editor.string
    let selection = editor.selectedRange()
    #expect(editor.hasMarkedText())
    #expect(
      !fixture.coordinator.textView(
        editor, doCommandBy: #selector(NSResponder.moveToLeftEndOfLine(_:))))
    #expect(
      editor.string == marked && editor.selectedRange() == selection && editor.hasMarkedText())
    editor.unmarkText()
  }
}
