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
  func setStrikethroughEnabled(_ value: Bool) {
    if allowsStrikethrough != value { allowsStrikethrough = value }
  }

  public func perform(_ command: MarkdownCommand) {
    guard canPerform else { return }
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
      Group {
        Button("Bold") { editor?.perform(.bold) }.keyboardShortcut("b")
        Button("Italic") { editor?.perform(.italic) }.keyboardShortcut("i")
        Button("Inline Code") { editor?.perform(.inlineCode) }.keyboardShortcut("k")
        Button("Strikethrough") { editor?.perform(.strikethrough) }.keyboardShortcut("-")
          .disabled(editor?.allowsStrikethrough != true)
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
}

@MainActor
final class MarkdownTextView: NSTextView {
  weak var commandController: EditorCommandController?
  weak var syntaxHighlighter: NativeSyntaxHighlighter?
  private(set) var isReceivingMarkedText = false
  private(set) var isReadingPasteboard = false

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
      commandController?.compositionChanged(hasMarkedText())
      syntaxHighlighter?.compositionChanged()
    }
    syntaxHighlighter?.invalidate()
    super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
  }

  override func unmarkText() {
    super.unmarkText()
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
