import AppKit
import XCTest

final class TerminalSettingsTests: XCTestCase {
  @MainActor
  func testCommandLineLocationChooserInstallationRemovalAndCollision() async throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let preserved = directory.appendingPathComponent("keep.md")
    let preservedBytes = Data("# Keep this document\r\n".utf8)
    try preservedBytes.write(to: preserved)
    let link = directory.appendingPathComponent("snowfolio")
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
    ]
    app.launch()
    defer { app.terminate() }
    defer {
      let hierarchy = XCTAttachment(string: app.debugDescription)
      hierarchy.name = "terminal-settings-final-hierarchy"
      hierarchy.lifetime = .keepAlways
      add(hierarchy)
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = "terminal-settings-final-state"
      image.lifetime = .keepAlways
      add(image)
    }
    let running = try XCTUnwrap(
      NSRunningApplication.runningApplications(withBundleIdentifier: "local.macdown.modern").first)
    let helper = try XCTUnwrap(running.bundleURL).appendingPathComponent(
      "Contents/Helpers/snowfolio")
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("shell install")
    let result = settings.outlines.firstMatch.staticTexts["Command-line tool"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let install = settings.buttons["installCommandLineTool"]
    let copy = settings.buttons["copyCommandLineTool"]
    XCTAssertTrue(install.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(settings.frame.contains(install.frame))
    XCTAssertTrue(settings.frame.contains(copy.frame))

    func expectStatus(_ expected: String) async {
      let status = settings.staticTexts["commandLineToolStatus"]
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          status.exists && (status.value as? String ?? status.label) == expected
        }, object: nil)
      let result = await XCTWaiter.fulfillment(of: [ready], timeout: 8)
      XCTAssertEqual(result, .completed, app.debugDescription)
    }
    func chooseLocation() {
      install.click()
      XCTAssertTrue(
        app.buttons["OKButton"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
      app.typeKey("g", modifierFlags: [.command, .shift])
      let path = app.textFields["PathTextField"].firstMatch
      XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
      path.click()
      app.typeKey("a", modifierFlags: .command)
      path.typeText(directory.path + "\n")
      app.buttons["OKButton"].firstMatch.click()
    }
    await expectStatus("Not installed")
    chooseLocation()
    await expectStatus("Installed")
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: link.path), helper.path)
    XCTAssertFalse(install.exists)
    XCTAssertTrue(settings.buttons["removeCommandLineTool"].exists)
    copy.click()
    let quotedLink = "'" + link.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    XCTAssertEqual(NSPasteboard.general.string(forType: .string), quotedLink)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "terminal-settings-installed-location"
    image.lifetime = .keepAlways
    add(image)
    settings.buttons["removeCommandLineTool"].click()
    await expectStatus("Not installed")
    XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
    XCTAssertEqual(try Data(contentsOf: preserved), preservedBytes)

    let occupiedBytes = Data("An unrelated user file\n".utf8)
    try occupiedBytes.write(to: link)
    chooseLocation()
    XCTAssertTrue(
      settings.staticTexts["commandLineToolMessage"].waitForExistence(timeout: 5),
      app.debugDescription)
    XCTAssertEqual(try Data(contentsOf: link), occupiedBytes)
    XCTAssertEqual(try Data(contentsOf: preserved), preservedBytes)
    XCTAssertFalse(settings.buttons["removeCommandLineTool"].exists)
    await expectStatus("Not installed")
  }
}
