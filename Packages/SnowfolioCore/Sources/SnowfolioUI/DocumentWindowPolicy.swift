import AppKit

/// Configure the native document window without replacing its host-owned delegate,
/// restoration class, identifier, close validation, or document/undo ownership.
@MainActor
enum DocumentWindowPolicy {
  static let tabbingIdentifier = "local.macdown.modern.documents"

  static func configure(_ window: NSWindow, preferTabs: Bool) {
    if window.tabbingIdentifier != tabbingIdentifier {
      window.tabbingIdentifier = tabbingIdentifier
    }
    let mode: NSWindow.TabbingMode = preferTabs ? .preferred : .automatic
    if window.tabbingMode != mode { window.tabbingMode = mode }
  }
}
