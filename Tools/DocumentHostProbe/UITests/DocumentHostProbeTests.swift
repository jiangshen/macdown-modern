import AppKit
import Synchronization
import XCTest

final class DocumentHostProbeTests: XCTestCase {
  @MainActor
  private func launch(environment: [String: String] = [:]) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
    ]
    #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
      app.launchEnvironment["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE"] = "1"
    #endif
    #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
      app.launchArguments += [
        "-editorOnRight", "NO", "-markdownManualRender", "NO", "-readingStyleSelection",
        "snowfolio",
      ]
    #endif
    app.launchEnvironment.merge(environment) { _, supplied in supplied }
    app.launch()
    return app
  }

  @MainActor
  private func open(_ file: URL, in app: XCUIApplication) -> XCUIElement {
    app.typeKey("o", modifierFlags: .command)
    XCTAssertTrue(
      app.descendants(matching: .any)["open-panel"].firstMatch.waitForExistence(timeout: 5))
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5))
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(file.path + "\n")
    let button = app.buttons["OKButton"].firstMatch
    XCTAssertTrue(button.waitForExistence(timeout: 5))
    button.click()
    #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
      let editor = app.textViews["markdownSourceEditor"].firstMatch
    #else
      let editor = app.textViews["stockDocumentEditor"].firstMatch
    #endif
    XCTAssertTrue(editor.waitForExistence(timeout: 8), app.debugDescription)
    return editor
  }

  @MainActor
  private func fixture(inUserFolder: Bool = false) throws -> URL {
    let parent =
      inUserFolder
      ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Snowfolio Document Host Fixtures", isDirectory: true)
      : FileManager.default.temporaryDirectory
    let directory = parent.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("stock-document.txt")
    try Data("Stock host 中文 👩‍💻\n".utf8).write(to: file)
    return file
  }

  @MainActor
  private func expectBytes(_ bytes: Data, at file: URL, timeout: TimeInterval) {
    let checkpoint = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == bytes }, object: nil)
    XCTAssertEqual(XCTWaiter().wait(for: [checkpoint], timeout: timeout), .completed)
  }

  private final class WriteState: Sendable {
    let result = Mutex<Result<Void, Error>?>(nil)
  }

  @MainActor
  private func replaceExternally(_ data: Data, at file: URL, coordinated: Bool) throws {
    let state = WriteState()
    let completed = XCTestExpectation(description: "Stock probe external write")
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    let began = ProcessInfo.processInfo.systemUptime
    queue.addOperation {
      let result = Result<Void, Error> {
        if coordinated {
          var coordinationError: NSError?
          var writeError: Error?
          NSFileCoordinator().coordinate(
            writingItemAt: file, options: .forReplacing, error: &coordinationError
          ) { destination in
            do { try data.write(to: destination, options: .atomic) } catch { writeError = error }
          }
          if let coordinationError { throw coordinationError }
          if let writeError { throw writeError }
        } else {
          try data.write(to: file, options: .atomic)
        }
      }
      state.result.withLock { $0 = result }
      completed.fulfill()
    }
    let outcome = XCTWaiter().wait(for: [completed], timeout: 8)
    let observation = XCTAttachment(
      string:
        "coordinated=\(coordinated); writer=\(outcome.rawValue); elapsed=\(ProcessInfo.processInfo.systemUptime - began); canonicalPath=\(file.path == file.resolvingSymlinksInPath().path)"
    )
    observation.name = "stock-external-writer"
    observation.lifetime = .keepAlways
    add(observation)
    XCTAssertEqual(outcome, .completed)
    try XCTUnwrap(state.result.withLock { $0 }).get()
  }

  @MainActor
  func testCleanExternalReloadWithoutEditing() throws {
    try checkReload(afterAutosave: false)
  }

  @MainActor
  func testCleanExternalReloadAfterAutosave() throws {
    try checkReload(afterAutosave: true)
  }

  @MainActor
  func testCleanCoordinatedReloadAfterAutosaveInTemporaryFolder() throws {
    try checkReload(afterAutosave: true, coordinated: true)
  }

  @MainActor
  func testCleanCoordinatedReloadAfterAutosaveInUserFolder() throws {
    try checkReload(afterAutosave: true, coordinated: true, inUserFolder: true)
  }

  @MainActor
  private func checkReload(
    afterAutosave: Bool, coordinated: Bool = false, inUserFolder: Bool = false
  ) throws {
    let file = try fixture(inUserFolder: inUserFolder)
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let original = try String(contentsOf: file, encoding: .utf8)
    let app = launch()
    defer { app.terminate() }
    let editor = open(file, in: app)
    XCTAssertEqual(editor.value as? String, original)
    let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
    if afterAutosave {
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      editor.typeText("Autosave checkpoint")
      XCTAssertEqual(editor.value as? String, original + "Autosave checkpoint")
      finder.activate()
      expectBytes(Data((original + "Autosave checkpoint").utf8), at: file, timeout: 35)
      app.activate()
    }
    app.typeKey("s", modifierFlags: .command)
    finder.activate()
    let external = "Externally replaced stock document 中文 👩‍💻\n"
    let bytes = Data(external.utf8)
    try replaceExternally(bytes, at: file, coordinated: coordinated)
    app.activate()
    let reloaded = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in editor.value as? String == external }, object: nil)
    let outcome = XCTWaiter().wait(for: [reloaded], timeout: 8)
    let observation = XCTAttachment(
      string:
        "afterAutosave=\(afterAutosave); coordinated=\(coordinated); userFolder=\(inUserFolder); reload=\(outcome.rawValue); externalBytesRetained=\((try? Data(contentsOf: file)) == bytes)\n"
        + app.debugDescription)
    observation.name = "stock-document-reload"
    observation.lifetime = .keepAlways
    add(observation)
    XCTAssertEqual(outcome, .completed)
    XCTAssertEqual(editor.value as? String, external)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }

  #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
    @MainActor
    func testNativeEncodedTypingAutosavesFinalBytesWhileActive() throws {
      let file = try fixture()
      defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
      let original = "# Native bytes\r\n中文 👩‍💻 e\u{301}\r\n"
      let bom = Data([0xFF, 0xFE])
      try (bom + XCTUnwrap(original.data(using: .utf16LittleEndian))).write(to: file)
      let app = launch()
      defer { app.terminate() }
      let editor = open(file, in: app)
      XCTAssertEqual(editor.value as? String, original)
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      // Continue the same word after an automatic save. This makes the test
      // exercise edits after a typing checkpoint even on a fast native editor.
      editor.typeText("Autosave checkpo")
      let checkpoint =
        bom + (try XCTUnwrap((original + "Autosave checkpo").data(using: .utf16LittleEndian)))
      expectBytes(checkpoint, at: file, timeout: 8)
      XCTAssertEqual(app.state, .runningForeground)
      editor.typeText("int")
      let edited = original + "Autosave checkpoint"
      XCTAssertEqual(editor.value as? String, edited)
      let expected = bom + (try XCTUnwrap(edited.data(using: .utf16LittleEndian)))
      expectBytes(expected, at: file, timeout: 8)
      XCTAssertEqual(app.state, .runningForeground)
      XCTAssertEqual(try Data(contentsOf: file), expected)
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(editor.value as? String, original + "Autosave checkpo")
      expectBytes(checkpoint, at: file, timeout: 8)
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(editor.value as? String, original)
      expectBytes(
        bom + (try XCTUnwrap(original.data(using: .utf16LittleEndian))), at: file, timeout: 8)
      app.typeKey("z", modifierFlags: [.command, .shift])
      XCTAssertEqual(editor.value as? String, original + "Autosave checkpo")
      app.typeKey("z", modifierFlags: [.command, .shift])
      XCTAssertEqual(editor.value as? String, edited)
      expectBytes(expected, at: file, timeout: 8)
      XCTAssertEqual(app.state, .runningForeground)
    }
  #endif

  #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
    @MainActor
    func testDirtyExternalReplacementPreservesBothVersionsUntilUserChoice() throws {
      let file = try fixture()
      defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
      let originalBytes = try Data(contentsOf: file)
      let original = try XCTUnwrap(String(data: originalBytes, encoding: .utf8))
      // Keep this fixture dirty until the explicit Save conflict check. All
      // existing automatic-save methods retain the standard2-second policy.
      let app = launch(environment: ["SNOWFOLIO_PROBE_AUTOSAVE_DELAY": "30"])
      defer { app.terminate() }
      let editor = open(file, in: app)
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      editor.typeText("X")
      let local = original + "X"
      XCTAssertEqual(editor.value as? String, local)
      XCTAssertEqual(
        try Data(contentsOf: file), originalBytes, "Fixture must still have unsaved local changes")
      let external = Data("External conflict checkpoint 中文 👩‍💻\n".utf8)
      try replaceExternally(external, at: file, coordinated: false)
      let loss = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          editor.value as? String != local || (try? Data(contentsOf: file)) != external
        }, object: nil)
      loss.isInverted = true
      let preserved = XCTWaiter().wait(for: [loss], timeout: 3)
      let state = XCTAttachment(
        string:
          "sourcePreserved=\(editor.value as? String == local); externalPreserved=\((try? Data(contentsOf: file)) == external)\n\(app.debugDescription)"
      )
      state.name = "native-dirty-external-conflict"
      state.lifetime = .keepAlways
      add(state)
      XCTAssertEqual(
        preserved, .completed,
        "An external change must not silently replace either unsaved local source or external disk bytes"
      )
      app.typeKey("s", modifierFlags: .command)
      let conflict = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          app.sheets.firstMatch.exists || app.dialogs.firstMatch.exists
            || app.alerts.firstMatch.exists
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [conflict], timeout: 5), .completed)
      XCTAssertEqual(editor.value as? String, local)
      XCTAssertEqual(try Data(contentsOf: file), external)
      let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      screenshot.name = "native-dirty-external-conflict"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }

    @MainActor
    func testNativeWorkspaceMenusSettingsAndExports() throws {
      let file = try fixture()
      defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
      let source = "Menu checkpoint"
      try Data(source.utf8).write(to: file)
      let app = launch()
      defer { app.terminate() }
      let editor = open(file, in: app)
      editor.click()
      app.typeKey("a", modifierFlags: .command)
      app.menuBars.menuBarItems["Format"].click()
      let bold = app.menuItems["Bold"].firstMatch
      XCTAssertTrue(bold.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(bold.isEnabled)
      bold.click()
      XCTAssertEqual(editor.value as? String, "**Menu checkpoint**")
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(editor.value as? String, source)

      app.menuBars.menuBarItems["View"].click()
      let zoom = app.menuItems["Zoom In"].firstMatch
      XCTAssertTrue(zoom.waitForExistence(timeout: 5))
      XCTAssertTrue(zoom.isEnabled)
      zoom.click()
      app.menuBars.menuBarItems["View"].click()
      let reset = app.menuItems["Actual Size"].firstMatch
      XCTAssertTrue(reset.waitForExistence(timeout: 5))
      XCTAssertTrue(reset.isEnabled)
      reset.click()
      XCTAssertEqual(editor.value as? String, source)

      app.menuBars.menuBarItems["File"].click()
      XCTAssertTrue(app.menuItems["Print…"].firstMatch.isEnabled)
      app.menuItems["Export"].firstMatch.click()
      let copy = app.menuItems["Copy HTML"].firstMatch
      XCTAssertTrue(copy.waitForExistence(timeout: 5))
      XCTAssertTrue(copy.isEnabled)
      NSPasteboard.general.clearContents()
      copy.click()
      let expectedHTML = "<p data-sourcepos=\"1:1-1:15\">Menu checkpoint</p>\n"
      let copied = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          NSPasteboard.general.string(forType: .string) == expectedHTML
            && NSPasteboard.general.string(forType: .html) == expectedHTML
        }, object: nil)
      let copiedResult = XCTWaiter().wait(for: [copied], timeout: 8)
      let clipboard = XCTAttachment(
        string:
          "plain=\(NSPasteboard.general.string(forType: .string) ?? "missing")\nhtml=\(NSPasteboard.general.string(forType: .html) ?? "missing")"
      )
      clipboard.name = "native-menu-copy-html"
      clipboard.lifetime = .keepAlways
      add(clipboard)
      XCTAssertEqual(copiedResult, .completed)
      XCTAssertEqual(editor.value as? String, source)

      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["snowfolioSettings"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(settings.searchFields["settingsSearch"].exists)
      XCTAssertTrue(settings.switches["restoreDocumentsOnLaunch"].exists)
      app.typeKey("w", modifierFlags: .command)
      XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
      app.typeKey(",", modifierFlags: .command)
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      app.typeKey("w", modifierFlags: .command)
      XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
      let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
      screenshot.name = "native-document-workspace-command-routing"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }

    @MainActor
    func testNativeWebKitPaintingControls() throws {
      let output = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioPaint-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: output) }
      let app = launch(environment: ["SNOWFOLIO_PROBE_PAINT_OUTPUT": output.path])
      defer { app.terminate() }
      let window = app.windows["nativeWebKitPaintControl"]
      XCTAssertTrue(window.waitForExistence(timeout: 8), app.debugDescription)
      let plain = app.descendants(matching: .any)["plainPaintWebView"].firstMatch
      let pipeline = app.descendants(matching: .any)["pipelinePaintWebView"].firstMatch
      let plainReady = plain.staticTexts["Plain WebKit checkpoint"].firstMatch.waitForExistence(
        timeout: 8)
      let pipelineReady = pipeline.staticTexts["Snowfolio pipeline checkpoint"].firstMatch
        .waitForExistence(timeout: 8)
      window.buttons["capturePaintSnapshots"].click()
      let report = output.appendingPathComponent("paint-diagnostics.json")
      let completed = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: report.path) },
        object: nil)
      let result = XCTWaiter().wait(for: [completed], timeout: 8)
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "native-webkit-paint-controls-tree"
      tree.lifetime = .keepAlways
      add(tree)
      let screenshot = XCTAttachment(screenshot: window.screenshot())
      screenshot.name = "native-webkit-paint-controls-screen"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      screen.name = "native-webkit-paint-controls-full-screen"
      screen.lifetime = .keepAlways
      add(screen)
      for name in ["paint-geometry", "paint-diagnostics"] {
        let file = output.appendingPathComponent(name + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
          let attachment = XCTAttachment(contentsOfFile: file)
          attachment.name = "native-webkit-" + name
          attachment.lifetime = .keepAlways
          add(attachment)
        }
      }
      for name in ["plain", "pipeline"] {
        if FileManager.default.fileExists(atPath: output.appendingPathComponent(name + ".png").path)
        {
          let image = XCTAttachment(contentsOfFile: output.appendingPathComponent(name + ".png"))
          image.name = "native-webkit-" + name + "-snapshot"
          image.lifetime = .keepAlways
          add(image)
        }
      }
      XCTAssertTrue(plainReady)
      XCTAssertTrue(pipelineReady)
      XCTAssertEqual(result, .completed)
      let records = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: Any]])
      XCTAssertEqual(records.count, 2)
      XCTAssertTrue(records.allSatisfy { $0["snapshotSaved"] as? Bool == true }, "\(records)")
      XCTAssertGreaterThan(plain.frame.width, 300)
      XCTAssertGreaterThan(pipeline.frame.width, 300)
      XCTAssertLessThan(plain.frame.minX, pipeline.frame.minX)

      window.buttons["showDirectPaintControl"].click()
      let direct = app.descendants(matching: .any)["directPaintWebView"].firstMatch
      let directReady = direct.staticTexts["Direct window WebKit checkpoint"].firstMatch
        .waitForExistence(timeout: 8)
      app.menuBars.menuBarItems["DocumentHostProbe"].click()
      let captureDirect = app.menuItems["Capture Direct WebKit Snapshot"].firstMatch
      XCTAssertTrue(captureDirect.waitForExistence(timeout: 5))
      captureDirect.click()
      let directReport = output.appendingPathComponent("paint-direct-diagnostics.json")
      let directCompleted = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: directReport.path)
        }, object: nil)
      let directResult = XCTWaiter().wait(for: [directCompleted], timeout: 8)
      for (name, shot) in [
        ("native-webkit-direct-window-screen", window.screenshot()),
        ("native-webkit-direct-full-screen", XCUIScreen.main.screenshot()),
      ] {
        let image = XCTAttachment(screenshot: shot)
        image.name = name
        image.lifetime = .keepAlways
        add(image)
      }
      for name in ["paint-direct-diagnostics.json", "direct.png"] {
        let file = output.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: file.path) {
          let attachment = XCTAttachment(contentsOfFile: file)
          attachment.name = "native-webkit-" + name
          attachment.lifetime = .keepAlways
          add(attachment)
        }
      }
      XCTAssertTrue(directReady)
      XCTAssertEqual(directResult, .completed)
      let directRecords = try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(contentsOf: directReport)) as? [[String: Any]])
      XCTAssertEqual(directRecords.count, 1)
      XCTAssertTrue(directRecords.first?["snapshotSaved"] as? Bool == true)
    }

    @MainActor
    func testNativeWorkspacePreviewAndUndo() throws {
      let file = try fixture()
      defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
      let original = "# Workspace preview\n\nShared preview checkpoint.\n\n"
      try Data(original.utf8).write(to: file)
      let app = launch()
      defer { app.terminate() }
      let editor = open(file, in: app)
      XCTAssertEqual(editor.value as? String, original)
      let preview = app.webViews.firstMatch
      XCTAssertTrue(preview.waitForExistence(timeout: 8), app.debugDescription)
      let body = preview.staticTexts["Shared preview checkpoint."].firstMatch
      XCTAssertTrue(body.waitForExistence(timeout: 8), app.debugDescription)
      XCTAssertTrue(app.toolbars.firstMatch.exists)
      XCTAssertTrue(app.buttons["Render"].firstMatch.exists)
      XCTAssertGreaterThan(editor.frame.width, 0)
      XCTAssertGreaterThan(preview.frame.width, 0)
      XCTAssertLessThan(editor.frame.minX, preview.frame.minX)
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      editor.typeText("X")
      XCTAssertEqual(editor.value as? String, original + "X")
      let marker = preview.staticTexts["X"].firstMatch
      XCTAssertTrue(marker.waitForExistence(timeout: 8), app.debugDescription)
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(editor.value as? String, original)
      let reverted = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in !marker.exists }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [reverted], timeout: 8), .completed)
      XCTAssertTrue(body.exists)
      let window = app.windows.firstMatch
      let screen = try XCTUnwrap(NSScreen.main?.frame)
      XCTAssertGreaterThanOrEqual(window.frame.minX, screen.minX)
      XCTAssertLessThanOrEqual(window.frame.maxX, screen.maxX)
      XCTAssertGreaterThanOrEqual(window.frame.minY, screen.minY)
      XCTAssertLessThanOrEqual(window.frame.maxY, screen.maxY)
      let screenshot = XCTAttachment(screenshot: window.screenshot())
      screenshot.name = "native-document-full-workspace-preview"
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }
  #endif

  @MainActor
  func testUndoRestoresSavedBytes() throws {
    let file = try fixture()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let original = try String(contentsOf: file, encoding: .utf8)
    let app = launch()
    defer { app.terminate() }
    let editor = open(file, in: app)
    XCTAssertEqual(editor.value as? String, original)
    editor.click()
    app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
    // One character avoids comparing the documented sample's per-character model
    // Undo registration with native NSTextView typing coalescing.
    editor.typeText("X")
    XCTAssertEqual(editor.value as? String, original + "X")
    let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
    finder.activate()
    // Require the edited bytes to reach disk before Undo, so rollback persistence
    // cannot pass merely because no edit has been written yet.
    expectBytes(Data((original + "X").utf8), at: file, timeout: 35)
    app.activate()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
    finder.activate()
    expectBytes(Data(original.utf8), at: file, timeout: 35)
  }
}
