import AppKit
import SwiftUI

@MainActor
enum NativeDocumentPreferences {
  static let shared = AppPreferences()
}

/// Workspace sizing uses the same minimum/ideal proposal as the current app;
/// the hosting controller measures that content before the native window is sized.
@MainActor
final class NativeDocumentWindowController: NSWindowController {
  init(document: NativeMarkdownDocument, preferences: AppPreferences, state: DocumentWorkspaceState)
  {
    let content = NativeDocumentWorkspace(
      document: document.markdownDocument, preferences: preferences, state: state,
      hostUndoManager: document.undoManager,
      openFile: { url in
        _ = try await NSDocumentController.shared.openDocument(withContentsOf: url, display: true)
      }
    )
    .frame(minWidth: 720, idealWidth: 1120, minHeight: 360, idealHeight: 640)
    let hosting = NSHostingController(rootView: content)
    // NSDocument supplies title/proxy/edited state; SwiftUI supplies its real toolbar.
    hosting.sceneBridgingOptions = .toolbars
    // Keep the minimum attached to the live SwiftUI layout. Disabling sizing
    // propagation clears the native minimum when the content joins its window.
    hosting.sizingOptions = [.minSize]
    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.contentViewController = hosting
    window.toolbarStyle = .unified
    // NavigationSplitView needs its window before it can measure the workspace.
    // Measuring before attachment returned zero and centered a growing window
    // partly outside the display.
    hosting.view.layoutSubtreeIfNeeded()
    let available = window.screen.map { window.contentRect(forFrameRect: $0.visibleFrame).size }
    let proposal = NSSize(
      width: min(1120, available?.width ?? 1120),
      height: min(640, available?.height ?? 640))
    let measured = hosting.sizeThatFits(in: proposal)
    let minimum = hosting.view.fittingSize
    window.setContentSize(
      NSSize(
        width: ceil(max(minimum.width, measured.width)),
        height: ceil(max(minimum.height, measured.height))))
    DocumentWindowPolicy.configure(window, preferTabs: preferences.preferDocumentTabs)
    window.center()
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(document:preferences:state:)") }
}
