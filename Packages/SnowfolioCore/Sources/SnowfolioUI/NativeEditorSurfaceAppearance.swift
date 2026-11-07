import AppKit

/// Owns reversible view-only colors. The scroll view paints paper once, including
/// below a short document; a translucent theme never paints a second glyph box.
@MainActor
final class NativeEditorSurfaceAppearance {
  private struct EditorState {
    let paper: NSColor
    let drawsBackground: Bool
    let caret: NSColor?
    let selection: [NSAttributedString.Key: Any]
  }
  @MainActor
  private struct ScrollState {
    weak var view: NSScrollView?
    let paper: NSColor
    let drawsBackground: Bool

    func restore() {
      view?.backgroundColor = paper
      view?.drawsBackground = drawsBackground
      view?.needsDisplay = true
    }
  }
  private weak var editor: MarkdownTextView?
  private var original: EditorState?
  private var scroll: ScrollState?

  init(editor: MarkdownTextView) { self.editor = editor }

  func apply(_ theme: NativeEditorTheme?) {
    guard let editor else { return }
    guard let theme else {
      restore()
      return
    }
    if original == nil {
      original = EditorState(
        paper: editor.backgroundColor, drawsBackground: editor.drawsBackground,
        caret: editor.insertionPointColor, selection: editor.selectedTextAttributes)
    }
    guard let original else { return }
    let container = editor.enclosingScrollView
    if scroll?.view !== container {
      scroll?.restore()
      scroll = container.map {
        ScrollState(view: $0, paper: $0.backgroundColor, drawsBackground: $0.drawsBackground)
      }
    }
    let paper = theme.backgroundColor ?? original.paper
    editor.backgroundColor = paper
    editor.drawsBackground = container == nil
    container?.backgroundColor = paper
    container?.drawsBackground = true
    editor.insertionPointColor = theme.caretColor ?? original.caret
    editor.selectedTextAttributes = original.selection.merging(theme.selectionAttributes) {
      _, new in new
    }
    editor.needsDisplay = true
    container?.needsDisplay = true
  }

  func restore() {
    guard let original else { return }
    if let editor {
      editor.backgroundColor = original.paper
      editor.drawsBackground = original.drawsBackground
      editor.insertionPointColor = original.caret
      editor.selectedTextAttributes = original.selection
      editor.needsDisplay = true
    }
    scroll?.restore()
    scroll = nil
    self.original = nil
  }
}
