import AppKit

/// Reads cached TextKit 2 geometry. A selection outside the laid-out viewport
/// never requests layout for the rest of a large document just to paint a row.
@MainActor
enum NativeEditorCurrentLine {
  static func backgroundRect(in editor: MarkdownTextView, line: NSRange) -> NSRect? {
    guard let manager = editor.textLayoutManager, let content = manager.textContentManager else {
      return nil
    }
    let length = editor.textStorage?.length ?? 0
    guard line.location <= length else { return nil }
    let vertical: NSRect
    if length == 0 {
      guard let window = editor.window else { return nil }
      let screen = editor.firstRect(forCharacterRange: line, actualRange: nil)
      vertical = editor.convert(window.convertFromScreen(screen), from: nil)
    } else {
      // The extra empty line after a terminal line break belongs to the previous
      // cached fragment. EOF itself does not identify a cached layout fragment.
      guard let viewport = manager.textViewportLayoutController.viewportRange else { return nil }
      let lower = content.offset(from: content.documentRange.location, to: viewport.location)
      let upper = content.offset(from: content.documentRange.location, to: viewport.endLocation)
      guard lower >= 0, upper >= lower else { return nil }
      if line.length == 0 {
        guard line.location >= lower, line.location <= upper else { return nil }
      } else {
        guard NSIntersectionRange(line, NSRange(location: lower, length: upper - lower)).length > 0
        else { return nil }
      }
      let offset = line.length == 0 ? max(0, line.location - 1) : max(line.location, lower)
      guard let location = content.location(content.documentRange.location, offsetBy: offset),
        let fragment = manager.textLayoutFragment(for: location)
      else { return nil }
      let lines = fragment.textLineFragments.filter {
        (line.length == 0) == ($0.characterRange.length == 0)
      }
      guard let first = lines.first, let last = lines.last else { return nil }
      vertical = NSRect(
        x: 0,
        y: editor.textContainerOrigin.y + fragment.layoutFragmentFrame.minY
          + first.typographicBounds.minY,
        width: 0, height: last.typographicBounds.maxY - first.typographicBounds.minY)
    }
    guard vertical.minY.isFinite, vertical.height.isFinite, vertical.height > 0 else { return nil }
    return NSRect(
      x: editor.bounds.minX, y: vertical.minY, width: editor.bounds.width, height: vertical.height)
  }
}
