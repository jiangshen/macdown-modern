import AppKit
import SwiftUI

/// Pane visibility must not destroy NSTextView: its native undo actions and input
/// context belong to the document's lifetime, including time spent in preview mode.
struct NativeDocumentSplit: NSViewControllerRepresentable {
  let document: MarkdownDocument
  let preferences: AppPreferences
  let editing: EditorCommandController
  let html: String
  let mode: WorkspaceMode
  @Binding var previewError: String?
  @Environment(\.undoManager) private var undoManager

  func makeNSViewController(context: Context) -> Controller {
    Controller(editor: editorSurface, preview: previewSurface, mode: mode)
  }

  func updateNSViewController(_ controller: Controller, context: Context) {
    controller.editorHost.rootView = editorSurface
    controller.previewHost.rootView = previewSurface
    controller.setMode(mode, editing: editing)
  }

  private var editorSurface: EditorSurface {
    EditorSurface(
      document: document, preferences: preferences, commands: editing, undoManager: undoManager)
  }

  private var previewSurface: PreviewSurface {
    PreviewSurface(
      html: html, directory: document.fileURL?.deletingLastPathComponent(),
      remoteImages: preferences.remoteImages, error: $previewError)
  }

  final class Controller: NSSplitViewController {
    let editorHost: NSHostingController<EditorSurface>
    let previewHost: NSHostingController<PreviewSurface>
    private(set) var mode: WorkspaceMode
    private var lastSplitFraction: CGFloat = 0.5

    init(editor: EditorSurface, preview: PreviewSurface, mode: WorkspaceMode) {
      editorHost = NSHostingController(rootView: editor)
      previewHost = NSHostingController(rootView: preview)
      self.mode = .split
      super.init(nibName: nil, bundle: nil)
      splitView.isVertical = true
      splitView.dividerStyle = .thin
      for controller in [editorHost as NSViewController, previewHost as NSViewController] {
        let item = NSSplitViewItem(viewController: controller)
        item.minimumThickness = 240
        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(item)
      }
      setMode(mode, editing: editor.commands)
    }

    required init?(coder: NSCoder) { nil }

    func setMode(_ next: WorkspaceMode, editing: EditorCommandController) {
      guard mode != next else { return }
      if mode == .split, next != .split {
        let available = splitView.bounds.width - splitView.dividerThickness
        let width = editorHost.view.frame.width
        if available > 0, width > 0 { lastSplitFraction = min(0.95, max(0.05, width / available)) }
      }
      if next == .preview, let window = view.window,
        let responder = window.firstResponder as? NSView,
        responder.isDescendant(of: editorHost.view)
      {
        window.makeFirstResponder(nil)
      }
      // Expand the destination before collapsing the other pane, so there is always
      // one content item present. No animation is required for this writing mode.
      if next != .preview { splitViewItems[0].isCollapsed = false }
      if next != .editor { splitViewItems[1].isCollapsed = false }
      if next == .preview { splitViewItems[0].isCollapsed = true }
      if next == .editor { splitViewItems[1].isCollapsed = true }
      let previous = mode
      mode = next
      if next == .split {
        view.layoutSubtreeIfNeeded()
        splitView.setPosition(
          (splitView.bounds.width - splitView.dividerThickness) * lastSplitFraction,
          ofDividerAt: 0)
      }
      if previous == .preview, next != .preview, let editor = editing.coordinator?.editor {
        view.window?.makeFirstResponder(editor)
      }
    }
  }

  struct EditorSurface: View {
    let document: MarkdownDocument
    let preferences: AppPreferences
    let commands: EditorCommandController
    let undoManager: UndoManager?
    var body: some View {
      NativeMarkdownEditor(
        document: document, fontName: preferences.editorFontName,
        fontSize: preferences.editorFontSize, behavior: preferences.editorBehavior,
        strikethroughEnabled: preferences.strikethrough, commands: commands,
        hostUndoManager: undoManager
      )
    }
  }

  struct PreviewSurface: View {
    let html: String
    let directory: URL?
    let remoteImages: Bool
    @Binding var error: String?
    var body: some View {
      NativeMarkdownPreview(html: html, directory: directory, remoteImages: remoteImages) {
        error = $0
      }
    }
  }
}
