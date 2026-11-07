import AppKit
import SwiftUI

enum SettingsWindowLayout {
  // Shared with the SwiftUI form's measured minimum layout.
  static let minimumContentSize = CGSize(width: 740, height: 573)
  static let sidebarWidth: CGFloat = 232

  static func constrainedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
    var result = frame
    result.origin.x = max(visibleFrame.minX, min(frame.minX, visibleFrame.maxX - frame.width))
    result.origin.y = min(visibleFrame.maxY - frame.height, max(frame.minY, visibleFrame.minY))
    return result
  }
}

/// A single retained native window; closing it preserves navigation and its saved frame.
@MainActor
public final class SettingsWindowController: NSWindowController {
  private let navigation: SettingsNavigation

  public init(
    preferences: AppPreferences,
    frameAutosaveName: NSWindow.FrameAutosaveName? = "SnowfolioSettingsWindow"
  ) {
    let navigation = SettingsNavigation()
    self.navigation = navigation
    let host = NSHostingController(
      rootView: SnowfolioSettingsView(
        preferences: preferences, navigation: navigation))
    // Hosting can report zero before its first layout. Its declared minimum is
    // a lower bound even then, so centering never uses a zero-sized window.
    let measuredSize = host.sizeThatFits(in: .zero)
    let minimumSize = SettingsWindowLayout.minimumContentSize
    let contentSize = CGSize(
      width: max(minimumSize.width, measuredSize.width),
      height: max(minimumSize.height, measuredSize.height))
    // NSWindow owns sizing; a transient hosting measurement must not shrink it.
    host.sizingOptions = []
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.contentViewController = host
    window.title = navigation.location.pane.title
    window.identifier = NSUserInterfaceItemIdentifier("snowfolioSettings")
    window.toolbarStyle = .unified
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.contentMinSize = minimumSize
    window.setContentSize(contentSize)
    host.view.layoutSubtreeIfNeeded()
    window.center()
    if let frameAutosaveName { window.setFrameAutosaveName(frameAutosaveName) }
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(preferences:)") }

  public override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    if let window {
      window.contentView?.layoutSubtreeIfNeeded()
      if let screen = window.screen {
        window.setFrame(
          SettingsWindowLayout.constrainedFrame(window.frame, to: screen.visibleFrame),
          display: false)
      }
    }
    window?.makeKeyAndOrderFront(sender)
    NSApp.activate()
  }
}

public struct SnowfolioSettingsCommands: Commands {
  private let preferences: AppPreferences
  @State private var controller: SettingsWindowController?

  public init(preferences: AppPreferences) { self.preferences = preferences }

  public var body: some Commands {
    CommandGroup(replacing: .appSettings) {
      Button("Settings…") {
        if controller == nil { controller = SettingsWindowController(preferences: preferences) }
        controller?.showWindow(nil)
      }
      .keyboardShortcut(",", modifiers: .command)
    }
  }
}
