import AppKit
import SwiftUI

/// A short-lived placement request, not a second document/window store. The native
/// document host still creates the model, file coordination, window and undo manager.
@MainActor
final class DocumentTabPlacement {
  static let shared = DocumentTabPlacement()

  @MainActor
  private final class Request {
    let anchor: DocumentWindowAnchor
    let existingWindows: Set<ObjectIdentifier>
    let deadline: ContinuousClock.Instant

    init(anchor: NSWindow, existingWindows: [NSWindow], now: ContinuousClock.Instant) {
      self.anchor = DocumentWindowAnchor(anchor)
      self.existingWindows = Set((existingWindows + [anchor]).map(ObjectIdentifier.init))
      deadline = now.advanced(by: .seconds(5))
    }
  }

  private var requests: [Request] = []

  func request(
    from anchor: NSWindow?, existingWindows: [NSWindow],
    now: ContinuousClock.Instant = .now
  ) {
    requests.removeAll { $0.anchor.window == nil || $0.deadline <= now }
    guard let anchor, anchor.tabbingIdentifier == DocumentWindowPolicy.tabbingIdentifier else {
      return
    }
    requests.append(Request(anchor: anchor, existingWindows: existingWindows, now: now))
  }

  /// Called only for a document window by its bridge, after SwiftUI has attached it.
  @discardableResult
  func place(_ window: NSWindow, now: ContinuousClock.Instant = .now) -> Bool {
    requests.removeAll { $0.anchor.window == nil || $0.deadline <= now }
    guard window.tabbingIdentifier == DocumentWindowPolicy.tabbingIdentifier,
      let index = requests.firstIndex(where: {
        !$0.existingWindows.contains(ObjectIdentifier(window))
      }),
      let anchor = requests[index].anchor.window
    else { return false }
    requests.remove(at: index)
    if window.tabGroup !== anchor.tabGroup {
      anchor.addTabbedWindow(window, ordered: .above)
    }
    anchor.tabGroup?.selectedWindow = window
    return true
  }
}

public struct DocumentTabCommands: Commands {
  @Environment(\.newDocument) private var newDocument

  public init() {}

  public var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("New Tab") {
        DocumentTabPlacement.shared.request(from: NSApp.keyWindow, existingWindows: NSApp.windows)
        // Unlike the generic newDocument action, the native tab action requests a
        // fresh untitled document even when a blank document is already open.
        if !NSApp.sendAction(#selector(NSResponder.newWindowForTab(_:)), to: nil, from: nil) {
          newDocument(contentType: MarkdownDocument.markdownType)
        }
      }
      .keyboardShortcut("t", modifiers: .command)
      .accessibilityIdentifier("newDocumentTab")
    }
  }
}
