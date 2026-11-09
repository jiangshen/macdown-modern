import XCTest

final class UpdateSettingsTests: XCTestCase {
  @MainActor
  func testDevelopmentUpdateControlsAndPrereleaseChoicePersistAcrossLaunches() async throws {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
    ]
    app.launch()
    defer { app.terminate() }
    func updates() -> XCUIElement {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["snowfolioSettings"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
      let search = settings.searchFields["settingsSearch"]
      search.click()
      app.typeKey("a", modifierFlags: .command)
      search.typeText("beta updates")
      let result = settings.outlines.firstMatch.staticTexts["Software Updates"].firstMatch
      XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
      result.click()
      return settings
    }
    func state(_ control: XCUIElement) throws -> String {
      let value: String
      if let number = control.value as? NSNumber {
        value = number.stringValue
      } else {
        value = try XCTUnwrap(control.value as? String)
      }
      XCTAssertTrue(["0", "1"].contains(value))
      return value
    }
    func capture(_ name: String) {
      let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      image.name = name
      image.lifetime = .keepAlways
      add(image)
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = name + "-hierarchy"
      tree.lifetime = .keepAlways
      add(tree)
    }
    app.menuBars.menuBarItems["Snowfolio"].click()
    let menuCheck = app.menuItems["Check for Updates…"].firstMatch
    XCTAssertTrue(menuCheck.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(menuCheck.isEnabled)
    app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    let settings = updates()
    let automatic = settings.switches["automaticUpdateChecks"].firstMatch
    let beta = settings.switches["includePreReleaseUpdates"].firstMatch
    let check = settings.buttons["checkForUpdates"].firstMatch
    XCTAssertTrue(beta.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(automatic.exists && check.exists)
    XCTAssertFalse(automatic.isEnabled)
    XCTAssertFalse(check.isEnabled)
    let status = settings.staticTexts["updateAvailabilityStatus"].firstMatch
    XCTAssertEqual(
      status.value as? String ?? status.label,
      "Automatic updates are off in development builds.")
    XCTAssertTrue(
      settings.frame.contains(status.frame), "The complete update explanation must be visible")
    XCTAssertTrue(settings.frame.contains(beta.frame))
    XCTAssertTrue(settings.frame.contains(check.frame))
    let initial = try state(beta)
    beta.click()
    let changed = try state(beta)
    XCTAssertNotEqual(initial, changed)
    capture("update-settings-development-and-beta-choice")
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
    app.launch()
    let restored = updates().switches["includePreReleaseUpdates"].firstMatch
    XCTAssertTrue(restored.waitForExistence(timeout: 5))
    XCTAssertEqual(try state(restored), changed)
    capture("update-settings-beta-choice-restored")
    restored.click()
    XCTAssertEqual(try state(restored), initial)
  }
}
