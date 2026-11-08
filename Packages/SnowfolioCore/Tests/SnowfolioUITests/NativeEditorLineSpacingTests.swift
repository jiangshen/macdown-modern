import AppKit
import DocumentCore
import EditorCore
import MarkdownCore
import Testing

@testable import SnowfolioUI

@Suite("Native source line spacing", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorLineSpacingTests {
  @Test("Line spacing imports the original key and preserves explicit zero on reopen")
  func preferences() throws {
    let domain = "LineSpacing." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(fresh.editorLayout.lineSpacing == 0)
    defaults.removePersistentDomain(forName: domain)
    let imported = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorLineSpacing": 3.0])
    #expect(imported.editorLayout.lineSpacing == 3)
    imported.editorLayout.lineSpacing = 12.5
    #expect(defaults.double(forKey: "editorLineSpacing") == 12.5)
    imported.editorLayout.lineSpacing = 0
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorLineSpacing": 3.0])
    #expect(reopened.editorLayout.lineSpacing == 0)
    #expect(SettingsCatalog.search("line spacing").map(\.id) == ["editorLineSpacing"])
  }

  private func rowDistance(in editor: NSTextView) throws -> CGFloat {
    let manager = try #require(editor.textLayoutManager)
    editor.window?.contentView?.layoutSubtreeIfNeeded()
    manager.textViewportLayoutController.layoutViewport()
    manager.ensureLayout(for: try #require(manager.textContentManager).documentRange)
    let first = editor.firstRect(
      forCharacterRange: NSRange(location: 0, length: 1), actualRange: nil)
    let second = editor.firstRect(
      forCharacterRange: NSRange(location: 6, length: 1), actualRange: nil)
    return abs(first.minY - second.minY)
  }

  private func window(for view: NSView) -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .titled,
      backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderFront(nil)
    return window
  }

  @Test(
    "Spacing changes actual native line geometry without changing source, attributes, selection or history",
    arguments: [false, true], [0.5, 1.0, 2.0])
  func geometry(themed: Bool, zoom: Double) async throws {
    let source = "First\nSecond\n\n中文 👩‍💻 Tail\n"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = window(for: scroll)
    defer { window.close() }
    let font = NSFont.monospacedSystemFont(ofSize: 14 * zoom, weight: .regular)
    editor.font = font
    let theme =
      themed ? try EditorTheme.parse("editor\nfont-family: Helvetica\nfont-size: 14pt\n") : nil
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    func update(_ spacing: Double) {
      coordinator.highlighter.update(
        syntax: parsed.syntax, revision: 0, enabled: true, font: font, document: document,
        theme: theme, zoomScale: zoom, lineSpacing: spacing)
    }
    update(0)
    let baseline = try rowDistance(in: editor)
    let backing = try #require(editor.textStorage).copy() as? NSAttributedString
    let selected = (source as NSString).range(of: "中文 👩‍💻")
    editor.setSelectedRange(selected)
    update(12)
    #expect(abs(try rowDistance(in: editor) - baseline - 12) < 0.5)
    #expect(editor.defaultParagraphStyle?.lineSpacing == 12)
    #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
    #expect(editor.selectedRange() == selected && !undo.canUndo)
    #expect(document.text.utf8.elementsEqual(source.utf8) && document.revision == 0)

    // Compare the empty terminal line against an explicitly styled native editor.
    let referenceDocument = MarkdownDocument(contents: TextFileContents(text: source))
    let referenceCoordinator = NativeMarkdownEditor.Coordinator(document: referenceDocument)
    let referenceScroll = NativeMarkdownEditor.makeScrollView(
      document: referenceDocument, coordinator: referenceCoordinator)
    let reference = try #require(referenceScroll.documentView as? MarkdownTextView)
    reference.font = editor.font
    let style = try #require(editor.defaultParagraphStyle)
    #expect(style.lineSpacing == 12)
    reference.defaultParagraphStyle = style
    reference.textStorage?.addAttribute(
      .paragraphStyle, value: style,
      range: NSRange(location: 0, length: (source as NSString).length))
    let referenceWindow = self.window(for: referenceScroll)
    defer { referenceWindow.close() }
    let end = NSRange(location: (source as NSString).length, length: 0)
    editor.setSelectedRange(end)
    reference.setSelectedRange(end)
    var referenceTyping = reference.typingAttributes
    referenceTyping[.paragraphStyle] = style
    reference.typingAttributes = referenceTyping
    #expect((editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing == 12)
    #expect((reference.typingAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing == 12)
    let referenceDistance = try rowDistance(in: reference)
    #expect(abs(referenceDistance - baseline - 12) < 0.5)
    _ = try rowDistance(in: editor)
    let actualCaret = editor.firstRect(forCharacterRange: end, actualRange: nil)
    let referenceCaret = reference.firstRect(forCharacterRange: end, actualRange: nil)
    #expect(
      abs(actualCaret.height - referenceCaret.height) < 0.5,
      "actual=\(actualCaret.height), reference=\(referenceCaret.height)")
    let actualLocal = editor.convert(window.convertFromScreen(actualCaret), from: nil)
    let referenceLocal = reference.convert(
      referenceWindow.convertFromScreen(referenceCaret), from: nil)
    #expect(abs(actualLocal.minX - referenceLocal.minX) < 0.5)
    #expect(
      abs(actualLocal.minY - referenceLocal.minY) < 0.5,
      "actual=\(actualLocal), reference=\(referenceLocal)")
    #expect(editor.textLayoutManager != nil && reference.textLayoutManager != nil)

    undo.beginUndoGrouping()
    editor.insertText("!", replacementRange: end)
    undo.endUndoGrouping()
    #expect(document.text == source + "!")
    let changed = try #require(editor.textStorage).copy() as? NSAttributedString
    update(0)
    let restoredDistance = try rowDistance(in: editor)
    #expect(abs(restoredDistance - baseline) < 0.5)
    #expect(editor.textStorage?.isEqual(to: try #require(changed)) == true)
    undo.undo()
    #expect(document.text == source)
    let referenceZero = NSMutableParagraphStyle()
    referenceZero.setParagraphStyle(.default)
    referenceZero.lineSpacing = 0
    reference.defaultParagraphStyle = referenceZero
    reference.textStorage?.addAttribute(
      .paragraphStyle, value: referenceZero, range: NSRange(location: 0, length: source.utf16.count)
    )
    reference.setSelectedRange(end)
    _ = try rowDistance(in: reference)
    _ = try rowDistance(in: editor)
    let afterUndo = editor.firstRect(forCharacterRange: end, actualRange: nil)
    let zeroReference = reference.firstRect(forCharacterRange: end, actualRange: nil)
    #expect(abs(afterUndo.height - zeroReference.height) < 0.5)
    let undoLocal = editor.convert(window.convertFromScreen(afterUndo), from: nil)
    let zeroLocal = reference.convert(referenceWindow.convertFromScreen(zeroReference), from: nil)
    #expect(abs(undoLocal.minY - zeroLocal.minY) < 0.5)
    undo.redo()
    #expect(document.text == source + "!")
  }

  @Test(
    "Empty, ordinary, LF and CRLF insertion rectangles match native writing metrics",
    arguments: ["", "Tail", "Tail\n", "Tail\r\n"])
  func terminalMetrics(_ source: String) throws {
    for spacing in [3.0, 100.0] {
      for zoom in [0.5, 1.0, 2.0] {
        let document = MarkdownDocument(contents: TextFileContents(text: source))
        let coordinator = NativeMarkdownEditor.Coordinator(document: document)
        let scroll = NativeMarkdownEditor.makeScrollView(
          document: document, coordinator: coordinator)
        let editor = try #require(scroll.documentView as? MarkdownTextView)
        let actualWindow = window(for: scroll)
        defer { actualWindow.close() }
        let font = try #require(NSFont(name: "Helvetica", size: 14 * zoom))
        editor.font = font
        coordinator.highlighter.update(
          syntax: nil, revision: nil, enabled: false, font: font,
          document: document, zoomScale: zoom, lineSpacing: spacing)
        let referenceDocument = MarkdownDocument(contents: TextFileContents(text: source))
        let referenceCoordinator = NativeMarkdownEditor.Coordinator(document: referenceDocument)
        let referenceScroll = NativeMarkdownEditor.makeScrollView(
          document: referenceDocument, coordinator: referenceCoordinator)
        let reference = try #require(referenceScroll.documentView as? MarkdownTextView)
        reference.font = font
        let style = try #require(editor.defaultParagraphStyle)
        reference.defaultParagraphStyle = style
        reference.textStorage?.addAttribute(
          .paragraphStyle, value: style, range: NSRange(location: 0, length: source.utf16.count))
        let referenceWindow = window(for: referenceScroll)
        defer { referenceWindow.close() }
        let end = NSRange(location: source.utf16.count, length: 0)
        for view in [editor, reference] {
          view.setSelectedRange(end)
          var attributes = view.typingAttributes
          attributes[.paragraphStyle] = style
          view.typingAttributes = attributes
          let manager = try #require(view.textLayoutManager)
          view.window?.contentView?.layoutSubtreeIfNeeded()
          manager.textViewportLayoutController.layoutViewport()
          manager.ensureLayout(for: try #require(manager.textContentManager).documentRange)
        }
        var actualRange = NSRange(location: NSNotFound, length: 0)
        let actual = editor.firstRect(forCharacterRange: end, actualRange: &actualRange)
        let expected = reference.firstRect(forCharacterRange: end, actualRange: nil)
        #expect(
          actual.height > 0 && abs(actual.height - expected.height) < 0.5,
          "source=\(source.debugDescription), spacing=\(spacing), zoom=\(zoom): \(actual.height) vs \(expected.height)"
        )
        #expect(actualRange == end)
        #expect(editor.string == source && document.text == source && document.revision == 0)
        #expect(editor.textLayoutManager != nil)
      }
    }
  }

  @Test("Wrapped lines and previously cached offscreen paragraphs use the current spacing")
  func wrappedAndOffscreen() throws {
    let source = (1...80).map {
      "Paragraph \($0): " + String(repeating: "Unicode 中文 👩‍💻 wrapped writing. ", count: 12) + "\n\n"
    }.joined()
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = window(for: scroll)
    defer { window.close() }
    let font = try #require(editor.font)
    func update(_ spacing: Double) {
      coordinator.highlighter.update(
        syntax: nil, revision: nil, enabled: true, font: font, document: document,
        lineSpacing: spacing)
    }
    func metrics(_ number: Int) throws -> (CGFloat, NSRange) {
      let manager = try #require(editor.textLayoutManager)
      let content = try #require(manager.textContentManager)
      manager.ensureLayout(for: content.documentRange)
      let offset = (source as NSString).range(of: "Paragraph \(number):").location
      let location = try #require(
        content.location(content.documentRange.location, offsetBy: offset))
      let fragment = try #require(manager.textLayoutFragment(for: location))
      let lines = fragment.textLineFragments
      try #require(lines.count > 2)
      return (
        lines[1].typographicBounds.minY - lines[0].typographicBounds.minY, lines[1].characterRange
      )
    }
    update(0)
    let first = try metrics(1)
    let last = try metrics(80)
    let backing = try #require(editor.textStorage).copy() as? NSAttributedString
    editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
    update(12)
    let newFirst = try metrics(1)
    let newLast = try metrics(80)
    #expect(abs(newFirst.0 - first.0 - 12) < 0.5 && newFirst.1 == first.1)
    #expect(abs(newLast.0 - last.0 - 12) < 0.5 && newLast.1 == last.1)
    update(0)
    let restored = try metrics(80)
    #expect(abs(restored.0 - last.0) < 0.5 && restored.1 == last.1)
    #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
    #expect(document.text == source && document.revision == 0)
  }

  @Test(
    "Pending spacing leaves native preedit attributes and geometry intact until composition ends",
    arguments: ["にほん", "拼音"])
  func composition(_ preedit: String) async throws {
    let source = "First\nSecond\n\n中文"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = window(for: scroll)
    defer { window.close() }
    let font = try #require(editor.font)
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font, document: document,
      lineSpacing: 12)
    let before = try rowDistance(in: editor)
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    editor.setSelectedRange((source as NSString).range(of: "中文"))
    editor.setMarkedText(
      preedit, selectedRange: NSRange(location: preedit.utf16.count, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    let marked = editor.string
    let selection = editor.selectedRange()
    let backing = try #require(editor.textStorage).copy() as? NSAttributedString
    let modelText = document.text
    let modelRevision = document.revision
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font, document: document,
      lineSpacing: 28)
    #expect(editor.defaultParagraphStyle?.lineSpacing == 12)
    #expect(abs(try rowDistance(in: editor) - before) < 0.5)
    #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
    #expect(
      editor.string == marked && editor.selectedRange() == selection && editor.hasMarkedText())
    #expect(document.text == modelText && document.revision == modelRevision)
    editor.unmarkText()
    #expect(!editor.hasMarkedText() && editor.string == marked)
    #expect(editor.defaultParagraphStyle?.lineSpacing == 28)
    let committedDistance = try rowDistance(in: editor)
    #expect(abs(committedDistance - before - 16) < 0.5)
    coordinator.highlighter.detach()
    #expect(editor.defaultParagraphStyle == nil)
    #expect(editor.string == marked)
  }
}
