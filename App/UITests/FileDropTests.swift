#if NATIVE_DOCUMENT_HOST
  import AppKit
  import XCTest

  final class FileDropTests: XCTestCase {
    @MainActor
    func testFinderMultiFileDropOpensTabsAndReusesDocumentsWithoutChangingBytes() async throws {
      continueAfterFailure = false
      let manager = FileManager.default
      let directory = manager.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("Snowfolio-Drop-" + UUID().uuidString)
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? manager.removeItem(at: directory) }
      let first = directory.appendingPathComponent("First 🧊.md")
      let second = directory.appendingPathComponent("Second.md")
      let firstText = "# First drop\r\n中文 e\u{301}\r\n"
      let secondText = "# Second drop\r\nIndependent notebook.\r\n"
      let firstBytes =
        Data([0xff, 0xfe]) + (try XCTUnwrap(firstText.data(using: .utf16LittleEndian)))
      let secondBytes = Data([0xef, 0xbb, 0xbf]) + Data(secondText.utf8)
      try firstBytes.write(to: first)
      try secondBytes.write(to: second)
      let app = XCUIApplication()
      let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
      app.launchArguments = [
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
        "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "YES",
        "-editorSyntaxHighlighting", "NO",
      ]
      app.launchEnvironment["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE"] = "1"
      app.launch()
      defer { app.terminate() }
      func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        for (target, suffix) in [(app, "app"), (finder, "finder")] {
          let tree = XCTAttachment(string: target.debugDescription)
          tree.name = name + "-" + suffix
          tree.lifetime = .keepAlways
          add(tree)
        }
      }
      func selectDocument(_ title: String) {
        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        let item = app.menuItems[title].firstMatch
        let appeared = item.waitForExistence(timeout: 5)
        if !appeared { capture("finder-drop-window-menu-failure") }
        XCTAssertTrue(appeared, app.debugDescription)
        item.click()
      }
      func expectSource(_ source: String) async {
        let editor = app.windows.firstMatch.textViews["markdownSourceEditor"].firstMatch
        let ready = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in editor.exists && editor.value as? String == source },
          object: nil)
        let result = await XCTWaiter.fulfillment(of: [ready], timeout: 8)
        if result != .completed { capture("finder-drop-source-failure") }
        XCTAssertEqual(result, .completed, app.debugDescription)
      }
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: 5))
      let originalEditor = window.textViews["markdownSourceEditor"].firstMatch
      XCTAssertTrue(originalEditor.waitForExistence(timeout: 5))
      originalEditor.click()
      originalEditor.typeText("Anchor stays in its own tab.")
      XCTAssertTrue(NSWorkspace.shared.open(directory))
      finder.activate()
      let finderWindow = finder.windows.matching(
        NSPredicate(format: "title == %@", directory.lastPathComponent)
      ).firstMatch
      let folderAppeared = finderWindow.waitForExistence(timeout: 5)
      if !folderAppeared { capture("finder-drop-folder-window-failure") }
      XCTAssertTrue(folderAppeared, finder.debugDescription)
      finder.typeKey("1", modifierFlags: .command)
      let icon = finder.descendants(matching: .any).matching(
        NSPredicate(
          format: "title == %@ OR label == %@", first.lastPathComponent, first.lastPathComponent)
      ).firstMatch
      let appeared = icon.waitForExistence(timeout: 8)
      if !appeared { capture("finder-drop-file-icon-failure") }
      XCTAssertTrue(appeared, finder.debugDescription)
      func dragBatch() {
        finder.activate()
        icon.click()
        finder.typeKey("a", modifierFlags: .command)
        let target = app.buttons["openMarkdownFiles"].firstMatch
        XCTAssertTrue(target.exists, app.debugDescription)
        let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
        // A real mouse drag can reach the exposed sidebar below the Finder window.
        // The cross-platform press API emits touch events rather than mouse input.
        XCTAssertFalse(finderWindow.frame.contains(point), "Finder covers the drop destination")
        icon.click(
          forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 1)
      }
      dragBatch()
      capture("finder-drop-initial-gesture")
      selectDocument(first.lastPathComponent)
      await expectSource(firstText)
      selectDocument(second.lastPathComponent)
      await expectSource(secondText)
      XCTAssertEqual(try Data(contentsOf: first), firstBytes)
      XCTAssertEqual(try Data(contentsOf: second), secondBytes)
      selectDocument("Untitled")
      await expectSource("Anchor stays in its own tab.")
      selectDocument(first.lastPathComponent)
      let editor = app.windows.firstMatch.textViews["markdownSourceEditor"].firstMatch
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      editor.typeText("IndependentEdit")
      await expectSource(firstText + "IndependentEdit")
      dragBatch()
      for name in [first.lastPathComponent, second.lastPathComponent] {
        app.activate()
        app.menuBars.menuBarItems["Window"].click()
        XCTAssertEqual(app.menuItems.matching(NSPredicate(format: "title == %@", name)).count, 1)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
      }
      selectDocument(second.lastPathComponent)
      await expectSource(secondText)
      selectDocument(first.lastPathComponent)
      await expectSource(firstText + "IndependentEdit")
      app.typeKey("z", modifierFlags: .command)
      await expectSource(firstText)
      app.typeKey("s", modifierFlags: .command)
      XCTAssertEqual(try Data(contentsOf: first), firstBytes)
      XCTAssertEqual(try Data(contentsOf: second), secondBytes)
      let tabs = app.windows.firstMatch.tabGroups.firstMatch
      XCTAssertTrue(tabs.exists, app.debugDescription)
      for name in ["Untitled", first.lastPathComponent, second.lastPathComponent] {
        XCTAssertTrue(
          tabs.descendants(matching: .any).matching(NSPredicate(format: "title == %@", name))
            .firstMatch.exists, app.debugDescription)
      }
      capture("finder-multi-file-tabs-and-independent-undo")
    }
  }
#endif
