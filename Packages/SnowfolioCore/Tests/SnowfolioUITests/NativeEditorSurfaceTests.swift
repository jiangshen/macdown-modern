import AppKit
import DocumentCore
import EditorCore
import MarkdownCore
import Testing

@testable import SnowfolioUI

@Suite("Native editor theme surfaces", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorSurfaceTests {
  private func host(_ source: String) throws -> (
    MarkdownDocument, NativeMarkdownEditor.Coordinator, MarkdownTextView, NSScrollView, NSWindow
  ) {
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    window.orderFront(nil)
    editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
    return (document, coordinator, editor, scroll, window)
  }

  private func layout(_ editor: MarkdownTextView) throws {
    editor.window?.contentView?.layoutSubtreeIfNeeded()
    let manager = try #require(editor.textLayoutManager)
    manager.textViewportLayoutController.layoutViewport()
    manager.ensureLayout(for: try #require(manager.textContentManager).documentRange)
  }

  private func attributes(_ editor: MarkdownTextView, at offset: Int) throws
    -> [NSAttributedString.Key: Any]
  {
    try layout(editor)
    let manager = try #require(editor.textLayoutManager)
    let content = try #require(manager.textContentManager)
    var result: [NSAttributedString.Key: Any]?
    manager.enumerateTextLayoutFragments(from: content.documentRange.location, options: []) {
      fragment in
      guard let paragraph = fragment.textElement as? NSTextParagraph,
        let range = paragraph.elementRange
      else { return true }
      let local = offset - content.offset(from: content.documentRange.location, to: range.location)
      if local >= 0, local < paragraph.attributedString.length {
        result = paragraph.attributedString.attributes(at: local, effectiveRange: nil)
        return false
      }
      return true
    }
    return try #require(result)
  }

  @Test(
    "Surface colors are separated from glyph backgrounds and selected text cannot change layout")
  func mapping() throws {
    let theme = try EditorTheme.parse(
      """
      editor
      foreground: 112233
      background: 80123456
      caret: 998877
      caret: 123456
      font-size: 18px

      editor-current-line
      foreground: 225522
      background: fff5d6
      font-size: +2px
      font-style: italic

      editor-selection
      foreground: ffffff
      background: 345678
      font-size: 99px
      font-family: Helvetica
      font-style: bold, underlined

      STRONG
      font-style: bold
      """)
    let resolved = NativeEditorTheme(
      theme, font: .monospacedSystemFont(ofSize: 14, weight: .regular), zoom: 1)
    #expect(resolved.baseAttributes[.backgroundColor] == nil)
    #expect(resolved.backgroundColor?.alphaComponent == 128.0 / 255)
    #expect(resolved.caretColor?.usingColorSpace(.sRGB)?.redComponent == 153.0 / 255)
    #expect(
      Set(resolved.selectionAttributes.keys) == [
        .foregroundColor, .backgroundColor, .underlineStyle,
      ])
    #expect(resolved.selectionAttributes[.font] == nil)
    #expect(resolved.currentLineBackground != nil && resolved.hasCurrentLineStyle)
    let active = resolved.attributes(for: [.strong], currentLine: true)
    let font = try #require(active[.font] as? NSFont)
    #expect(font.pointSize == 20)
    #expect(NSFontManager.shared.traits(of: font).contains([.boldFontMask, .italicFontMask]))
    #expect(active[.backgroundColor] == nil)
    #expect((resolved.attributes(for: [.strong])[.font] as? NSFont)?.pointSize == 18)
  }

  @Test(
    "Page, caret, selection and moving current-line fonts restore without storage or undo changes")
  func lifecycle() async throws {
    let source = "# 中文 😀\r\nTail **bold**\r\n"
    let (document, coordinator, editor, scroll, window) = try host(source)
    defer { window.close() }
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    let original = try #require(editor.textStorage).copy() as? NSAttributedString
    let paper = editor.backgroundColor
    let drawsPaper = editor.drawsBackground
    let caret = editor.insertionPointColor
    let selection = editor.selectedTextAttributes
    let scrollPaper = scroll.backgroundColor
    let scrollDrawsPaper = scroll.drawsBackground
    let syntax = try await MarkdownProcessor().render(source, includeSyntax: true).syntax
    let font = try #require(editor.font)
    let theme = try EditorTheme.parse(
      """
      editor
      foreground: 112233
      background: 80123456
      caret: 998877
      font-size: 18px

      editor-selection
      foreground: ffffff
      background: 345678
      font-style: underlined

      editor-current-line
      foreground: 225522
      background: fff5d6
      font-size: +2px
      """)
    editor.setSelectedRange(NSRange(location: 2, length: 0))
    coordinator.highlighter.update(
      syntax: syntax, revision: 0, enabled: true, font: font, document: document, theme: theme)
    #expect(editor.backgroundColor.alphaComponent == 128.0 / 255)
    #expect(scroll.backgroundColor == editor.backgroundColor)
    #expect(!editor.drawsBackground && scroll.drawsBackground)
    #expect(editor.insertionPointColor.usingColorSpace(.sRGB)?.redComponent == 153.0 / 255)
    #expect(
      editor.selectedTextAttributes[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
    #expect((try attributes(editor, at: 2)[.font] as? NSFont)?.pointSize == 20)
    let tail = (source as NSString).range(of: "Tail").location
    #expect((try attributes(editor, at: tail)[.font] as? NSFont)?.pointSize == 18)
    editor.setSelectedRange(NSRange(location: tail, length: 0))
    #expect(coordinator.highlighter.currentLineRange?.location == tail)
    #expect((try attributes(editor, at: tail)[.font] as? NSFont)?.pointSize == 20)
    #expect((try attributes(editor, at: 2)[.font] as? NSFont)?.pointSize == 18)
    editor.setSelectedRange(NSRange(location: tail, length: 4))
    #expect(coordinator.highlighter.currentLineRange == nil)
    #expect(coordinator.highlighter.currentLineBackgroundRect() == nil)
    #expect((try attributes(editor, at: tail)[.font] as? NSFont)?.pointSize == 18)
    #expect(editor.textStorage?.isEqual(to: try #require(original)) == true)
    #expect(
      editor.string.utf8.elementsEqual(source.utf8) && document.text == source && !undo.canUndo)

    let sparse = try EditorTheme.parse("CODE\nforeground: 008800\n")
    coordinator.highlighter.update(
      syntax: syntax, revision: 0, enabled: true, font: font, document: document, theme: sparse)
    #expect(editor.backgroundColor == paper && editor.insertionPointColor == caret)
    #expect(NSDictionary(dictionary: editor.selectedTextAttributes).isEqual(to: selection))
    #expect(coordinator.highlighter.currentLineRange == nil)
    coordinator.highlighter.update(
      syntax: syntax, revision: 0, enabled: true, font: font, document: document)
    #expect(editor.backgroundColor == paper && editor.drawsBackground == drawsPaper)
    #expect(scroll.backgroundColor == scrollPaper && scroll.drawsBackground == scrollDrawsPaper)
    #expect(NSDictionary(dictionary: editor.selectedTextAttributes).isEqual(to: selection))
    #expect(editor.textStorage?.isEqual(to: try #require(original)) == true)
    #expect(!undo.canUndo && editor.string == source)

    coordinator.highlighter.update(
      syntax: syntax, revision: 0, enabled: true, font: font, document: document, theme: theme)
    coordinator.highlighter.detach()
    #expect(editor.backgroundColor == paper && editor.drawsBackground == drawsPaper)
    #expect(scroll.backgroundColor == scrollPaper && scroll.drawsBackground == scrollDrawsPaper)
  }

  @Test(
    "Current-line bands cover wrapped text, blank lines, empty documents and trailing line breaks",
    arguments: [
      "", "Tail", "Tail\n", "Tail\r\n", "First\n\nTail",
      String(repeating: "wrapped words ", count: 40) + "\nTail",
    ])
  func geometry(_ source: String) throws {
    let (document, coordinator, editor, _, window) = try host(source)
    defer { window.close() }
    let font = try #require(editor.font)
    let theme = try EditorTheme.parse("editor-current-line\nbackground: fff5d6\n")
    coordinator.highlighter.update(
      syntax: nil, revision: nil, enabled: true, font: font, document: document, theme: theme)
    let blank = (source as NSString).range(of: "\n\n")
    let offsets =
      [0, source.utf16.count] + (blank.location == NSNotFound ? [] : [blank.location + 1])
    for offset in Set(offsets) {
      editor.setSelectedRange(NSRange(location: offset, length: 0))
      try layout(editor)
      let band = try #require(
        coordinator.highlighter.currentLineBackgroundRect(),
        "\(source.debugDescription) at \(offset)")
      #expect(band.minX == editor.bounds.minX && band.width == editor.bounds.width)
      #expect(band.height > 0 && band.minY >= editor.textContainerOrigin.y)
      if source.hasPrefix("wrapped"), offset == 0 { #expect(band.height > 50) }
    }
    #expect(editor.string == source && document.text == source)
  }

  @Test("Native canvas pixels have uniform translucent paper and full-width current-line fill")
  func pixels() throws {
    let (document, coordinator, editor, scroll, window) = try host("First          line\nSecond")
    defer { window.close() }
    let font = try #require(editor.font)
    func apply(_ text: String) throws {
      coordinator.highlighter.update(
        syntax: nil, revision: nil, enabled: true, font: font,
        document: document, theme: try EditorTheme.parse(text))
      try layout(editor)
      scroll.displayIfNeeded()
    }
    func capture() throws -> NSBitmapImageRep {
      let bitmap = try #require(scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds))
      scroll.cacheDisplay(in: scroll.bounds, to: bitmap)
      return bitmap
    }
    func pixel(_ point: NSPoint, in bitmap: NSBitmapImageRep) throws -> NSColor {
      let converted = scroll.convert(point, from: editor)
      let x = Int(
        (converted.x - scroll.bounds.minX) * CGFloat(bitmap.pixelsWide) / scroll.bounds.width)
      let y = Int(
        (scroll.isFlipped ? converted.y - scroll.bounds.minY : scroll.bounds.maxY - converted.y)
          * CGFloat(bitmap.pixelsHigh) / scroll.bounds.height)
      return try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
    func same(_ lhs: NSColor, _ rhs: NSColor) {
      #expect(abs(lhs.redComponent - rhs.redComponent) < 0.015)
      #expect(abs(lhs.greenComponent - rhs.greenComponent) < 0.015)
      #expect(abs(lhs.blueComponent - rhs.blueComponent) < 0.015)
      #expect(abs(lhs.alphaComponent - rhs.alphaComponent) < 0.015)
    }
    try apply("editor\nforeground: 112233\nbackground: 80f0f0f0\n")
    let translucent = try capture()
    let margin = try pixel(NSPoint(x: 5, y: 12), in: translucent)
    for point in [
      NSPoint(x: 80, y: 32), NSPoint(x: 420, y: 32), NSPoint(x: 5, y: 90), NSPoint(x: 5, y: 298),
    ] {
      same(try pixel(point, in: translucent), margin)
    }
    try apply(
      "editor\nforeground: 112233\nbackground: f0f0f0\n\neditor-current-line\nbackground: 80ff0000\n"
    )
    let highlighted = try capture()
    let band = try #require(coordinator.highlighter.currentLineBackgroundRect())
    let left = try pixel(NSPoint(x: 5, y: band.midY), in: highlighted)
    let right = try pixel(NSPoint(x: 420, y: band.midY), in: highlighted)
    same(left, right)
    let paper = try pixel(NSPoint(x: 5, y: 90), in: highlighted)
    // The native cache uses the host display profile (including HDR mapping).
    // Check red hue, contrast and uniformity in that same profile, not assumed
    // output RGB values after a display-dependent color conversion.
    #expect(left.redComponent > left.greenComponent + 0.1)
    #expect(left.redComponent > left.blueComponent + 0.1)
    #expect(left.greenComponent < paper.greenComponent)
    #expect(left.blueComponent < paper.blueComponent)
  }

  @Test("Changing surface colors during composition preserves the native marked text and selection")
  func composition() throws {
    let (document, coordinator, editor, _, window) = try host("Text")
    defer { window.close() }
    let font = try #require(editor.font)
    editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 0, length: 4))
    let text = editor.string
    let marked = editor.markedRange()
    let selection = editor.selectedRange()
    coordinator.highlighter.update(
      syntax: nil, revision: nil, enabled: true, font: font,
      document: document,
      theme: try EditorTheme.parse(
        "editor\nbackground: f0f0f0\ncaret: 112233\n\neditor-selection\nbackground: 345678\n\neditor-current-line\nbackground: fff5d6\nfont-size: 30px\n"
      ))
    try layout(editor)
    #expect(editor.hasMarkedText() && editor.markedRange() == marked)
    #expect(editor.string == text && editor.selectedRange() == selection)
    #expect(coordinator.highlighter.currentLineRange == nil)
    editor.unmarkText()
    #expect(editor.string == text && document.text == text)
    #expect(coordinator.highlighter.currentLineRange != nil)
  }

}
