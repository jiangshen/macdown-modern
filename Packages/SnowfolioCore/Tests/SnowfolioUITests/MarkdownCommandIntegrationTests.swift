import AppKit
import DocumentCore
import EditorCore
import Testing

@testable import SnowfolioUI

@Suite("Native Markdown commands", .serialized)
@MainActor
struct MarkdownCommandIntegrationTests {
  private func editor(_ source: String) throws -> (
    MarkdownDocument, NativeMarkdownEditor.Coordinator, NSScrollView, NSTextView, UndoManager
  ) {
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let manager = UndoManager()
    manager.groupsByEvent = false
    coordinator.undoManager = manager
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    return (
      document, coordinator, scroll, try #require(scroll.documentView as? NSTextView), manager
    )
  }

  @Test("Formatting uses one native undo step and restores source and selection")
  func nativeFormatUndo() throws {
    let (document, coordinator, scroll, view, manager) = try editor("before 中文 after")
    defer { withExtendedLifetime(scroll) {} }
    let selection = NSRange(location: 7, length: 2)
    view.setSelectedRange(selection)
    #expect(coordinator.perform(.bold))
    #expect(view.string == "before **中文** after")
    #expect(document.text == view.string)
    #expect(view.selectedRange() == NSRange(location: 9, length: 2))
    #expect(manager.undoActionName == "Bold")
    manager.undo()
    #expect(document.text == "before 中文 after")
    #expect(view.selectedRange() == selection)
    #expect(!manager.canUndo)
    manager.redo()
    #expect(document.text == "before **中文** after")
    #expect(view.selectedRange() == NSRange(location: 9, length: 2))
    #expect(view.textLayoutManager != nil)
    manager.undo()
    #expect(view.selectedRange() == selection)
    manager.redo()
    #expect(view.selectedRange() == NSRange(location: 9, length: 2))
  }

  @Test("Return continues a checked task with one undoable native change")
  func listContinuation() throws {
    let (document, coordinator, scroll, view, manager) = try editor("- [x] 中文")
    defer { withExtendedLifetime(scroll) {} }
    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
    view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    #expect(document.text == "- [x] 中文\n- [ ] ")
    manager.undo()
    #expect(document.text == "- [x] 中文")
    #expect(!manager.canUndo)
    withExtendedLifetime(coordinator) {}
  }

  @Test("Pairing wraps selections, skips existing closers without dirtying text, and deletes pairs")
  func pairedInput() throws {
    let (document, coordinator, scroll, view, manager) = try editor("")
    defer { withExtendedLifetime(scroll) {} }
    coordinator.behavior.pairDelimiters = true
    view.insertText("(", replacementRange: NSRange(location: 0, length: 0))
    #expect(document.text == "()")
    #expect(view.selectedRange() == NSRange(location: 1, length: 0))
    view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    #expect(document.text == "")
    manager.undo()
    #expect(document.text == "()")
    let revision = document.revision
    view.setSelectedRange(NSRange(location: 1, length: 0))
    view.insertText(")", replacementRange: view.selectedRange())
    #expect(document.text == "()")
    #expect(document.revision == revision)
    #expect(view.selectedRange() == NSRange(location: 2, length: 0))
  }

  @Test("Marked text is never reformatted or paired, including its first ASCII character")
  func composition() throws {
    let (document, coordinator, scroll, view, _) = try editor("")
    defer { withExtendedLifetime(scroll) {} }
    coordinator.behavior.pairDelimiters = true
    view.setMarkedText(
      "(", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 0, length: 0))
    #expect(view.string == "(")
    #expect(view.hasMarkedText())
    #expect(!coordinator.perform(.bold))
    #expect(view.string == "(")
    view.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: view.markedRange())
    #expect(view.string == "にほん")
    #expect(view.hasMarkedText())
    view.unmarkText()
    view.setSelectedRange(NSRange(location: 0, length: 3))
    #expect(coordinator.perform(.bold))
    #expect(document.text == "**にほん**")
  }

  @Test("Paste and multi-character insertion bypass paired-character assistance")
  func paste() throws {
    let (document, coordinator, scroll, view, manager) = try editor("")
    defer { withExtendedLifetime(scroll) {} }
    coordinator.behavior.pairDelimiters = true
    manager.beginUndoGrouping()
    view.insertText("(literal paste)\n[raw]", replacementRange: NSRange(location: 0, length: 0))
    manager.endUndoGrouping()
    #expect(document.text == "(literal paste)\n[raw]")
    manager.undo()
    #expect(document.text == "")
  }
  @Test(
    "Applying an existing heading level is selection-only and does not create a dirty undo step")
  func unchangedFormatting() throws {
    let (document, coordinator, scroll, view, manager) = try editor("## Heading")
    defer { withExtendedLifetime(scroll) {} }
    view.setSelectedRange(NSRange(location: 4, length: 3))
    #expect(coordinator.perform(.heading(2)))
    #expect(document.text == "## Heading")
    #expect(document.revision == 0)
    #expect(!manager.canUndo)
  }

  @Test("Formatting command availability follows native focus and marked-text state")
  func commandFocus() throws {
    _ = NSApplication.shared
    let (document, coordinator, scroll, view, _) = try editor("word")
    let controller = EditorCommandController()
    controller.coordinator = coordinator
    coordinator.commands = controller
    let native = try #require(view as? MarkdownTextView)
    native.commandController = controller
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
      styleMask: .titled, backing: .buffered, defer: false)
    window.contentView = scroll
    #expect(window.makeFirstResponder(view))
    #expect(controller.canPerform)
    view.setMarkedText(
      "に", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: 0, length: 4))
    #expect(controller.isComposing)
    #expect(!controller.canPerform)
    view.unmarkText()
    #expect(!controller.isComposing)
    #expect(controller.canPerform)
    #expect(window.makeFirstResponder(nil))
    #expect(!controller.canPerform)
    let before = document.text
    controller.perform(.bold)
    #expect(document.text == before)
  }

  @Test("Changing split modes retains the editor and its native undo connection")
  func modeLifetime() async throws {
    _ = NSApplication.shared
    let domain = "SplitLifetimeTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let document = MarkdownDocument(contents: TextFileContents(text: "word"))
    let commands = EditorCommandController()
    let manager = UndoManager()
    manager.groupsByEvent = false
    let editor = NativeDocumentSplit.EditorSurface(
      document: document, preferences: preferences,
      commands: commands, undoManager: manager, editorSelection: .constant(nil))
    let preview = NativeDocumentSplit.PreviewSurface(
      html: "<p>word</p>", directory: nil,
      remoteImages: false, error: .constant(nil))
    let controller = NativeDocumentSplit.Controller(editor: editor, preview: preview, mode: .split)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
      styleMask: .titled, backing: .buffered, defer: false)
    window.contentViewController = controller
    window.orderFront(nil)
    defer {
      window.orderOut(nil)
      window.contentViewController = nil
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while commands.coordinator?.editor == nil && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    let coordinator = try #require(commands.coordinator)
    let view = try #require(coordinator.editor)
    view.setSelectedRange(NSRange(location: 0, length: 4))
    #expect(coordinator.perform(.bold))
    controller.view.layoutSubtreeIfNeeded()
    controller.splitView.setPosition(310, ofDividerAt: 0)
    controller.view.layoutSubtreeIfNeeded()
    let previousWidth = controller.editorHost.view.frame.width
    controller.setMode(.preview, editing: commands)
    controller.setMode(.editor, editing: commands)
    controller.setMode(.split, editing: commands)
    controller.view.layoutSubtreeIfNeeded()
    #expect(abs(controller.editorHost.view.frame.width - previousWidth) < 1)
    preferences.editorFontSize = 19
    controller.editorHost.rootView = editor
    let updateDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while view.font?.pointSize != 19 && ContinuousClock.now < updateDeadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(view.font?.pointSize == 19)
    #expect(commands.coordinator === coordinator)
    #expect(commands.coordinator?.editor === view)
    manager.undo()
    #expect(document.text == "word")
    #expect(view.selectedRange() == NSRange(location: 0, length: 4))
    manager.redo()
    #expect(document.text == "**word**")
    #expect(view.selectedRange() == NSRange(location: 2, length: 4))
  }

  @Test("Pasting a single delimiter replaces the selection without wrapping it")
  func singleCharacterPaste() throws {
    let (document, coordinator, scroll, view, manager) = try editor("selected")
    defer { withExtendedLifetime(scroll) {} }
    coordinator.behavior.pairDelimiters = true
    view.setSelectedRange(NSRange(location: 0, length: 8))
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("(", forType: .string)
    manager.beginUndoGrouping()
    #expect(view.readSelection(from: board, type: .string))
    manager.endUndoGrouping()
    #expect(document.text == "(")
    manager.undo()
    #expect(document.text == "selected")
  }

}
