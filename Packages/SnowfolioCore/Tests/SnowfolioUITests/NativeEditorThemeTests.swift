import AppKit
import DocumentCore
import EditorCore
import MarkdownCore
import Testing

@testable import SnowfolioUI

@Suite("Native theme paragraph presentation", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorThemeTests {
  private func laidOut(_ offset: Int, in editor: NSTextView) throws -> (
    [NSAttributedString.Key: Any], CGFloat
  ) {
    let layout = try #require(editor.textLayoutManager)
    let content = try #require(layout.textContentManager)
    editor.window?.contentView?.layoutSubtreeIfNeeded()
    layout.textViewportLayoutController.layoutViewport()
    layout.ensureLayout(for: content.documentRange)
    var result: ([NSAttributedString.Key: Any], CGFloat)?
    layout.enumerateTextLayoutFragments(from: content.documentRange.location, options: []) {
      fragment in
      guard let paragraph = fragment.textElement as? NSTextParagraph,
        let range = paragraph.elementRange
      else { return true }
      let start = content.offset(from: content.documentRange.location, to: range.location)
      let local = offset - start
      if local >= 0, local < paragraph.attributedString.length {
        result = (
          paragraph.attributedString.attributes(at: local, effectiveRange: nil),
          fragment.layoutFragmentFrame.height
        )
        return false
      }
      return true
    }
    return try #require(result)
  }

  @Test(
    "Syntax fonts stay out of storage while native writing defaults preserve source and undo"
  )
  func paragraphFonts() async throws {
    let source = "# 中文 **bold *italic***\r\n\r\nTail `code` and _under_."
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.close() }
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.font = font
    let backing = try #require(editor.textStorage).copy() as? NSAttributedString
    let selected = (source as NSString).range(of: "中文")
    editor.setSelectedRange(selected)
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let theme = try EditorTheme.parse(
      """
      editor
      foreground: 112233

      H1
      font-size: 30px
      font-style: bold
      foreground: aa0000

      EMPH
      font-size: +2pt
      font-style: italic, underlined

      STRONG
      font-style: bold

      CODE
      font-size: 12px
      foreground: 008800
      """)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font,
      document: document, theme: theme)
    let (heading, height) = try laidOut(selected.location, in: editor)
    #expect((heading[.font] as? NSFont)?.pointSize == 30)
    #expect(height >= 35)
    let italic = try laidOut((source as NSString).range(of: "italic").location, in: editor).0
    let italicFont = try #require(italic[.font] as? NSFont)
    #expect(italicFont.pointSize == 16)
    #expect(NSFontManager.shared.traits(of: italicFont).contains([.boldFontMask, .italicFontMask]))
    #expect(italic[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    let code = try laidOut((source as NSString).range(of: "code").location, in: editor).0
    #expect((code[.font] as? NSFont)?.pointSize == 12)
    #expect(
      (try laidOut((source as NSString).range(of: "`code`").location, in: editor).0[.font]
        as? NSFont)?.pointSize == 12)
    #expect(
      (code[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)?.greenComponent == 136.0 / 255)
    let writingBacking = NSMutableAttributedString(attributedString: try #require(backing))
    let writingColor = NSColor(srgbRed: 17.0 / 255, green: 34.0 / 255, blue: 51.0 / 255, alpha: 1)
    #expect(editor.font == font && editor.textColor == writingColor)
    writingBacking.addAttribute(
      .foregroundColor, value: writingColor,
      range: NSRange(location: 0, length: writingBacking.length))
    #expect(editor.textStorage?.isEqual(to: writingBacking) == true)
    #expect(editor.string.utf8.elementsEqual(source.utf8) && document.text == source)
    #expect(editor.selectedRange() == selected && !undo.canUndo)

    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font,
      document: document)
    let restored = try laidOut(selected.location, in: editor)
    #expect((restored.0[.font] as? NSFont)?.pointSize == 14)
    #expect(restored.1 < height)
    #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
    #expect(editor.selectedRange() == selected && !undo.canUndo)

    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font,
      document: document, theme: theme)
    _ = try laidOut(selected.location, in: editor)
    let insertion = NSMaxRange(selected)
    undo.beginUndoGrouping()
    editor.insertText("!", replacementRange: NSRange(location: insertion, length: 0))
    undo.endUndoGrouping()
    #expect(document.text == editor.string)
    #expect(
      (editor.textStorage?.attribute(.font, at: insertion, effectiveRange: nil) as? NSFont)?
        .pointSize == 14)
    undo.undo()
    #expect(document.text == source && editor.string == source)
    undo.redo()
    #expect(document.text.contains("中文!") && editor.string == document.text)
  }

  @Test("Entities, definitions and note markers reach real native paragraph typography")
  func remainingScopes() async throws {
    let source = "[a]: /target\n中文 😀 &copy; [a] Text[^n].\n\n[^n]: **Body**.\n\n[^unused]: Unused."
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.close() }
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.font = font
    let backing = try #require(editor.textStorage).copy() as? NSAttributedString
    let parsed = try await MarkdownProcessor().render(source, includeSyntax: true)
    let theme = try EditorTheme.parse(
      "HTML_ENTITY\nfont-size: 22px\n\nREFERENCE\nfont-size: 18px\n\nNOTE\nfont-size: 20px\n\nSTRONG\nfont-style: bold\n"
    )
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font,
      document: document, theme: theme)
    for (text, points) in [
      ("[a]:", 18.0), ("&copy;", 22.0), ("[^n]", 20.0), ("[^n]:", 20.0), ("Body", 20.0),
      ("[^unused]:", 20.0),
    ] {
      let attributes = try laidOut((source as NSString).range(of: text).location, in: editor).0
      #expect((attributes[.font] as? NSFont)?.pointSize == CGFloat(points), "\(text)")
    }
    let body = try laidOut((source as NSString).range(of: "Body").location, in: editor).0
    #expect(
      NSFontManager.shared.traits(of: try #require(body[.font] as? NSFont)).contains(.boldFontMask))
    #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
    #expect(editor.string == source && document.text == source)
  }

  @Test("Theme updates cannot replace marked text or apply a stale syntax snapshot")
  func compositionAndRevision() async throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "# Heading"))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.close() }
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.font = font
    let parsed = try await MarkdownProcessor().render(document.text, includeSyntax: true)
    let theme = try EditorTheme.parse("H1\nfont-size: 30px\n")
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true,
      font: font, document: document, theme: theme)
    #expect((try laidOut(2, in: editor).0[.font] as? NSFont)?.pointSize == 30)
    editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 2, length: 7))
    let composing = editor.string
    let marked = editor.markedRange()
    let selected = editor.selectedRange()
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true,
      font: font, document: document, theme: theme)
    _ = try laidOut(2, in: editor)
    #expect(editor.hasMarkedText() && editor.markedRange() == marked)
    #expect(editor.string == composing && editor.selectedRange() == selected)
    editor.unmarkText()
    #expect(document.revision > 0)
    #expect((try laidOut(2, in: editor).0[.font] as? NSFont)?.pointSize == 14)
    let fresh = try await MarkdownProcessor().render(document.text, includeSyntax: true)
    coordinator.highlighter.update(
      syntax: fresh.syntax, revision: document.revision, enabled: true,
      font: font, document: document, theme: theme)
    #expect((try laidOut(2, in: editor).0[.font] as? NSFont)?.pointSize == 30)
    #expect(editor.string == composing)
  }

  @Test("Relative theme sizes follow zoom and repeated scalar precedence while font traits combine")
  func resolution() throws {
    let theme = try EditorTheme.parse(
      """
      editor
      font-size: +2px

      H1
      font-size: +3px
      font-size: 40px
      font-style: bold
      font-style: italic
      foreground: 112233
      foreground: aabbcc

      CODE
      font-family: Helvetica
      font-size: 12px

      LINK
      font-family: SnowfolioMissingFontCheckpoint
      """)
    let font = NSFont.monospacedSystemFont(ofSize: 28, weight: .regular)
    let resolved = NativeEditorTheme(theme, font: font, zoom: 2)
    #expect((resolved.baseAttributes[.font] as? NSFont)?.pointSize == 32)
    let attributes = resolved.attributes(for: [.heading(1)])
    let heading = try #require(attributes[.font] as? NSFont)
    #expect(heading.pointSize == 38)
    let code = resolved.attributes(for: [.inlineCode])
    #expect((code[.font] as? NSFont)?.fontName == "Helvetica")
    #expect((code[.font] as? NSFont)?.pointSize == 24)
    let unavailable = resolved.attributes(for: [.link])
    #expect((unavailable[.font] as? NSFont)?.fontName == font.fontName)
    #expect(NSFontManager.shared.traits(of: heading).contains([.boldFontMask, .italicFontMask]))
    #expect(
      (attributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB)?.redComponent == 17.0 / 255
    )
  }

  @Test("Physical lazy-list and partial-tab ranges decorate only the authored bold span")
  func physicalSourceFonts() async throws {
    let theme = try EditorTheme.parse("STRONG\nfont-size: 26px\nfont-style: bold\n")
    let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    for source in [
      "- first\n**中文 😀** tail", "- first\r\n\t**中文 😀** tail",
      "> first\r**中文 😀** tail", ">\t**中文 😀** tail",
      "> before _start\n**中文 😀** end_ tail",
    ] {
      var options = MarkdownRenderingOptions()
      options.underline = true
      let parsed = try await MarkdownProcessor().render(
        source, options: options, includeSyntax: true)
      let document = MarkdownDocument(contents: TextFileContents(text: source))
      let coordinator = NativeMarkdownEditor.Coordinator(document: document)
      let undo = UndoManager()
      undo.groupsByEvent = false
      coordinator.undoManager = undo
      let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
      let editor = try #require(scroll.documentView as? MarkdownTextView)
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
        styleMask: .titled, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.animationBehavior = .none
      window.contentView = scroll
      window.orderFront(nil)
      defer { window.close() }
      editor.font = font
      let selection = (source as NSString).range(of: "中文 😀")
      editor.setSelectedRange(selection)
      coordinator.highlighter.update(
        syntax: parsed.syntax, revision: 0, enabled: true, font: font,
        document: document, theme: theme)
      let bold = try laidOut(selection.location, in: editor).0
      let actualFont = try #require(bold[.font] as? NSFont)
      #expect(actualFont.pointSize == 26)
      #expect(NSFontManager.shared.traits(of: actualFont).contains(.boldFontMask))
      let tail = try laidOut((source as NSString).range(of: "tail").location, in: editor).0
      #expect((tail[.font] as? NSFont)?.pointSize == 14)
      #expect(editor.string.utf8.elementsEqual(source.utf8) && document.revision == 0)
      #expect(editor.selectedRange() == selection && !undo.canUndo)
    }
  }

}
