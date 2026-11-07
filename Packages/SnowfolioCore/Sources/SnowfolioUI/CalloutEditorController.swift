import AppKit
import EditorCore
import MarkdownCore
import SwiftUI

@MainActor
public final class CalloutEditorController {
  weak var document: MarkdownDocument?
  weak var editing: EditorCommandController?
  weak var preferences: AppPreferences?
  private var popover: NSPopover?
  private var targetRevision: UInt64?
  private var targetLines: Set<Int> = []

  func setTargets(_ nodes: [MarkdownNode], revision: UInt64) {
    targetRevision = revision
    targetLines = Set(nodes.compactMap { $0.callout != nil ? $0.range?.start.line : nil })
  }

  public init() {}

  func present(line: Int, revision: UInt64, relativeTo rect: NSRect, in view: NSView) -> Bool {
    guard let document, document.revision == revision, targetRevision == revision,
      targetLines.contains(line), preferences?.alerts == true,
      CalloutMarker.iconReplacement(in: document.text, line: line, emoji: nil) != nil,
      view.window != nil
    else { return false }
    close()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.contentViewController = NSHostingController(
      rootView: EmojiPicker { [weak self] emoji in
        guard let self, self.apply(emoji: emoji, line: line, revision: revision) else {
          return false
        }
        self.close()
        return true
      })
    self.popover = popover
    popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    return true
  }

  @discardableResult
  func apply(emoji: String?, line: Int, revision: UInt64) -> Bool {
    guard let document, document.revision == revision, targetRevision == revision,
      targetLines.contains(line), preferences?.alerts == true,
      let coordinator = editing?.coordinator, let editor = coordinator.editor,
      !editor.hasMarkedText(), (editor as? MarkdownTextView)?.isReceivingMarkedText != true,
      editor.selectedRanges.count == 1, editor.string.utf8.elementsEqual(document.text.utf8),
      let replacement = CalloutMarker.iconReplacement(in: document.text, line: line, emoji: emoji)
    else { return false }
    let selection = editor.selectedRange()
    let delta = replacement.replacement.utf16.count - replacement.range.length
    func shifted(_ offset: Int) -> Int {
      if offset <= replacement.range.location { return offset }
      if offset >= NSMaxRange(replacement.range) { return offset + delta }
      return replacement.range.location + replacement.replacement.utf16.count
    }
    let start = shifted(selection.location)
    let end = shifted(NSMaxRange(selection))
    let transaction = EditorTransaction(
      edit: TextEdit(range: replacement.range, replacement: replacement.replacement),
      selection: NSRange(location: start, length: max(0, end - start)))
    return coordinator.apply(transaction, actionName: String(localized: "Change Callout Emoji"))
  }

  func close() {
    popover?.performClose(nil)
    popover = nil
  }
}
