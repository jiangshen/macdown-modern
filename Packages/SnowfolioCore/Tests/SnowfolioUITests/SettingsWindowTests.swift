import AppKit
import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Settings window placement", .serialized, NativeUIExclusive())
@MainActor
struct SettingsWindowTests {
  @Test("A cold Settings host has its full minimum width before it is shown")
  func coldWindowSize() throws {
    _ = NSApplication.shared
    let domain = "SettingsWindowTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let controller = SettingsWindowController(preferences: preferences, frameAutosaveName: nil)
    let window = try #require(controller.window)
    defer { window.close() }
    #expect(!window.isVisible)
    #expect(window.frame.width >= SettingsWindowLayout.minimumContentSize.width)
    #expect(window.frame.height >= SettingsWindowLayout.minimumContentSize.height)
  }

  @Test("Visible Settings scroll regions remain inside the window")
  func contentFitsWindow() async throws {
    _ = NSApplication.shared
    let domain = "SettingsContentBounds." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let controller = SettingsWindowController(preferences: preferences, frameAutosaveName: nil)
    let window = try #require(controller.window)
    window.animationBehavior = .none
    window.orderFront(nil)
    defer { window.close() }
    let root = try #require(window.contentView)
    func scrolls(in view: NSView) -> [NSScrollView] {
      (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrolls)
    }
    var regions: [NSScrollView] = []
    for _ in 0..<100 {
      root.layoutSubtreeIfNeeded()
      regions = scrolls(in: root).filter { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.height > 0 }
      if window.toolbar != nil && regions.count >= 2 { break }
      try await Task.sleep(for: .milliseconds(25))
    }
    #expect(window.toolbar != nil)
    #expect(regions.count >= 2)
    // Full-size content intentionally extends behind the unified toolbar.
    // Its scroll wrapper may fill that area, but must never pass the bottom
    // or any other edge of the actual window content.
    let contentBounds = root.convert(root.bounds, to: nil)
    for scroll in regions {
      let frame = scroll.convert(scroll.bounds, to: nil)
      #expect(
        contentBounds.insetBy(dx: -1, dy: -1).contains(frame),
        "Scroll region \(frame) exceeds full-size window content \(contentBounds)")
    }
  }

  @Test("Offscreen and disconnected-display positions fit the current display")
  func displayBounds() {
    let smallDisplay = CGRect(x: 0, y: 40, width: 1024, height: 700)
    let firstOpenFailure = CGRect(x: 511, y: 0, width: 740, height: 625)
    #expect(
      smallDisplay.contains(
        SettingsWindowLayout.constrainedFrame(firstOpenFailure, to: smallDisplay)))
    let leftDisplay = CGRect(x: -1280, y: -100, width: 1280, height: 900)
    #expect(
      leftDisplay.contains(SettingsWindowLayout.constrainedFrame(firstOpenFailure, to: leftDisplay))
    )
    let normal = CGRect(x: 100, y: 70, width: 740, height: 625)
    #expect(SettingsWindowLayout.constrainedFrame(normal, to: smallDisplay) == normal)
  }
}
