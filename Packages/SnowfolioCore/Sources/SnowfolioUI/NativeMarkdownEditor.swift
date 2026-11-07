import AppKit
import EditorCore
import MarkdownCore
import SwiftUI

/// Native editing surface. It never requests the legacy layoutManager, which would
/// force a TextKit 1 fallback, and never resets marked text during SwiftUI updates.
public struct NativeMarkdownEditor: NSViewRepresentable {
  public let document: MarkdownDocument
  public var fontName: String
  public var fontSize: Double
  public var zoomScale: Double
  public var behavior: EditorBehavior
  public var strikethroughEnabled: Bool
  public var commands: EditorCommandController?
  public var hostUndoManager: UndoManager?
  public var syntax: MarkdownSyntax?
  public var syntaxRevision: UInt64?
  public var syntaxHighlighting: Bool
  public var scrolling: DocumentScrollCoordinator?
  public var selectionStorage: Binding<Data?>?
  public var openDroppedFiles: (@MainActor ([URL]) -> Bool)?
  @Environment(\.undoManager) private var undoManager

  public init(
    document: MarkdownDocument, fontName: String = "Menlo-Regular", fontSize: Double = 14,
    behavior: EditorBehavior = .init(), strikethroughEnabled: Bool = true,
    commands: EditorCommandController? = nil, hostUndoManager: UndoManager? = nil,
    syntax: MarkdownSyntax? = nil, syntaxRevision: UInt64? = nil, syntaxHighlighting: Bool = true,
    selectionStorage: Binding<Data?>? = nil,
    openDroppedFiles: (@MainActor ([URL]) -> Bool)? = nil,
    scrolling: DocumentScrollCoordinator? = nil, zoomScale: Double = 1
  ) {
    self.document = document
    self.fontName = fontName
    self.fontSize = fontSize
    self.zoomScale = zoomScale
    self.behavior = behavior
    self.strikethroughEnabled = strikethroughEnabled
    self.commands = commands
    self.hostUndoManager = hostUndoManager
    self.syntax = syntax
    self.syntaxRevision = syntaxRevision
    self.syntaxHighlighting = syntaxHighlighting
    self.selectionStorage = selectionStorage
    self.scrolling = scrolling
    self.openDroppedFiles = openDroppedFiles
  }

  public func makeCoordinator() -> Coordinator { Coordinator(document: document) }

  public func makeNSView(context: Context) -> NSScrollView {
    context.coordinator.undoManager = hostUndoManager ?? undoManager
    context.coordinator.behavior = behavior
    context.coordinator.strikethroughEnabled = strikethroughEnabled
    context.coordinator.commands = commands
    commands?.coordinator = context.coordinator
    context.coordinator.selectionStorage = selectionStorage
    let view = Self.makeScrollView(document: document, coordinator: context.coordinator)
    (view.documentView as? MarkdownTextView)?.fileDrop.openFiles = openDroppedFiles
    view.documentView?.registerForDraggedTypes([.fileURL])
    context.coordinator.restoreSelectionIfNeeded()
    context.coordinator.scrolling = scrolling
    if let editor = view.documentView as? MarkdownTextView { scrolling?.attachSource(editor) }
    return view
  }

  static func makeScrollView(document: MarkdownDocument, coordinator: Coordinator) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.identifier = NSUserInterfaceItemIdentifier("markdownSourceScroll")
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder

    let editor = MarkdownTextView(usingTextLayoutManager: true)
    editor.identifier = NSUserInterfaceItemIdentifier("markdownSourceEditor")
    editor.commandController = coordinator.commands
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
    editor.markSourceSynchronized(with: document)
    coordinator.editor = editor
    coordinator.highlighter.attach(to: editor, document: document)
    editor.delegate = coordinator
    scrollView.documentView = editor
    return scrollView
  }

  public func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.isUpdatingView = true
    defer { context.coordinator.isUpdatingView = false }
    context.coordinator.selectionStorage = selectionStorage
    context.coordinator.document = document
    context.coordinator.undoManager = hostUndoManager ?? undoManager
    context.coordinator.behavior = behavior
    context.coordinator.strikethroughEnabled = strikethroughEnabled
    if context.coordinator.commands !== commands {
      context.coordinator.commands?.focusChanged(false)
      context.coordinator.commands?.coordinator = nil
      context.coordinator.commands = commands
      commands?.coordinator = context.coordinator
      (scrollView.documentView as? MarkdownTextView)?.commandController = commands
      commands?.focusChanged(scrollView.window?.firstResponder === scrollView.documentView)
    }
    if context.coordinator.scrolling !== scrolling {
      if let editor = scrollView.documentView as? MarkdownTextView {
        context.coordinator.scrolling?.detachSource(editor)
      }
      context.coordinator.scrolling = scrolling
    }
    Self.synchronize(scrollView, document: document, coordinator: context.coordinator)
    context.coordinator.restoreSelectionIfNeeded()
    (scrollView.documentView as? MarkdownTextView)?.fileDrop.openFiles = openDroppedFiles
    guard let editor = scrollView.documentView as? NSTextView else { return }
    if let window = editor.window, window.firstResponder === window,
      !editor.isHiddenOrHasHiddenAncestor
    {
      window.makeFirstResponder(editor)
    }
    if let editor = editor as? MarkdownTextView { scrolling?.attachSource(editor) }
    let size = DocumentZoomController.sourceFontSize(base: fontSize, scale: zoomScale)
    let font =
      NSFont(name: fontName, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    context.coordinator.highlighter.update(
      syntax: syntax, revision: syntaxRevision,
      enabled: syntaxHighlighting, font: font, document: document)
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
      scrolling?.sourceEditedOrNavigated()
      editor.setSelectedRange(range)
      editor.scrollRangeToVisible(range)
      editor.window?.makeFirstResponder(editor)
      context.coordinator.selectionID = request.id
    }
  }

  static func synchronize(
    _ scrollView: NSScrollView, document: MarkdownDocument, coordinator: Coordinator
  ) {
    guard let editor = scrollView.documentView as? MarkdownTextView,
      !editor.hasMarkedText(), !editor.isReceivingMarkedText
    else { return }
    defer { editor.markSourceSynchronized(with: document) }
    guard !editor.string.utf8.elementsEqual(document.text.utf8) else { return }
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
    coordinator.highlighter.invalidate()
    coordinator.isSynchronizing = false
  }

  public static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
    if let editor = scrollView.documentView as? MarkdownTextView {
      coordinator.scrolling?.detachSource(editor)
    }
    coordinator.scrolling = nil
    (scrollView.documentView as? MarkdownTextView)?.fileDrop.openFiles = nil
    coordinator.highlighter.detach()
    (scrollView.documentView as? NSTextView)?.delegate = nil
    coordinator.undoManager = nil
    coordinator.commands?.focusChanged(false)
    coordinator.commands?.coordinator = nil
    coordinator.editor = nil
  }

  @MainActor
  public final class Coordinator: NSObject, NSTextViewDelegate {
    let highlighter = NativeSyntaxHighlighter()
    weak var scrolling: DocumentScrollCoordinator?
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
    var behavior = EditorBehavior()
    var strikethroughEnabled = true
    weak var commands: EditorCommandController?
    var isApplyingCommand = false
    var isSynchronizing = false
    var selectionID: UUID?

    init(document: MarkdownDocument) { self.document = document }

    @discardableResult
    func perform(_ command: MarkdownCommand) -> Bool {
      guard let editor, !editor.hasMarkedText(),
        (editor as? MarkdownTextView)?.isReceivingMarkedText != true,
        editor.selectedRanges.count == 1
      else {
        return false
      }
      do {
        guard
          let transaction = try MarkdownEditing.transaction(
            for: command, in: editor.string,
            selection: editor.selectedRange(), behavior: behavior)
        else { return false }
        return apply(transaction, actionName: command.actionName)
      } catch { return false }
    }

    @discardableResult
    func apply(_ transaction: EditorTransaction, actionName: String) -> Bool {
      guard let editor, editor.isEditable, !editor.hasMarkedText(), !isApplyingCommand else {
        return false
      }
      let source = editor.string as NSString
      guard transaction.edit.range.location >= 0, transaction.edit.range.length >= 0,
        transaction.edit.range.location <= source.length,
        transaction.edit.range.length <= source.length - transaction.edit.range.location
      else { return false }
      if source.substring(with: transaction.edit.range).utf8.elementsEqual(
        transaction.edit.replacement.utf8)
      {
        editor.setSelectedRange(transaction.selection)
        return true
      }
      editor.breakUndoCoalescing()
      isApplyingCommand = true
      defer { isApplyingCommand = false }
      let manager = editor.undoManager
      manager?.beginUndoGrouping()
      let previousSelection = editor.selectedRange()
      if let manager {
        registerSelectionBeforeChange(
          previousSelection, after: transaction.selection, manager: manager)
      }
      editor.insertText(transaction.edit.replacement, replacementRange: transaction.edit.range)
      editor.setSelectedRange(transaction.selection)
      if let manager {
        registerSelectionAfterChange(
          previousSelection, after: transaction.selection, manager: manager)
      }
      manager?.setActionName(actionName)
      manager?.endUndoGrouping()
      editor.breakUndoCoalescing()
      document.acceptNativeEdit(editor.string)
      (editor as? MarkdownTextView)?.markSourceSynchronized(with: document)
      scrolling?.sourceEditedOrNavigated()
      editor.scrollRangeToVisible(transaction.selection)
      return true
    }

    // Native text undo is between two selection actions. Undo runs the trailing
    // no-op, text inverse, then restores the old selection. Redo reverses that order
    // and restores the new selection only after its text exists. Each selection action
    // registers its mirror, so repeated undo/redo stays one native undo group.
    private func registerSelectionBeforeChange(
      _ before: NSRange, after: NSRange, manager: UndoManager
    ) {
      manager.registerUndo(withTarget: self) { [weak manager] coordinator in
        guard let manager else { return }
        coordinator.restoreSelection(before)
        coordinator.registerSelectionAfterChange(after, after: before, manager: manager)
      }
    }

    private func registerSelectionAfterChange(
      _ before: NSRange, after: NSRange, manager: UndoManager
    ) {
      manager.registerUndo(withTarget: self) { [weak manager] coordinator in
        guard let manager else { return }
        coordinator.registerSelectionBeforeChange(after, after: before, manager: manager)
      }
    }

    private func restoreSelection(_ selection: NSRange) {
      guard let editor else { return }
      let text = editor.string as NSString
      var start = min(max(0, selection.location), text.length)
      if start < text.length, (0xDC00...0xDFFF).contains(text.character(at: start)) {
        start = max(0, start - 1)
      }
      var end = start + min(max(0, selection.length), text.length - start)
      if end < text.length, (0xDC00...0xDFFF).contains(text.character(at: end)) {
        end = max(start, end - 1)
      }
      let range = NSRange(location: start, length: end - start)
      editor.setSelectedRange(range)
      editor.scrollRangeToVisible(range)
    }

    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard !isApplyingCommand, !textView.hasMarkedText(),
        (textView as? MarkdownTextView)?.isReceivingMarkedText != true,
        textView.selectedRanges.count == 1
      else {
        return false
      }
      let input: MarkdownInput
      switch commandSelector {
      case #selector(NSResponder.insertNewline(_:)): input = .newline
      case #selector(NSResponder.insertTab(_:)): input = .tab
      case #selector(NSResponder.insertBacktab(_:)): input = .backtab
      case #selector(NSResponder.deleteBackward(_:)): input = .backspace
      default: return false
      }
      do {
        guard
          let transaction = try MarkdownEditing.input(
            input, in: textView.string,
            selection: textView.selectedRange(), behavior: behavior)
        else {
          // Shift-Tab stays an editing command even if there is no indent to remove.
          return commandSelector == #selector(NSResponder.insertBacktab(_:))
        }
        return apply(transaction, actionName: String(localized: "Typing"))
      } catch { return false }
    }

    public func textView(
      _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
      replacementString: String?
    ) -> Bool {
      guard !isApplyingCommand, behavior.pairDelimiters, !textView.hasMarkedText(),
        (textView as? MarkdownTextView)?.isReadingPasteboard != true,
        (textView as? MarkdownTextView)?.isReceivingMarkedText != true,
        textView.selectedRanges.count == 1, affectedCharRange == textView.selectedRange(),
        let replacementString, replacementString != "~" || strikethroughEnabled
      else { return true }
      do {
        guard
          let transaction = try MarkdownEditing.matchingReplacement(
            replacementString,
            in: textView.string, selection: affectedCharRange)
        else { return true }
        return !apply(transaction, actionName: String(localized: "Typing"))
      } catch { return true }
    }

    var selectionStorage: Binding<Data?>?
    var isUpdatingView = false
    private var didRestoreSelection = false

    func restoreSelectionIfNeeded() {
      guard !didRestoreSelection, let editor = editor as? MarkdownTextView,
        !editor.hasMarkedText(), let data = selectionStorage?.wrappedValue
      else { return }
      // The reference document host can deliver its first snapshot after view creation.
      guard document.loadRevision > 0 || !document.text.isEmpty else { return }
      didRestoreSelection = true
      guard let state = try? JSONDecoder().decode(EditorSelectionState.self, from: data) else {
        return
      }
      let previous = isSynchronizing
      isSynchronizing = true
      defer { isSynchronizing = previous }
      editor.restoreSelection(location: state.location, length: state.length)
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
      guard !isSynchronizing, !isUpdatingView, let editor, !editor.hasMarkedText(),
        let selectionStorage
      else { return }
      didRestoreSelection = true
      let selection = editor.selectedRange()
      selectionStorage.wrappedValue = try? JSONEncoder().encode(
        EditorSelectionState(location: selection.location, length: selection.length))
    }

    public func textDidChange(_ notification: Notification) {
      guard !isSynchronizing, let editor = notification.object as? NSTextView else { return }
      document.acceptNativeEdit(editor.string)
      (editor as? MarkdownTextView)?.markSourceSynchronized(with: document)
      scrolling?.sourceEditedOrNavigated()
      highlighter.invalidate()
      commands?.compositionChanged(editor.hasMarkedText())
    }

    @objc private func undoStateChanged(_ notification: Notification) {
      guard !isSynchronizing, let editor else { return }
      let revision = document.revision
      document.acceptNativeEdit(editor.string)
      (editor as? MarkdownTextView)?.markSourceSynchronized(with: document)
      if document.revision != revision {
        scrolling?.sourceEditedOrNavigated()
        highlighter.invalidate()
      }
    }

    public func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    deinit { NotificationCenter.default.removeObserver(self) }
  }
}

/// UI offsets only; the document host remains the sole owner of saved source data.
struct EditorSelectionState: Codable, Equatable {
  let location: Int
  let length: Int
}
