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
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: host.view.fittingSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.contentViewController = host
    window.title = "Settings"
    window.identifier = NSUserInterfaceItemIdentifier("snowfolioSettings")
    window.toolbarStyle = .unified
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    window.contentMinSize = NSSize(width: 740, height: 573)
    window.center()
    window.setFrameAutosaveName("SnowfolioSettingsWindow")
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(preferences:)") }

  public override func showWindow(_ sender: Any?) {
    super.showWindow(sender)
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
