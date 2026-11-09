#if NATIVE_DOCUMENT_HOST
  import Foundation
  import XCTest

  final class PluginTests: XCTestCase {
    @MainActor
    func testExplicitPluginRunRetainsStateAndPreservesNativeUndoAndEncodedSave() async throws {
      continueAfterFailure = false
      let manager = FileManager.default
      let root = manager.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent(UUID().uuidString)
      try manager.createDirectory(at: root, withIntermediateDirectories: true)
      defer { try? manager.removeItem(at: root) }
      let folder = root.appendingPathComponent("PlugIns")
      try manager.createDirectory(at: folder, withIntermediateDirectories: true)
      let fixture = try XCTUnwrap(
        Bundle(for: Self.self).url(forResource: "SnowfolioPluginFixture", withExtension: "bundle"))
      try manager.copyItem(at: fixture, to: folder.appendingPathComponent("Local Fixture.plugin"))
      try Data("invalid bundle".utf8).write(to: folder.appendingPathComponent("Broken.plugin"))
      try makeIntelMetadata(in: folder)
      let events = root.appendingPathComponent("events.txt")
      let file = root.appendingPathComponent("plugin-encoding.md")
      let source = "# Native plug-in\r\n中文 👩‍💻 e\u{301}\r\n"
      let bom = Data([0xff, 0xfe])
      func encoded(_ text: String) throws -> Data {
        bom + (try XCTUnwrap(text.data(using: .utf16LittleEndian)))
      }
      let bytes = try encoded(source)
      try bytes.write(to: file)
      let app = XCUIApplication()
      app.launchArguments = [
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
        "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
      ]
      app.launchEnvironment["SNOWFOLIO_TEST_PLUGIN_FOLDER"] = folder.path
      app.launchEnvironment["SNOWFOLIO_PLUGIN_FIXTURE_EVENTS"] = events.path
      app.launch()
      defer { app.terminate() }
      app.typeKey("o", modifierFlags: .command)
      XCTAssertTrue(
        app.descendants(matching: .any)["open-panel"].firstMatch.waitForExistence(timeout: 5))
      app.typeKey("g", modifierFlags: [.command, .shift])
      let path = app.textFields["PathTextField"].firstMatch
      XCTAssertTrue(path.waitForExistence(timeout: 5))
      path.click()
      app.typeKey("a", modifierFlags: .command)
      path.typeText(file.path + "\n")
      app.buttons["OKButton"].firstMatch.click()
      let editor = app.windows[file.lastPathComponent].firstMatch
        .textViews["markdownSourceEditor"].firstMatch
      func expectSource(_ expected: String) async {
        let ready = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in editor.exists && editor.value as? String == expected },
          object: nil)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 8)
        XCTAssertEqual(result, .completed, app.debugDescription)
      }
      func menu() { app.menuBars.menuBarItems["Plug-ins"].click() }
      func select(_ title: String) {
        menu()
        let item = app.menuItems[title].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(item.isEnabled)
        item.click()
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
      await expectSource(source)
      menu()
      XCTAssertTrue(app.menuItems["Local Fixture"].firstMatch.exists)
      XCTAssertTrue(app.menuItems["Intel Fixture — Intel only"].firstMatch.exists)
      XCTAssertFalse(app.menuItems["Intel Fixture — Intel only"].firstMatch.isEnabled)
      XCTAssertTrue(app.menuItems["Broken — Invalid plug-in"].firstMatch.exists)
      XCTAssertFalse(app.menuItems["Broken — Invalid plug-in"].firstMatch.isEnabled)
      XCTAssertFalse(manager.fileExists(atPath: events.path))
      capture("plugin-metadata-inventory")
      app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
      select("Local Fixture")
      let cancel = app.buttons["cancelPluginRun"].firstMatch
      XCTAssertTrue(cancel.waitForExistence(timeout: 5))
      cancel.click()
      await expectSource(source)
      XCTAssertFalse(manager.fileExists(atPath: events.path))
      XCTAssertEqual(try Data(contentsOf: file), bytes)
      select("Refresh Plug-ins")
      XCTAssertFalse(manager.fileExists(atPath: events.path))
      select("Local Fixture")
      let confirm = app.buttons["confirmPluginRun"].firstMatch
      XCTAssertTrue(confirm.waitForExistence(timeout: 5))
      capture("plugin-first-run-confirmation")
      confirm.click()
      let once = source + "\r\nPlug-in run 1 🧊"
      await expectSource(once)
      select("Refresh Plug-ins")
      select("Glacial Fixture")
      let twice = once + "\r\nPlug-in run 2 🧊"
      await expectSource(twice)
      XCTAssertFalse(app.buttons["confirmPluginRun"].firstMatch.exists)
      XCTAssertEqual(
        try String(contentsOf: events, encoding: .utf8),
        "construct\nname\ninitialize\nrun:1\nrun:2\n")
      editor.click()
      app.typeKey("z", modifierFlags: .command)
      await expectSource(once)
      app.typeKey("z", modifierFlags: [.command, .shift])
      await expectSource(twice)
      app.typeKey("s", modifierFlags: .command)
      let expectedBytes = try encoded(twice)
      let saved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == expectedBytes },
        object: nil)
      let savedResult = await XCTWaiter.fulfillment(of: [saved], timeout: 8)
      XCTAssertEqual(savedResult, .completed)
      capture("plugin-retained-state-native-undo-encoded-save")
      select("Glacial Fixture")
      let dismiss = app.buttons["dismissPluginError"].firstMatch
      XCTAssertTrue(dismiss.waitForExistence(timeout: 5), app.debugDescription)
      capture("plugin-false-result-error")
      dismiss.click()
      await expectSource(twice)
      XCTAssertEqual(try Data(contentsOf: file), expectedBytes)
      XCTAssertEqual(
        try String(contentsOf: events, encoding: .utf8),
        "construct\nname\ninitialize\nrun:1\nrun:2\nrun:3\n")
    }

    private func makeIntelMetadata(in folder: URL) throws {
      let contents = folder.appendingPathComponent("Intel Fixture.plugin/Contents")
      let binaries = contents.appendingPathComponent("MacOS")
      try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
      let info: [String: Any] = [
        "CFBundlePackageType": "BNDL", "CFBundleExecutable": "fixture",
        "CFBundleIdentifier": "local.snowfolio.tests.intel-metadata",
        "NSPrincipalClass": "NeverLoadedIntelFixture",
      ]
      try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
      var data = Data()
      for word: UInt32 in [0xfeed_facf, 0x0100_0007, 0, 8, 0, 0, 0, 0] {
        var value = word.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
      }
      try data.write(to: binaries.appendingPathComponent("fixture"))
    }
  }
#endif
