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
