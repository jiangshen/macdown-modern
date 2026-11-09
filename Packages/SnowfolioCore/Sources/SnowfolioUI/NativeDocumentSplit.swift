import AppKit
import MarkdownCore
import RenderingCore
import SwiftUI

/// Pane visibility must not destroy NSTextView: its native undo actions and input
/// context belong to the document's lifetime, including time spent in preview mode.
struct NativeDocumentSplit: NSViewControllerRepresentable {
  let document: MarkdownDocument
  let preferences: AppPreferences
  let editing: EditorCommandController
  let html: String
  var syntax: MarkdownSyntax? = nil
  var syntaxRevision: UInt64? = nil
  var revision: UInt64? = nil
  var callouts: CalloutEditorController? = nil
  let mode: WorkspaceMode
  @Binding var previewError: String?
  var openDroppedFiles: (@MainActor ([URL]) -> Bool)? = nil
  @Binding var editorSelection: Data?
  var hostUndoManager: UndoManager? = nil
  var scrolling: DocumentScrollCoordinator? = nil
  var zoomScale: Double = 1
  var statistics: DocumentWritingStatistics? = nil
  var sourceViewportStorage: Binding<Data?> = .constant(nil)
  var previewViewportStorage: Binding<Data?> = .constant(nil)
  @Environment(\.undoManager) private var undoManager

  func makeNSViewController(context: Context) -> Controller {
    configureScrolling()
    return Controller(
      editor: editorSurface, preview: previewSurface, mode: mode,
      editorOnRight: preferences.editorOnRight)
  }

  func updateNSViewController(_ controller: Controller, context: Context) {
    configureScrolling()
    controller.editorHost.rootView = editorSurface
    controller.previewHost.rootView = previewSurface
    controller.setEditorOnRight(preferences.editorOnRight)
    controller.setMode(mode, editing: editing)
  }

  private func configureScrolling() {
    scrolling?.configure(
      document: document, linked: preferences.synchronizedScrolling && mode == .split,
      mode: mode, sourceStorage: sourceViewportStorage, previewStorage: previewViewportStorage)
  }

  private var editorSurface: EditorSurface {
    EditorSurface(
      document: document, preferences: preferences, commands: editing,
      undoManager: hostUndoManager ?? undoManager,
      syntax: syntax, syntaxRevision: syntaxRevision, openDroppedFiles: openDroppedFiles,
      editorSelection: $editorSelection, scrolling: scrolling, zoomScale: zoomScale)
  }

  private var previewSurface: PreviewSurface {
    let location = preferences.assetFolder.location(for: document.fileURL)
    return PreviewSurface(
      html: html, directory: location.directory, assetAccess: location.access,
      remoteImages: preferences.remoteImages, style: preferences.documentStyle, revision: revision,
      callouts: callouts, openDroppedFiles: openDroppedFiles, scrolling: scrolling,
      zoomScale: DocumentZoomController.previewScale(
        workspace: zoomScale,
        baseFontSize: preferences.editorFontSize,
        followsEditor: preferences.previewFollowsEditorFont),
      statistics: statistics, error: $previewError
    )
  }

  final class Controller: NSSplitViewController {
    let editorHost: NSHostingController<EditorSurface>
    let previewHost: NSHostingController<PreviewSurface>
    private(set) var mode: WorkspaceMode
    private(set) var editorOnRight: Bool
    private let editorItem: NSSplitViewItem
    private let previewItem: NSSplitViewItem
    private var lastSplitFraction: CGFloat = 0.5

    init(
      editor: EditorSurface, preview: PreviewSurface, mode: WorkspaceMode,
      editorOnRight: Bool = false
    ) {
      let sourceHost = NSHostingController(rootView: editor)
      let renderedHost = NSHostingController(rootView: preview)
      editorHost = sourceHost
      previewHost = renderedHost
      editorItem = NSSplitViewItem(viewController: sourceHost)
      previewItem = NSSplitViewItem(viewController: renderedHost)
      self.editorOnRight = editorOnRight
      self.mode = .split
      super.init(nibName: nil, bundle: nil)
      splitView.setAccessibilityIdentifier("documentPaneSplit")
      splitView.isVertical = true
      splitView.dividerStyle = .thin
      for item in editorOnRight ? [previewItem, editorItem] : [editorItem, previewItem] {
        item.minimumThickness = 240
        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(item)
      }
      setMode(mode, editing: editor.commands)
    }

    required init?(coder: NSCoder) { nil }

    private func rememberSplitFraction() {
      guard mode == .split else { return }
      let available = splitView.bounds.width - splitView.dividerThickness
      let width = editorHost.view.frame.width
      if available > 0, width > 0 { lastSplitFraction = min(0.95, max(0.05, width / available)) }
    }

    private func restoreSplitFraction() {
      guard mode == .split else { return }
      view.layoutSubtreeIfNeeded()
      let leadingFraction = editorOnRight ? 1 - lastSplitFraction : lastSplitFraction
      splitView.setPosition(
        (splitView.bounds.width - splitView.dividerThickness) * leadingFraction,
        ofDividerAt: 0)
    }

    func setEditorOnRight(_ next: Bool) {
      guard editorOnRight != next else { return }
      rememberSplitFraction()
      let window = view.window
      let responder = window?.firstResponder
      editorOnRight = next
      // Reorder the existing items/controllers, keeping their document views alive.
      splitViewItems = next ? [previewItem, editorItem] : [editorItem, previewItem]
      restoreSplitFraction()
      if let responder = responder as? NSView, !responder.isHiddenOrHasHiddenAncestor,
        responder.isDescendant(of: view), window?.firstResponder !== responder
      {
        window?.makeFirstResponder(responder)
      }
    }

    func setMode(_ next: WorkspaceMode, editing: EditorCommandController) {
      guard mode != next else { return }
      if mode == .split, next != .split { rememberSplitFraction() }
      var focusEditor = mode == .preview && next != .preview
      if let window = view.window, let responder = window.firstResponder as? NSView {
        let hidingFocusedPane =
          next == .preview && responder.isDescendant(of: editorHost.view)
          || next == .editor && responder.isDescendant(of: previewHost.view)
        if hidingFocusedPane {
          window.makeFirstResponder(nil)
          focusEditor = next != .preview
        }
      }
      // Expand the destination before collapsing the other pane, so there is always
      // one content item present. No animation is required for this writing mode.
      if next != .preview { editorItem.isCollapsed = false }
      if next != .editor { previewItem.isCollapsed = false }
      if next == .preview { editorItem.isCollapsed = true }
      if next == .editor { previewItem.isCollapsed = true }
      mode = next
      if next == .split { restoreSplitFraction() }
      if focusEditor, let editor = editing.coordinator?.editor {
        view.window?.makeFirstResponder(editor)
      }
    }
  }

  struct EditorSurface: View {
    let document: MarkdownDocument
    let preferences: AppPreferences
    let commands: EditorCommandController
    let undoManager: UndoManager?
    var syntax: MarkdownSyntax? = nil
    var syntaxRevision: UInt64? = nil
    var openDroppedFiles: (@MainActor ([URL]) -> Bool)? = nil
    @Binding var editorSelection: Data?
    var scrolling: DocumentScrollCoordinator? = nil
    var zoomScale: Double = 1
    var body: some View {
      NativeMarkdownEditor(
        document: document, fontName: preferences.editorFontName,
        fontSize: preferences.editorFontSize, layout: preferences.editorLayout,
        behavior: preferences.editorBehavior,
        strikethroughEnabled: preferences.strikethrough, commands: commands,
        hostUndoManager: undoManager, syntax: syntax, syntaxRevision: syntaxRevision,
        syntaxHighlighting: preferences.syntaxHighlighting, selectionStorage: $editorSelection,
        openDroppedFiles: openDroppedFiles, scrolling: scrolling, zoomScale: zoomScale,
        theme: preferences.editorThemes.theme
      )
      .task { await preferences.editorThemes.loadIfNeeded() }
    }
  }

  struct PreviewSurface: View {
    let html: String
    let directory: URL?
    var assetAccess: DocumentAssetAccess? = nil
    let remoteImages: Bool
    var style: DocumentStyle = .init()
    var revision: UInt64? = nil
    var callouts: CalloutEditorController? = nil
    var openDroppedFiles: (@MainActor ([URL]) -> Bool)? = nil
    var scrolling: DocumentScrollCoordinator? = nil
    var zoomScale: Double = 1
    var statistics: DocumentWritingStatistics? = nil
    @Binding var error: String?
    var body: some View {
      NativeMarkdownPreview(
        html: html, directory: directory, remoteImages: remoteImages, style: style,
        assetAccess: assetAccess,
        revision: revision, callouts: callouts, openDroppedFiles: openDroppedFiles,
        scrolling: scrolling, zoomScale: zoomScale, statistics: statistics
      ) {
        error = $0
      }
    }
  }
}
