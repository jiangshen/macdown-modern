import AppKit
import DocumentCore
import EditorCore
import Testing

@testable import SnowfolioUI

@Suite("Native scrolling past the source end", .serialized, NativeUIExclusive())
@MainActor
struct NativeEditorScrollPastEndTests {
  private final class NativeReferenceDocument: NSView {
    override var isFlipped: Bool { true }
  }

  @Test("Original scroll-past-end key imports and explicit false survives reopen")
  func preferences() throws {
    let domain = "ScrollPastEnd." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(!fresh.editorLayout.scrollsPastEnd)
    defaults.removePersistentDomain(forName: domain)
    let imported = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorScrollsPastEnd": true])
    #expect(imported.editorLayout.scrollsPastEnd)
    imported.editorLayout.scrollsPastEnd = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorScrollsPastEnd": true])
    #expect(!reopened.editorLayout.scrollsPastEnd)
    #expect(SettingsCatalog.search("scroll past the end").map(\.id) == ["editorScrollsPastEnd"])
  }

  @Test(
    "Native extra scrolling preserves text, attributes, selection and history; blank tails already provide space",
    arguments: [false, true], [0.5, 1.0, 2.0, 3.0])
  func geometry(legacy: Bool, zoom: Double) throws {
    _ = NSApplication.shared
    let long = (1...150).map { "Line \($0) 中文 👩‍💻" }.joined(separator: "\n")
    for fontName in ["Menlo-Regular", "Helvetica"] {
      for source in [
        "", "\n \n", "First\nSecond", "First\r\nSecond\r\n", long,
        long + String(repeating: "\n", count: 60),
      ] {
        let document = MarkdownDocument(contents: TextFileContents(text: source))
        let coordinator = NativeMarkdownEditor.Coordinator(document: document)
        let undo = UndoManager()
        coordinator.undoManager = undo
        let scroll = NativeMarkdownEditor.makeScrollView(
          document: document, coordinator: coordinator)
        let editor = try #require(scroll.documentView as? MarkdownTextView)
        let spacing = zoom >= 2 ? 100.0 : zoom == 0.5 ? 3.0 : 0.0
        let font = try #require(
          NSFont(name: fontName, size: (zoom == 3 ? 72 : zoom == 0.5 ? 8 : 14) * zoom))
        coordinator.highlighter.update(
          syntax: nil, revision: 0, enabled: false, font: font, document: document,
          zoomScale: zoom, lineSpacing: spacing)
        scroll.scrollerStyle = legacy ? .legacy : .overlay
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
          styleMask: [.titled, .resizable],
          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderFront(nil)
        defer { window.close() }
        editor.setFrameSize(NSSize(width: 600, height: 400))
        editor.layoutPreferences = .init(lineSpacing: spacing)
        window.contentView?.layoutSubtreeIfNeeded()
        editor.textContainer?.containerSize.width = 550
        editor.textLayoutManager?.ensureLayout(
          for: try #require(editor.textLayoutManager?.textContentManager?.documentRange))
        editor.sizeToFit()
        window.contentView?.layoutSubtreeIfNeeded()
        let backing = try #require(editor.textStorage).copy() as? NSAttributedString
        let selection = NSRange(location: (source as NSString).length, length: 0)
        editor.setSelectedRange(selection)
        func maximum() -> CGFloat {
          var proposed = scroll.contentView.bounds
          proposed.origin.y = editor.frame.maxY + proposed.height + scroll.contentInsets.bottom
          return scroll.contentView.constrainBoundsRect(proposed).minY
        }
        let last = (source as NSString).rangeOfCharacter(
          from: .whitespacesAndNewlines.inverted, options: .backwards)
        var nativeRow: NSRect?
        if last.location != NSNotFound {
          let cluster = (source as NSString).rangeOfComposedCharacterSequence(at: last.location)
          editor.scrollRangeToVisible(cluster)
          editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
          let screen = editor.firstRect(forCharacterRange: cluster, actualRange: nil)
          nativeRow = editor.convert(window.convertFromScreen(screen), from: nil)
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let originalInsets = scroll.contentInsets
        let originalEffectiveInsets = scroll.contentView.contentInsets
        let originalAutomatic = scroll.automaticallyAdjustsContentInsets
        let frame = editor.frame
        let baseline = maximum()
        let hasSpaceAlready =
          nativeRow.map {
            $0.minY - baseline <= editor.textContainerInset.height + 1
          } ?? true
        editor.layoutPreferences?.scrollsPastEnd = true
        editor.layoutSubtreeIfNeeded()
        scroll.layoutSubtreeIfNeeded()
        editor.refreshScrollPastEnd()
        let extra = scroll.contentView.contentInsets.bottom - originalEffectiveInsets.bottom
        #expect(
          hasSpaceAlready ? abs(extra) < 1 : extra > 5,
          "font=\(fontName), zoom=\(zoom), spacing=\(spacing), source length=\(source.utf16.count), extra=\(extra)"
        )
        #expect(
          scroll.contentView.documentRect.height
            >= min(frame.height, scroll.contentView.bounds.height - originalEffectiveInsets.bottom))
        #expect(editor.frame.width == scroll.contentView.bounds.width)
        #expect(editor.textContainer?.containerSize.width == editor.frame.width - 48)
        #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
        #expect(editor.selectedRange() == selection && !undo.canUndo)
        #expect(editor.string == source && document.text == source && document.revision == 0)
        #expect(editor.textLayoutManager != nil)
        if !hasSpaceAlready {
          for height in [400.0, 650, 300, 400] {
            window.setContentSize(NSSize(width: 600, height: height))
            window.contentView?.layoutSubtreeIfNeeded()
            editor.refreshScrollPastEnd()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: maximum()))
            scroll.reflectScrolledClipView(scroll.contentView)
            editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
            let last = (source as NSString).rangeOfCharacter(
              from: .whitespacesAndNewlines.inverted, options: .backwards)
            let cluster = (source as NSString).rangeOfComposedCharacterSequence(at: last.location)
            let screen = editor.firstRect(forCharacterRange: cluster, actualRange: nil)
            let row = editor.convert(window.convertFromScreen(screen), from: nil)
            let top = row.minY - scroll.contentView.bounds.minY
            #expect(
              top >= -1 && top <= editor.textContainerInset.height + 1
                && row.maxY <= scroll.contentView.bounds.maxY + 1,
              "last source row top=\(top), row=\(row), viewport=\(scroll.contentView.bounds), frame=\(editor.frame), insets=\(scroll.contentView.contentInsets), minimum=\(editor.minSize)"
            )
            #expect(editor.frame.width == scroll.contentView.bounds.width)
          }

        }
        editor.layoutPreferences?.scrollsPastEnd = false
        editor.refreshScrollPastEnd()
        #expect(scroll.automaticallyAdjustsContentInsets == originalAutomatic)
        #expect(abs(scroll.contentInsets.bottom - originalInsets.bottom) < 1)
        // Usage height changes as TextKit refines layout during viewport changes.
        // Restored clamping must match an unmodified clip with the current geometry.
        for height in [400.0, 650, 300, 400] {
          window.setContentSize(NSSize(width: 600, height: height))
          window.contentView?.layoutSubtreeIfNeeded()
          let reference = NSClipView(
            frame: NSRect(origin: .zero, size: scroll.contentView.bounds.size))
          reference.automaticallyAdjustsContentInsets = false
          reference.documentView = NativeReferenceDocument(frame: editor.frame)
          reference.contentInsets = scroll.contentView.contentInsets
          var proposed = reference.bounds
          proposed.origin.y = editor.frame.maxY + proposed.height + reference.contentInsets.bottom
          let expected = reference.constrainBoundsRect(proposed).minY
          #expect(
            abs(maximum() - expected) < 1,
            "font=\(fontName), zoom=\(zoom), source length=\(source.utf16.count), current=\(maximum()), native=\(expected)"
          )
        }
      }
    }
  }
  @Test(
    "Changing scroll-past-end defers all view changes while Chinese/Japanese marked text is active",
    arguments: ["日本語", "中文"])
  func composition(_ preedit: String) throws {
    _ = NSApplication.shared
    let source = String(repeating: "A source paragraph.\n", count: 100)
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let undo = UndoManager()
    coordinator.undoManager = undo
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: .titled,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.close() }
    editor.setFrameSize(NSSize(width: 600, height: 400))
    editor.layoutPreferences = .init(scrollsPastEnd: true)
    window.contentView?.layoutSubtreeIfNeeded()
    editor.textLayoutManager?.ensureLayout(
      for: try #require(editor.textLayoutManager?.textContentManager?.documentRange))
    editor.sizeToFit()
    editor.refreshScrollPastEnd()
    let insets = scroll.contentView.contentInsets
    #expect(insets.bottom > 100)
    undo.beginUndoGrouping()
    defer { undo.endUndoGrouping() }
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    editor.setMarkedText(
      preedit, selectedRange: NSRange(location: preedit.utf16.count, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(editor.hasMarkedText())
    let backing = try #require(editor.textStorage).copy() as? NSAttributedString
    let selection = editor.selectedRange()
    let model = document.text
    let revision = document.revision
    editor.layoutPreferences?.scrollsPastEnd = false
    editor.refreshScrollPastEnd()
    #expect(scroll.contentView.contentInsets.bottom == insets.bottom)
    #expect(editor.textStorage?.isEqual(to: try #require(backing)) == true)
    #expect(editor.hasMarkedText() && editor.selectedRange() == selection)
    #expect(document.text == model && document.revision == revision)
    editor.unmarkText()
    editor.refreshScrollPastEnd()
    #expect(!editor.hasMarkedText())
    #expect(scroll.contentView.contentInsets.bottom < 10)
    #expect(editor.string == backing?.string)
  }

}
