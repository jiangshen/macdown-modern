import AppKit
import SwiftUI

/// Native editing surface. It never requests the legacy layoutManager, which would
/// force a TextKit 1 fallback, and never resets marked text during SwiftUI updates.
public struct NativeMarkdownEditor: NSViewRepresentable {
  public let document: MarkdownDocument
  public var fontName: String
  public var fontSize: Double
  @Environment(\.undoManager) private var undoManager

  public init(document: MarkdownDocument, fontName: String = "Menlo-Regular", fontSize: Double = 14)
  {
    self.document = document
    self.fontName = fontName
    self.fontSize = fontSize
  }

  public func makeCoordinator() -> Coordinator { Coordinator(document: document) }

  public func makeNSView(context: Context) -> NSScrollView {
    context.coordinator.undoManager = undoManager
    return Self.makeScrollView(document: document, coordinator: context.coordinator)
  }

  static func makeScrollView(document: MarkdownDocument, coordinator: Coordinator) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder

    let editor = NSTextView(usingTextLayoutManager: true)
    editor.isRichText = false
    editor.importsGraphics = false
    editor.isEditable = true
    editor.isSelectable = true
    editor.allowsUndo = true
    editor.usesFindBar = true
    editor.isIncrementalSearchingEnabled = true
    editor.isContinuousSpellCheckingEnabled = true
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.font = .monospacedSystemFont(
      ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
      weight: .regular)
    editor.textColor = .textColor
    editor.backgroundColor = .textBackgroundColor
    editor.textContainerInset = NSSize(width: 24, height: 24)
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = false
    editor.autoresizingMask = [.width]
    editor.textContainer?.widthTracksTextView = true
    editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    editor.setAccessibilityIdentifier("markdownSourceEditor")
    editor.setAccessibilityLabel(String(localized: "Markdown source"))
    editor.string = document.text
    coordinator.editor = editor
    editor.delegate = coordinator
    scrollView.documentView = editor
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.document = document
    context.coordinator.undoManager = undoManager
    Self.synchronize(scrollView, document: document, coordinator: context.coordinator)
    guard let editor = scrollView.documentView as? NSTextView else { return }
    let size = min(72, max(8, fontSize))
    let font =
      NSFont(name: fontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    if editor.font != font { editor.font = font }
    if let request = document.selectionRequest,
      request.id != context.coordinator.selectionID, !editor.hasMarkedText()
    {
      var offset = min(max(0, request.offset), (editor.string as NSString).length)
      if offset < (editor.string as NSString).length,
        (0xDC00...0xDFFF).contains((editor.string as NSString).character(at: offset))
      {
        offset = max(0, offset - 1)
      }
      let range = NSRange(location: offset, length: 0)
      editor.setSelectedRange(range)
      editor.scrollRangeToVisible(range)
      editor.window?.makeFirstResponder(editor)
      context.coordinator.selectionID = request.id
    }
  }

  static func synchronize(
    _ scrollView: NSScrollView, document: MarkdownDocument, coordinator: Coordinator
  ) {
    guard let editor = scrollView.documentView as? NSTextView,
      !editor.hasMarkedText(), !editor.string.utf8.elementsEqual(document.text.utf8)
    else { return }
    let previousSelection = editor.selectedRange()
    coordinator.isSynchronizing = true
    editor.string = document.text
    let length = (editor.string as NSString).length
    var location = min(previousSelection.location, length)
    if location < length,
      (0xDC00...0xDFFF).contains((editor.string as NSString).character(at: location))
    {
      location = max(0, location - 1)
    }
    var end = location + min(previousSelection.length, length - location)
    if end < length, (0xDC00...0xDFFF).contains((editor.string as NSString).character(at: end)) {
      end = max(location, end - 1)
    }
    editor.setSelectedRange(NSRange(location: location, length: end - location))
    coordinator.isSynchronizing = false
  }

  public static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    (scrollView.documentView as? NSTextView)?.delegate = nil
    coordinator.undoManager = nil
    coordinator.editor = nil
  }

  @MainActor
  public final class Coordinator: NSObject, NSTextViewDelegate {
    var document: MarkdownDocument
    weak var editor: NSTextView?
    weak var undoManager: UndoManager? {
      didSet {
        guard oldValue !== undoManager else { return }
        let center = NotificationCenter.default
        center.removeObserver(
          self, name: NSNotification.Name.NSUndoManagerDidUndoChange, object: oldValue)
        center.removeObserver(
          self, name: NSNotification.Name.NSUndoManagerDidRedoChange, object: oldValue)
        if let undoManager {
          center.addObserver(
            self, selector: #selector(undoStateChanged),
            name: NSNotification.Name.NSUndoManagerDidUndoChange, object: undoManager)
          center.addObserver(
            self, selector: #selector(undoStateChanged),
            name: NSNotification.Name.NSUndoManagerDidRedoChange, object: undoManager)
        }
      }
    }
    var isSynchronizing = false
    var selectionID: UUID?

    init(document: MarkdownDocument) { self.document = document }

    public func textDidChange(_ notification: Notification) {
      guard !isSynchronizing, let editor = notification.object as? NSTextView else { return }
      document.acceptNativeEdit(editor.string)
    }

    @objc private func undoStateChanged(_ notification: Notification) {
      guard !isSynchronizing, let editor else { return }
      document.acceptNativeEdit(editor.string)
    }

    public func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    deinit { NotificationCenter.default.removeObserver(self) }
  }
}
