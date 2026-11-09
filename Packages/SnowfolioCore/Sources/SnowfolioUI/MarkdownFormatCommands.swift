import AppKit
import EditorCore
import Observation
import SwiftUI

/// A window's native command target. Editing semantics live in EditorCore, while
/// this object follows AppKit focus and routes menu actions to its live text view.
@MainActor
@Observable
public final class EditorCommandController {
  @ObservationIgnored weak var coordinator: NativeMarkdownEditor.Coordinator?
  public private(set) var isFocused = false
  public private(set) var isComposing = false
  public private(set) var allowsHighlight = false
  public private(set) var allowsUnderline = false
  public private(set) var allowsStrikethrough = true
  public init() {}

  public var canPerform: Bool {
    isFocused && coordinator?.editor?.isEditable == true
      && !isComposing && coordinator?.editor?.hasMarkedText() == false
      && coordinator?.editor?.selectedRanges.count == 1
  }

  func focusChanged(_ focused: Bool) { isFocused = focused }
  func compositionChanged(_ composing: Bool) {
    if isComposing != composing { isComposing = composing }
  }
  func setUnderlineEnabled(_ value: Bool) {
    if allowsUnderline != value { allowsUnderline = value }
  }
  func setHighlightEnabled(_ value: Bool) {
    if allowsHighlight != value { allowsHighlight = value }
  }
  func setStrikethroughEnabled(_ value: Bool) {
    if allowsStrikethrough != value { allowsStrikethrough = value }
  }

  public func perform(_ command: MarkdownCommand) {
    guard canPerform else { return }
    if case .highlight = command, !allowsHighlight { return }
    if case .underline = command, !allowsUnderline { return }
    _ = coordinator?.perform(command)
  }

  public func insertLink(image: Bool = false) {
    let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let destination: String?
    if let value, value.utf16.count <= 8192, let url = URL(string: value),
      ["http", "https", "mailto", "file"].contains(url.scheme?.lowercased() ?? "")
    {
      destination = value
    } else {
      destination = nil
    }
    perform(image ? .image(destination) : .link(destination))
  }
}

extension FocusedValues {
  @Entry public var markdownEditor: EditorCommandController?
}

public struct MarkdownFormatCommands: Commands {
  @FocusedValue(\.markdownEditor) private var editor
  public init() {}

  public var body: some Commands {
    CommandMenu("Format") {
      MarkdownFormatMenuContent(editor: editor)
    }
  }
}

/// Shared by SwiftUI commands and the native application's NSHostingMenu.
struct MarkdownFormatMenuContent: View {
  let editor: EditorCommandController?

  var body: some View {
    Group {
      Button("Bold") { editor?.perform(.bold) }.keyboardShortcut("b")
      Button("Italic") { editor?.perform(.italic) }.keyboardShortcut("i")
      Button("Underline") { editor?.perform(.underline) }.keyboardShortcut("u")
        .disabled(editor?.allowsUnderline != true)
      Button("Inline Code") { editor?.perform(.inlineCode) }.keyboardShortcut("k")
      Button("Strikethrough") { editor?.perform(.strikethrough) }.keyboardShortcut("-")
        .disabled(editor?.allowsStrikethrough != true)
      Button("Highlight") { editor?.perform(.highlight) }.keyboardShortcut("=")
        .disabled(editor?.allowsHighlight != true)
      Button("Comment") { editor?.perform(.comment) }.keyboardShortcut("/")
      Divider()
      Menu("Heading") {
        ForEach(1...6, id: \.self) { level in
          Button("Heading \(level)") { editor?.perform(.heading(level)) }
            .keyboardShortcut(KeyEquivalent(Character(String(level))))
        }
        Divider()
        Button("Paragraph") { editor?.perform(.paragraph) }.keyboardShortcut("0")
      }
      Divider()
      Button("Ordered List") { editor?.perform(.orderedList) }.keyboardShortcut(
        "o", modifiers: [.command, .shift])
      Button("Unordered List") { editor?.perform(.unorderedList) }.keyboardShortcut(
        "u", modifiers: [.command, .shift])
      Button("Blockquote") { editor?.perform(.blockquote) }.keyboardShortcut(
        "b", modifiers: [.command, .shift])
      Button("Toggle Task") { editor?.perform(.toggleTask) }
      Divider()
      Button("Indent") { editor?.perform(.indent) }.keyboardShortcut("]")
      Button("Outdent") { editor?.perform(.outdent) }.keyboardShortcut("[")
      Divider()
      Button("Link") { editor?.insertLink() }.keyboardShortcut(
        "k", modifiers: [.command, .shift])
      Button("Image") { editor?.insertLink(image: true) }.keyboardShortcut(
        "i", modifiers: [.command, .shift])
      Button("New Paragraph") { editor?.perform(.newParagraph) }.keyboardShortcut(.return)
    }.disabled(editor?.canPerform != true)
  }
}

@MainActor
final class MarkdownTextView: NSTextView {
  let fileDrop = MarkdownFileDropHandler()
  var layoutPreferences: EditorLayoutPreferences? {
    didSet { if layoutPreferences != oldValue { needsLayout = true } }
  }
  // The native snapshot may lag the reference model while a file loads.
  private(set) weak var sourceDocument: MarkdownDocument?
  private(set) var sourceRevision: UInt64?
  private var pastEnd: NativeEditorScrollPastEnd?
  var scrollPastEndMinimumHeight: CGFloat? { pastEnd?.minimumHeight }

  func refreshScrollPastEnd() {
    if pastEnd == nil, layoutPreferences?.scrollsPastEnd == true {
      pastEnd = NativeEditorScrollPastEnd(editor: self)
    }
    pastEnd?.refresh()
  }

  private var insertionMetricsFont: NSFont?
  private var insertionMetricsHeight: CGFloat = 0

  override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect
  {
    let rect = super.firstRect(forCharacterRange: range, actualRange: actualRange)
    return terminalInsertionRect(rect, range: range, screenCoordinates: true)
  }

  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    let corrected =
      selectedRanges.count == 1
      ? terminalInsertionRect(rect, range: selectedRange(), screenCoordinates: false) : rect
    super.drawInsertionPoint(in: corrected, color: color, turnedOn: flag)
  }

  private func terminalInsertionRect(
    _ original: NSRect, range: NSRange, screenCoordinates: Bool
  ) -> NSRect {
    guard range.length == 0, let storage = textStorage, range.location == storage.length,
      (syntaxHighlighter?.appliedLineSpacing ?? 0) > 0, let font
    else { return original }
    if storage.length > 0 {
      let last = (storage.string as NSString).character(at: storage.length - 1)
      guard [10, 13, 0x2028, 0x2029].contains(last) else { return original }
    }
    if insertionMetricsFont != font {
      insertionMetricsFont = font
      // This standalone metric query never accesses NSTextView.layoutManager or
      // attaches a TextKit 1 manager to the editor's TextKit 2 storage.
      insertionMetricsHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
    }
    let height = insertionMetricsHeight
    guard height > 0, original.height > height else { return original }
    // Custom paragraph presentation can include the following line gap in the
    // terminal insertion rectangle. Keep the native writing font's bottom edge.
    var rect = original
    if !screenCoordinates && isFlipped { rect.origin.y += rect.height - height }
    rect.size.height = height
    return rect
  }

  func markSourceSynchronized(with document: MarkdownDocument) {
    sourceDocument = document
    sourceRevision = document.revision
  }
  var viewportLayoutChanged: (@MainActor () -> Void)?
  var viewportPresentationWillChange: (@MainActor () -> Void)?
  var viewportInputBegan: (@MainActor () -> Void)?

  override func draw(_ dirtyRect: NSRect) {
    if !drawsBackground { syntaxHighlighter?.drawCurrentLineBackground(in: dirtyRect) }
    super.draw(dirtyRect)
  }

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    if drawsBackground { syntaxHighlighter?.drawCurrentLineBackground(in: rect) }
  }

  override func doCommand(by selector: Selector) {
    viewportInputBegan?()
    super.doCommand(by: selector)
  }

  override func scrollWheel(with event: NSEvent) {
    viewportInputBegan?()
    super.scrollWheel(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    viewportInputBegan?()
    super.mouseDown(with: event)
  }
  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = frame.width != newSize.width
    super.setFrameSize(newSize)
    // A persistent scroller can shrink the clip view during an existing layout.
    // Update the column immediately; another needsLayout flag can be consumed by
    // that same pass without laying out the newly narrowed text view.
    if widthChanged { applyEditorGeometry() }
  }

  override func layout() {
    applyEditorGeometry()
    super.layout()
    refreshScrollPastEnd()
    viewportLayoutChanged?()
  }

  private func applyEditorGeometry() {
    guard !hasMarkedText(), !isReceivingMarkedText, let layoutPreferences,
      let container = textContainer
    else { return }
    let geometry = layoutPreferences.geometry(viewWidth: bounds.width)
    let inset = NSSize(width: geometry.horizontalInset, height: geometry.verticalInset)
    guard
      textContainerInset != inset || container.widthTracksTextView
        || container.containerSize.width != geometry.columnWidth
    else { return }
    viewportPresentationWillChange?()
    container.widthTracksTextView = false
    textContainerInset = inset
    container.containerSize = NSSize(
      width: geometry.columnWidth, height: CGFloat.greatestFiniteMagnitude)
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    fileDrop.operation(for: sender) ?? super.draggingEntered(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    fileDrop.operation(for: sender) ?? super.draggingUpdated(sender)
  }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if let operation = fileDrop.operation(for: sender) { return operation == .copy }
    return super.prepareForDragOperation(sender)
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    fileDrop.perform(sender) ?? super.performDragOperation(sender)
  }

  weak var commandController: EditorCommandController?
  weak var syntaxHighlighter: NativeSyntaxHighlighter?
  private(set) var isReceivingMarkedText = false
  private(set) var isReadingPasteboard = false

  /// Restored UI offsets may refer to an externally shortened document. Clamp them
  /// without changing source bytes, undo state, or splitting a UTF-16 surrogate pair.
  func restoreSelection(location: Int, length: Int) {
    let source = string as NSString
    var start = min(source.length, max(0, location))
    var end = start + min(source.length - start, max(0, length))
    if start < source.length, (0xDC00...0xDFFF).contains(source.character(at: start)) { start -= 1 }
    if length <= 0 {
      end = start
    } else if end < source.length, (0xDC00...0xDFFF).contains(source.character(at: end)) {
      end += 1
    }
    setSelectedRange(NSRange(location: start, length: end - start))
  }

  override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool
  {
    let previous = isReadingPasteboard
    isReadingPasteboard = true
    defer { isReadingPasteboard = previous }
    return super.readSelection(from: pboard, type: type)
  }

  override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
    isReceivingMarkedText = true
    defer {
      isReceivingMarkedText = false
      needsLayout = true
      commandController?.compositionChanged(hasMarkedText())
      syntaxHighlighter?.compositionChanged()
    }
    syntaxHighlighter?.invalidate()
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
  }

  override func unmarkText() {
    super.unmarkText()
    needsLayout = true
    syntaxHighlighter?.compositionChanged()
    commandController?.compositionChanged(hasMarkedText())
  }
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    if result { commandController?.focusChanged(true) }
    return result
  }
  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    if result { commandController?.focusChanged(false) }
    return result
  }
}

extension MarkdownCommand {
  var actionName: String {
    switch self {
    case .bold: String(localized: "Bold")
    case .italic: String(localized: "Italic")
    case .inlineCode: String(localized: "Inline Code")
    case .strikethrough: String(localized: "Strikethrough")
    case .highlight: String(localized: "Highlight")
    case .underline: String(localized: "Underline")
    case .comment: String(localized: "Comment")
    case .heading: String(localized: "Heading")
    case .paragraph: String(localized: "Paragraph")
    case .orderedList: String(localized: "Ordered List")
    case .unorderedList: String(localized: "Unordered List")
    case .blockquote: String(localized: "Blockquote")
    case .indent: String(localized: "Indent")
    case .outdent: String(localized: "Outdent")
    case .link: String(localized: "Link")
    case .image: String(localized: "Image")
    case .toggleTask: String(localized: "Toggle Task")
    case .newParagraph: String(localized: "New Paragraph")
    }
  }
}
