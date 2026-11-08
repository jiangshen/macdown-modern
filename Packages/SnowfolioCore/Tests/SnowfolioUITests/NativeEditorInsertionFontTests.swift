import AppKit
import DocumentCore
import EditorCore
import Testing

@testable import SnowfolioUI

@Suite("Native theme insertion typography", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorInsertionFontTests {
  private func host(_ source: String, font: NSFont) throws -> (
    MarkdownDocument, NativeMarkdownEditor.Coordinator, MarkdownTextView, NSWindow
  ) {
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: .titled,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.contentView = scroll
    window.orderFront(nil)
    editor.font = font
    editor.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
    return (document, coordinator, editor, window)
  }

  private func caret(_ editor: MarkdownTextView) throws -> NSRect {
    editor.window?.contentView?.layoutSubtreeIfNeeded()
    let manager = try #require(editor.textLayoutManager)
    manager.textViewportLayoutController.layoutViewport()
    manager.ensureLayout(for: try #require(manager.textContentManager).documentRange)
    return editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
  }

  @Test(
    "Themed empty and terminal-line carets match a native editor using that font",
    arguments: ["", "Tail", "Tail\n", "Tail\r\n"])
  func nativeMetrics(_ source: String) throws {
    for zoom in [0.5, 1.0, 2.0] {
      let base = NSFont.monospacedSystemFont(ofSize: 14 * zoom, weight: .regular)
      for selector in ["editor", "editor-current-line"] {
        for family in [nil, "Helvetica"] as [String?] {
          let font =
            family.flatMap { NSFont(name: $0, size: 22 * zoom) }
            ?? .monospacedSystemFont(ofSize: 22 * zoom, weight: .regular)
          let (document, coordinator, editor, window) = try host(source, font: base)
          let (_, _, reference, referenceWindow) = try host(source, font: font)
          defer {
            window.close()
            referenceWindow.close()
          }
          let familyRule = family.map { "font-family: \($0)\n" } ?? ""
          coordinator.highlighter.update(
            syntax: nil, revision: nil, enabled: true, font: base, document: document,
            theme: try EditorTheme.parse("\(selector)\nfont-size: 22px\n\(familyRule)"),
            zoomScale: zoom)
          let actualFont = try #require(editor.font)
          let expectedPoints = CGFloat(22 * zoom)
          #expect(
            actualFont.pointSize == expectedPoints,
            "\(selector), \(source.debugDescription), zoom \(zoom)")
          #expect(actualFont.fontName == font.fontName)
          let actual = try caret(editor)
          let expected = try caret(reference)
          var facts = ""
          if actual.height <= 0 || abs(actual.height - expected.height) >= 0.1 {
            facts =
              " actual descriptor: \(actualFont.fontDescriptor.fontAttributes); reference descriptor: \(String(describing: reference.font?.fontDescriptor.fontAttributes)); actual typing: \(editor.typingAttributes); reference typing: \(reference.typingAttributes)"
          }
          #expect(
            actual.height > 0 && abs(actual.height - expected.height) < 0.1,
            "\(selector), \(source.debugDescription), \(family ?? "monospaced"), zoom \(zoom): \(actual.height) vs \(expected.height)\(facts)"
          )
          #expect(editor.string.utf8.elementsEqual(source.utf8) && document.text == source)
          #expect(document.revision == 0)
        }
      }
    }
  }

  @Test("Native preedit keeps a coherent writing palette until a theme change can apply safely")
  func compositionPalette() throws {
    let base = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let (document, coordinator, editor, window) = try host("Text", font: base)
    defer { window.close() }
    let first = try EditorTheme.parse(
      "editor\nforeground: ffffff\nbackground: 202020\nfont-size: 22px\n")
    let second = try EditorTheme.parse(
      "editor\nforeground: 112233\nbackground: ffffff\nfont-size: 26px\n")
    coordinator.highlighter.update(
      syntax: nil, revision: nil, enabled: true, font: base, document: document, theme: first)
    let oldColor = editor.textColor
    let oldPaper = editor.backgroundColor
    editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 0, length: 4))
    let original = try #require(editor.textStorage).copy() as? NSAttributedString
    let text = editor.string
    let marked = editor.markedRange()
    let selection = editor.selectedRange()
    coordinator.highlighter.update(
      syntax: nil, revision: nil, enabled: true, font: base, document: document, theme: second)
    #expect(
      editor.font?.pointSize == 22 && editor.textColor == oldColor
        && editor.backgroundColor == oldPaper)
    #expect(editor.textStorage?.isEqual(to: try #require(original)) == true)
    #expect(
      editor.hasMarkedText() && editor.markedRange() == marked
        && editor.selectedRange() == selection)
    editor.unmarkText()
    #expect(editor.font?.pointSize == 26)
    #expect(editor.textColor?.usingColorSpace(.sRGB)?.redComponent == 17.0 / 255)
    #expect(editor.backgroundColor.usingColorSpace(.sRGB)?.redComponent == 1)
    #expect(editor.string == text && document.text == text)
  }

  @Test(
    "Theme font/color changes preserve typing and paste undo/redo across writing defaults",
    arguments: [false, true])
  func nativeHistory(_ paste: Bool) throws {
    let source = "中文 😀\r\nTail\r\n"
    let base = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let (document, coordinator, editor, window) = try host(source, font: base)
    defer { window.close() }
    let originalColor = editor.textColor
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    func insert(_ text: String) throws {
      undo.beginUndoGrouping()
      defer { undo.endUndoGrouping() }
      if paste {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.setString(text, forType: .string))
        #expect(editor.readSelection(from: board, type: .string))
      } else {
        editor.insertText(text, replacementRange: editor.selectedRange())
      }
    }
    try insert("!")
    #expect(editor.string == source + "!" && document.text == editor.string)
    let name = undo.undoActionName
    let revision = document.revision
    let theme = try EditorTheme.parse(
      "editor\nforeground: 112233\nfont-size: 22px\n\neditor-current-line\nfont-size: +2px\n")
    coordinator.highlighter.update(
      syntax: nil, revision: nil, enabled: true, font: base, document: document, theme: theme)
    #expect(editor.font?.pointSize == 24)
    #expect(
      document.revision == revision && undo.undoActionName == name && undo.canUndo && !undo.canRedo)
    try insert("?")
    #expect(editor.string == source + "!?" && document.text == editor.string)
    #expect((editor.typingAttributes[.font] as? NSFont)?.pointSize == 24)
    let last =
      try #require(editor.textStorage).attribute(
        .font, at: editor.string.utf16.count - 1, effectiveRange: nil) as? NSFont
    #expect(last?.pointSize == 24)
    undo.undo()
    #expect(editor.string == source + "!" && document.text == editor.string)
    undo.undo()
    #expect(
      editor.string.utf8.elementsEqual(source.utf8) && document.text == source && undo.canRedo)
    undo.redo()
    undo.redo()
    #expect(editor.string == source + "!?" && document.text == editor.string)
    let finalRevision = document.revision
    coordinator.highlighter.update(
      syntax: nil, revision: nil, enabled: true, font: base, document: document)
    #expect(
      editor.font == base && editor.textColor == originalColor && document.revision == finalRevision
    )
    #expect(undo.canUndo && editor.string == source + "!?")
  }

}
