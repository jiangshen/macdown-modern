import AppKit
import SwiftUI

/// A single retained native window; closing it preserves navigation and its saved frame.
@MainActor
public final class SettingsWindowController: NSWindowController {
  private let navigation: SettingsNavigation

  public init(preferences: AppPreferences) {
    let navigation = SettingsNavigation()
    self.navigation = navigation
    let host = NSHostingController(
      rootView: SnowfolioSettingsView(
        preferences: preferences, navigation: navigation))
    // fittingSize can still be zero before the first hosting layout. Measure
    // SwiftUI explicitly so centering uses the full content size on a cold launch.
    let contentSize = host.sizeThatFits(in: .zero)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.contentViewController = host
    window.title = "Settings"
    window.identifier = NSUserInterfaceItemIdentifier("snowfolioSettings")
    window.toolbarStyle = .unified
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 740, height: 573)
    host.view.layoutSubtreeIfNeeded()
    window.center()
    window.setFrameAutosaveName("SnowfolioSettingsWindow")
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(preferences:)") }

  public override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
    if let window {
      window.contentView?.layoutSubtreeIfNeeded()
      window.setFrame(window.constrainFrameRect(window.frame, to: window.screen), display: false)
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
