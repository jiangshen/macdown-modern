import AppKit
import EditorCore

/// Retains MacDown's optional two-step line-start navigation. Native insertion
/// rectangles keep a soft-wrapped row from jumping to the logical paragraph start.
@MainActor
enum NativeEditorSmartHome {
  static func move(in editor: NSTextView) -> Bool {
    let cursor = editor.selectedRange().location
    guard cursor != NSNotFound, cursor > 0, cursor <= (editor.string as NSString).length,
      editor.window != nil
    else { return false }
    let target = LegacyLineLookup(editor.string).firstNonWhitespace(before: cursor)
    guard target != cursor else { return false }
    let destination = NSRange(location: target, length: 0)
    let targetRect = editor.firstRect(forCharacterRange: destination, actualRange: nil)
    let currentRect = editor.firstRect(
      forCharacterRange: NSRange(location: cursor, length: 0), actualRange: nil)
    guard targetRect.height > 0, currentRect.height > 0,
      abs(targetRect.minY - currentRect.minY) < 0.5
    else { return false }
    editor.setSelectedRange(destination)
    editor.scrollRangeToVisible(destination)
    return true
  }
}
