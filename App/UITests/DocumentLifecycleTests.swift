import AppKit
import Synchronization
import XCTest

final class DocumentLifecycleTests: XCTestCase {
  @MainActor
  private func launch(arguments: [String] = [], environment: [String: String] = [:])
    -> XCUIApplication
  {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
      "-editorThemeSelection", "automatic", "-readingStyleSelection", "snowfolio",
      "-htmlLineNumbers", "NO", "-htmlCodeBlockAccessory", "0",
      "-editorHorizontalInset", "24", "-editorVerticalInset", "24",
      "-editorWidthLimited", "NO", "-editorMaximumWidth", "1000", "-editorLineSpacing", "0",
      "-editorScrollsPastEnd", "NO",
    ]
    app.launchArguments += arguments
    app.launchEnvironment.merge(environment) { _, supplied in supplied }
    app.launch()
    return app
  }

  @MainActor
  private func newDocument(in app: XCUIApplication) -> XCUIElement {
    if app.buttons["NewDocumentButton"].firstMatch.exists {
      app.buttons["NewDocumentButton"].firstMatch.click()
    } else {
      app.typeKey("n", modifierFlags: .command)
    }
    let editor = app.textViews["markdownSourceEditor"].firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 8))
    return editor
  }

  @MainActor
  private func openDocument(_ file: URL, in app: XCUIApplication) -> XCUIElement {
    app.typeKey("o", modifierFlags: .command)
    let panel = app.descendants(matching: .any)["open-panel"].firstMatch
    XCTAssertTrue(panel.waitForExistence(timeout: 5))
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5))
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(file.path + "\n")
    let open = app.buttons["OKButton"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.click()
    let editor = app.textViews["markdownSourceEditor"].firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 8))
    return editor
  }

  @MainActor
  func testAutosavePreservesEncodingAndReloadsCleanExternalChange() throws {
    try checkAutosaveAndExternalReload(coordinated: false)
  }

  @MainActor
  func testCoordinatedExternalReloadAfterAutosave() throws {
    try checkAutosaveAndExternalReload(coordinated: true)
  }

  @MainActor
  private func checkAutosaveAndExternalReload(coordinated: Bool) throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("lifecycle-encoding.md")
    let original = "# Native lifecycle\r\n中文 👩‍💻 e\u{301}\r\n"
    let utf16BOM = Data([0xFF, 0xFE])
    try (utf16BOM + XCTUnwrap(original.data(using: .utf16LittleEndian))).write(to: file)
    let app = launch(environment: ["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE": "1"])
    defer { app.terminate() }
    let editor = openDocument(file, in: app)
    XCTAssertEqual(editor.value as? String, original)
    editor.click()
    app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
    editor.typeText("Autosave checkpoint")
    let edited = original + "Autosave checkpoint"
    XCTAssertEqual(editor.value as? String, edited)
    let expectedAutosave = utf16BOM + (try XCTUnwrap(edited.data(using: .utf16LittleEndian)))
    let began = ProcessInfo.processInfo.systemUptime
    let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
    finder.activate()
    // No Save command precedes this byte-exact assertion: the native host must autosave.
    let autosaved = NSPredicate { _, _ in (try? Data(contentsOf: file)) == expectedAutosave }
    expectation(for: autosaved, evaluatedWith: nil)
    waitForExpectations(timeout: 35)
    XCTAssertEqual(try Data(contentsOf: file), expectedAutosave)
    let metrics = XCTAttachment(
      string:
        "Native inactive autosave observed after \(ProcessInfo.processInfo.systemUptime - began) seconds; UTF-16LE BOM, CRLF, combining text and emoji preserved."
    )
    metrics.name = "native-autosave-encoding"
    metrics.lifetime = .keepAlways
    add(metrics)
    app.activate()
    app.typeKey("s", modifierFlags: .command)
    finder.activate()
    let external = "# External snapshot\n中文 👩‍💻 e\u{301}\n"
    let utf8BOM = Data([0xEF, 0xBB, 0xBF])
    let externalBytes = utf8BOM + Data(external.utf8)
    try writeExternally(externalBytes, to: file, coordinated: coordinated)
    app.activate()
    let reloaded = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in editor.value as? String == external }, object: nil)
    let result = XCTWaiter().wait(for: [reloaded], timeout: 8)
    let observation = XCTAttachment(
      string:
        "Coordinated writer: \(coordinated); wait outcome: \(result.rawValue); external bytes retained: \((try? Data(contentsOf: file)) == externalBytes)\n"
        + app.debugDescription)
    observation.name =
      coordinated ? "coordinated-reload-observation" : "uncoordinated-reload-observation"
    observation.lifetime = .keepAlways
    add(observation)
    XCTAssertEqual(
      result, .completed, "External reload must complete without Save, reopen or longer waits")
    XCTAssertEqual(editor.value as? String, external)
    XCTAssertEqual(try Data(contentsOf: file), externalBytes)
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "native-clean-external-reload"
    image.lifetime = .keepAlways
    add(image)
    editor.click()
    app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
    editor.typeText("After external reload")
    let final = external + "After external reload"
    XCTAssertEqual(editor.value as? String, final)
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, external)
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, final)
    app.typeKey("s", modifierFlags: .command)
    let expectedFinal = utf8BOM + Data(final.utf8)
    let saved = NSPredicate { _, _ in (try? Data(contentsOf: file)) == expectedFinal }
    expectation(for: saved, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    XCTAssertEqual(try Data(contentsOf: file), expectedFinal)
  }

  private final class ExternalWriteState: Sendable {
    let result = Mutex<Result<Void, Error>?>(nil)
  }

  @MainActor
  private func writeExternally(_ bytes: Data, to file: URL, coordinated: Bool) throws {
    let state = ExternalWriteState()
    let complete = XCTestExpectation(description: "External fixture writer completed")
    let began = ProcessInfo.processInfo.systemUptime
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    defer { queue.cancelAllOperations() }
    // Coordination can wait for a file presenter. Keep the test's main run loop responsive.
    queue.addOperation {
      let result = Result<Void, Error> {
        if coordinated {
          var coordinationError: NSError?
          var writeError: Error?
          NSFileCoordinator().coordinate(
            writingItemAt: file, options: .forReplacing, error: &coordinationError
          ) { url in
            do { try bytes.write(to: url, options: .atomic) } catch { writeError = error }
          }
          if let coordinationError { throw coordinationError }
          if let writeError { throw writeError }
        } else {
          try bytes.write(to: file, options: .atomic)
        }
      }
      state.result.withLock { $0 = result }
      complete.fulfill()
    }
    let result = XCTWaiter().wait(for: [complete], timeout: 8)
    let observation = XCTAttachment(
      string:
        "Coordinated writer: \(coordinated); completion: \(result.rawValue); elapsed: \(ProcessInfo.processInfo.systemUptime - began) seconds; canonical path: \(file.path == file.resolvingSymlinksInPath().path)."
    )
    observation.name = "external-writer-completion"
    observation.lifetime = .keepAlways
    add(observation)
    XCTAssertEqual(
      result, .completed,
      "External fixture I/O should finish while the main run loop stays responsive")
    try XCTUnwrap(state.result.withLock { $0 }).get()
  }

  @MainActor
  func testCancelUnsavedDocumentCloseRetainsEditingAndUndo() {
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    let original = "Unsaved Unicode document 中文 👩‍💻"
    editor.click()
    editor.typeText(original)
    XCTAssertEqual(editor.value as? String, original)
    app.typeKey("w", modifierFlags: .command)
    let cancel = app.sheets.buttons["Cancel"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "native-unsaved-close-confirmation"
    image.lifetime = .keepAlways
    add(image)
    cancel.click()
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, original)
    editor.click()
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Editing continues after Cancel")
    XCTAssertEqual(editor.value as? String, "Editing continues after Cancel")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
  }

  @MainActor
  func testActiveAutosaveAndSavedEditUndoPreserveBytes() throws {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("active-autosave.md")
    let original = "# Active autosave\r\n中文 👩‍💻 e\u{301}\r\n"
    let bom = Data([0xFF, 0xFE])
    let originalBytes = bom + (try XCTUnwrap(original.data(using: .utf16LittleEndian)))
    try originalBytes.write(to: file)
    let app = launch(environment: ["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE": "1"])
    defer { app.terminate() }
    let editor = openDocument(file, in: app)
    XCTAssertEqual(editor.value as? String, original)
    editor.click()
    app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
    // Require edited bytes on disk before Undo; otherwise untouched original bytes
    // could make rollback persistence pass without any automatic save.
    editor.typeText("X")
    XCTAssertEqual(editor.value as? String, original + "X")
    let editedBytes = bom + (try XCTUnwrap((original + "X").data(using: .utf16LittleEndian)))
    let edited = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == editedBytes }, object: nil)
    XCTAssertEqual(XCTWaiter().wait(for: [edited], timeout: 8), .completed)
    XCTAssertEqual(app.state, .runningForeground)
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
    let undone = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == originalBytes }, object: nil
    )
    XCTAssertEqual(XCTWaiter().wait(for: [undone], timeout: 8), .completed)
    XCTAssertEqual(app.state, .runningForeground)
    XCTAssertEqual(try Data(contentsOf: file), originalBytes)
  }

  @MainActor
  func testGracefulQuitRestoresSavedDocumentAndInsertionPosition() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("restoration-checkpoint.md")
    let source =
      "# Restoration 中文 👩‍💻\n\n" + String(repeating: "Reading and writing checkpoint.\n", count: 40)
    let bytes = Data(source.utf8)
    try bytes.write(to: file)
    let app = launch(
      arguments: [
        "-ApplePersistenceIgnoreState", "NO", "-NSQuitAlwaysKeepsWindows", "YES",
      ], environment: ["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE": "1"])
    defer { app.terminate() }
    let editor = openDocument(file, in: app)
    XCTAssertEqual(editor.value as? String, source)
    editor.click()
    app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(
      app.wait(for: .notRunning, timeout: 10), "Normal Quit should finish without a sheet")
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    app.launch()
    let window = app.windows.matching(
      NSPredicate(format: "title CONTAINS %@", "restoration-checkpoint")
    ).firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 10), app.debugDescription)
    let restored = window.textViews["markdownSourceEditor"].firstMatch
    XCTAssertTrue(restored.waitForExistence(timeout: 5))
    XCTAssertEqual(restored.value as? String, source)
    // Send through the restored first responder; clicking would replace the restored insertion position.
    app.typeText("Restored insertion checkpoint")
    XCTAssertEqual(restored.value as? String, source + "Restored insertion checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(restored.value as? String, source)
    let undoAutosaved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == bytes }, object: nil)
    let automaticResult = XCTWaiter().wait(for: [undoAutosaved], timeout: 8)
    if automaticResult != .completed {
      // Compare the same native deactivation trigger used by the encoding test.
      // This is diagnostic only: the original active8s assertion still fails below.
      let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
      finder.activate()
      let inactiveSaved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == bytes }, object: nil)
      let inactiveResult = XCTWaiter().wait(for: [inactiveSaved], timeout: 35)
      let inactiveObservation = XCTAttachment(
        string:
          "Active Undo autosave outcome: \(automaticResult.rawValue); deactivation-triggered automatic outcome: \(inactiveResult.rawValue); disk matches original: \((try? Data(contentsOf: file)) == bytes)."
      )
      inactiveObservation.name = "restored-undo-deactivation-comparison"
      inactiveObservation.lifetime = .keepAlways
      add(inactiveObservation)
      app.activate()
      // Diagnose model state versus autosave scheduling; this does not satisfy the original assertion.
      app.typeKey("s", modifierFlags: .command)
      let explicitlySaved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == bytes }, object: nil)
      let explicitResult = XCTWaiter().wait(for: [explicitlySaved], timeout: 8)
      let observation = XCTAttachment(
        string:
          "Undo autosave outcome: \(automaticResult.rawValue); diagnostic explicit Save outcome: \(explicitResult.rawValue); native text matches original: \(restored.value as? String == source); disk matches original: \((try? Data(contentsOf: file)) == bytes)."
      )
      observation.name = "restored-undo-save-comparison"
      observation.lifetime = .keepAlways
      add(observation)
    }
    XCTAssertEqual(
      automaticResult, .completed,
      "Diagnostic Save must not replace automatic Undo persistence acceptance")
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let image = XCTAttachment(screenshot: window.screenshot())
    image.name = "native-graceful-document-restoration"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testNewDocumentTypingUndoRedo() {
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("# Snowfolio\nNative document editing")
    XCTAssertEqual(editor.value as? String, "# Snowfolio\nNative document editing")
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("replacement")
    XCTAssertEqual(editor.value as? String, "replacement")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "# Snowfolio\nNative document editing")
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "replacement")
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "native-document-editor"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testLivePreviewUpdatesAfterEditingAndUndo() {
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    let original = "# Live preview\n\nFirst preview checkpoint"
    editor.typeText(original)
    let preview = app.webViews.firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 8), app.debugDescription)
    let first = preview.staticTexts["First preview checkpoint"].firstMatch
    XCTAssertTrue(first.waitForExistence(timeout: 8), app.debugDescription)
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Second preview checkpoint")
    let second = preview.staticTexts["Second preview checkpoint"].firstMatch
    XCTAssertTrue(second.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(first.exists)
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
    XCTAssertTrue(first.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(second.exists)
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "live-preview-after-native-undo"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testFencedCodePreferenceUpdatesCurrentPreview() {
    let app = launch(arguments: ["-extensionFencedCode", "YES"])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    let source = "~~~text\n**Fence checkpoint**\n~~~"
    editor.click()
    editor.typeText(source)
    XCTAssertEqual(editor.value as? String, source)
    let preview = app.webViews.firstMatch
    let code = preview.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@ OR value CONTAINS %@", "**Fence checkpoint**",
        "**Fence checkpoint**")
    ).firstMatch
    let prose = preview.staticTexts.matching(
      NSPredicate(
        format:
          "(label CONTAINS %@ OR value CONTAINS %@) AND NOT (label CONTAINS %@ OR value CONTAINS %@)",
        "Fence checkpoint", "Fence checkpoint", "**", "**")
    ).firstMatch
    XCTAssertTrue(code.waitForExistence(timeout: 8), app.debugDescription)
    func setFences() {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["snowfolioSettings"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      settings.staticTexts["Markdown"].firstMatch.click()
      let control = settings.switches["markdownFencedCode"]
      XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
      control.click()
      app.typeKey("w", modifierFlags: .command)
      XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    }
    setFences()
    XCTAssertTrue(prose.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(code.exists)
    XCTAssertEqual(editor.value as? String, source)
    setFences()
    XCTAssertTrue(code.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(prose.exists)
    XCTAssertEqual(editor.value as? String, source)
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "fenced-code-restored-through-settings"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testUnderlinePreferenceAndNativeCommand() async throws {
    let app = launch(arguments: [
      "-extensionUnderline", "NO", "-markdownEmphasisPolicy", "standard",
    ])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("a_b_c")
    let preview = app.webViews.firstMatch
    XCTAssertTrue(preview.staticTexts["a_b_c"].firstMatch.waitForExistence(timeout: 8))
    func toggleUnderline() {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["snowfolioSettings"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      settings.staticTexts["Markdown"].firstMatch.click()
      let control = settings.switches["markdownUnderline"]
      XCTAssertTrue(control.waitForExistence(timeout: 5), app.debugDescription)
      control.click()
      app.typeKey("w", modifierFlags: .command)
      XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    }
    toggleUnderline()
    XCTAssertTrue(preview.staticTexts["abc"].firstMatch.waitForExistence(timeout: 8))
    // Read the displayed UI surface, not a fresh AppKit cacheDisplay drawing.
    // The source contains no other teal elements, so the underlined b must repaint.
    var sourceRepainted = false
    for _ in 0..<60 {
      let snapshot = editor.screenshot()
      if let bitmap = NSBitmapImageRep(data: snapshot.pngRepresentation) {
        var teal = 0
        for y in 0..<min(bitmap.pixelsHigh, 180) {
          for x in 0..<min(bitmap.pixelsWide, 300) {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            if color.saturationComponent > 0.2 && (0.48...0.56).contains(color.hueComponent) {
              teal += 1
            }
          }
        }
        if teal > 5 {
          sourceRepainted = true
          break
        }
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertTrue(sourceRepainted, "The displayed source must repaint without another edit")
    XCTAssertEqual(editor.value as? String, "a_b_c")
    editor.click()
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Underline checkpoint")
    app.typeKey("a", modifierFlags: .command)
    app.typeKey("u", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "_Underline checkpoint_")
    XCTAssertTrue(
      preview.staticTexts["Underline checkpoint"].firstMatch.waitForExistence(timeout: 8))
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "Underline checkpoint")
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "_Underline checkpoint_")
    toggleUnderline()
    editor.click()
    app.typeKey("a", modifierFlags: .command)
    app.typeKey("u", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "_Underline checkpoint_")
    app.menuBars.menuBarItems["Format"].click()
    XCTAssertFalse(app.menuItems["Underline"].isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "underline-setting-and-native-command"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testIntrawordPreferenceRoundTrip() {
    let app = launch(arguments: [
      "-extensionUnderline", "NO", "-markdownEmphasisPolicy", "standard",
    ])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("a_b_c")
    let preview = app.webViews.firstMatch
    XCTAssertTrue(preview.staticTexts["a_b_c"].firstMatch.waitForExistence(timeout: 8))
    func select(_ choice: String) {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["snowfolioSettings"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      let search = settings.searchFields["settingsSearch"]
      search.click()
      app.typeKey("a", modifierFlags: .command)
      search.typeText("intraword")
      let result = settings.outlines.firstMatch.staticTexts["Formatting inside words"].firstMatch
      XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
      result.click()
      let picker = settings.popUpButtons["markdownIntraword"]
      XCTAssertTrue(picker.waitForExistence(timeout: 5))
      XCTAssertTrue(settings.frame.contains(picker.frame))
      picker.click()
      app.menuItems[choice].click()
      app.typeKey("w", modifierFlags: .command)
      XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    }
    select("Allow")
    XCTAssertTrue(preview.staticTexts["abc"].firstMatch.waitForExistence(timeout: 8))
    XCTAssertEqual(editor.value as? String, "a_b_c")
    select("Avoid")
    XCTAssertTrue(preview.staticTexts["a_b_c"].firstMatch.waitForExistence(timeout: 8))
    XCTAssertFalse(preview.staticTexts["abc"].firstMatch.exists)
    select("Standard Markdown")
    XCTAssertTrue(preview.staticTexts["a_b_c"].firstMatch.waitForExistence(timeout: 8))
    XCTAssertEqual(editor.value as? String, "a_b_c")
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "intraword-setting-round-trip"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testSettingsSearchHistoryAndWindowReopen() {
    let app = launch(arguments: ["-htmlMathJax", "NO"])
    defer { app.terminate() }
    _ = newDocument(in: app)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(settings.switches["restoreDocumentsOnLaunch"].exists)
    let sidebar = settings.outlines.firstMatch
    sidebar.staticTexts["Appearance"].firstMatch.click()
    XCTAssertTrue(settings.popUpButtons["documentFont"].waitForExistence(timeout: 5))
    settings.popUpButtons["documentFont"].click()
    XCTAssertTrue(app.menuItems["Serif"].waitForExistence(timeout: 3))
    app.typeKey(.escape, modifierFlags: [])
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("inline equations")
    let result = sidebar.staticTexts["Single dollar signs for inline equations"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let inlineMath = settings.switches["markdownInlineMath"]
    XCTAssertTrue(inlineMath.waitForExistence(timeout: 5))
    XCTAssertTrue(
      settings.frame.contains(inlineMath.frame), "Search must reveal the entire offscreen setting")
    XCTAssertFalse(inlineMath.isEnabled)
    settings.buttons["settingsGoBack"].click()
    XCTAssertTrue(settings.popUpButtons["documentFont"].waitForExistence(timeout: 5))
    settings.buttons["settingsGoForward"].click()
    XCTAssertTrue(inlineMath.waitForExistence(timeout: 5))
    XCTAssertTrue(settings.frame.contains(inlineMath.frame))
    search.click()
    app.typeKey("a", modifierFlags: .command)
    app.typeKey(.delete, modifierFlags: [])
    sidebar.staticTexts["Privacy & Security"].firstMatch.click()
    XCTAssertTrue(settings.switches["previewRawHTML"].waitForExistence(timeout: 5))
    XCTAssertTrue(settings.switches["previewRemoteImages"].exists)
    sidebar.staticTexts["Editor"].firstMatch.click()
    XCTAssertTrue(settings.textFields["editorFontName"].waitForExistence(timeout: 5))
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertTrue(settings.textFields["editorFontName"].waitForExistence(timeout: 5))
    app.typeKey(",", modifierFlags: .command)
    XCTAssertEqual(app.windows.matching(identifier: "snowfolioSettings").count, 1)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "system-style-settings-editor"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testImportReadingStyleFolderAndSourceUndo() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appending(path: "parts"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let main = root.appending(path: "Arctic Reading Checkpoint.css")
    let sourceCSS = Data("@import 'parts/base.css'; body{font-family:Helvetica;}".utf8)
    let childCSS = Data("body{background:rgb(240,248,255);color:rgb(17,34,51);}".utf8)
    try sourceCSS.write(to: main)
    try childCSS.write(to: root.appending(path: "parts/base.css"))
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    let original = "# Original source\n\nPreserved text."
    editor.typeText(original)
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Imported style checkpoint")
    let preview = app.webViews.firstMatch
    XCTAssertTrue(
      preview.staticTexts["Imported style checkpoint"].firstMatch.waitForExistence(timeout: 8))
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.outlines.firstMatch.staticTexts["Appearance"].firstMatch.click()
    let importer = settings.descendants(matching: .any).matching(identifier: "importReadingStyle")
      .firstMatch
    XCTAssertTrue(importer.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(
      settings.descendants(matching: .any).matching(identifier: "importReadingStyle").count, 1)
    XCTAssertEqual(settings.buttons.matching(identifier: "revealReadingStyles").count, 1)
    importer.click()
    app.menuItems["Style Folder…"].click()
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(root.path + "\n")
    let open = app.buttons["OKButton"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.click()
    let mainPicker = settings.popUpButtons["readingStyleMainFile"]
    XCTAssertTrue(mainPicker.waitForExistence(timeout: 8), app.debugDescription)
    mainPicker.click()
    XCTAssertTrue(app.menuItems["parts/base.css"].exists)
    app.menuItems["Arctic Reading Checkpoint.css"].click()
    settings.buttons["confirmReadingStyleFolder"].click()
    let picker = settings.popUpButtons["readingStyle"]
    let imported = NSPredicate { _, _ in
      picker.value as? String == "Arctic Reading Checkpoint" && settings.sheets.count == 0
    }
    expectation(for: imported, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    XCTAssertFalse(settings.popUpButtons["documentFont"].isEnabled)
    XCTAssertEqual(try Data(contentsOf: main), sourceCSS)
    XCTAssertEqual(try Data(contentsOf: root.appending(path: "parts/base.css")), childCSS)
    try FileManager.default.removeItem(at: root)
    settings.buttons["reloadReadingStyle"].click()
    XCTAssertEqual(picker.value as? String, "Arctic Reading Checkpoint")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertTrue(
      preview.staticTexts["Imported style checkpoint"].firstMatch.waitForExistence(timeout: 8))
    XCTAssertEqual(editor.value as? String, "Imported style checkpoint")
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Imported style checkpoint")
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertEqual(picker.value as? String, "Arctic Reading Checkpoint")
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "imported-style-folder-and-source-history"
    image.lifetime = .keepAlways
    add(image)
    picker.click()
    app.menus.containing(.menuItem, identifier: "Clearness Dark").firstMatch.menuItems["Snowfolio"]
      .click()
    app.typeKey("w", modifierFlags: .command)
  }

  @MainActor
  func testReadingStylePickerPreviewAndSourceUndo() {
    let app = launch(arguments: ["-markdownManualRender", "NO"])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    let original = "# Reading style checkpoint\n\nPreserved source."
    editor.typeText(original)
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Style undo checkpoint")
    let preview = app.webViews.firstMatch
    let rendered = preview.staticTexts["Style undo checkpoint"].firstMatch
    XCTAssertTrue(rendered.waitForExistence(timeout: 8), app.debugDescription)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.outlines.firstMatch.staticTexts["Appearance"].firstMatch.click()
    let picker = settings.popUpButtons["readingStyle"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(picker.value as? String, "Snowfolio")
    picker.click()
    let styleMenu = app.menus.containing(.menuItem, identifier: "Clearness Dark").firstMatch
    for title in [
      "None", "Clearness", "Clearness Dark", "GitHub", "GitHub2", "Solarized (Light)",
      "Solarized (Dark)",
    ] {
      XCTAssertTrue(styleMenu.menuItems[title].exists)
    }
    styleMenu.menuItems["Clearness Dark"].click()
    let changed = NSPredicate { _, _ in
      picker.value as? String == "Clearness Dark"
        && !settings.popUpButtons["documentFont"].isEnabled
    }
    expectation(for: changed, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Style undo checkpoint")
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    XCTAssertTrue(rendered.waitForExistence(timeout: 8), app.debugDescription)
    var lastPreview: XCUIScreenshot?
    var paperRGB: [UInt8] = []
    let paper = NSPredicate { _, _ in
      let snapshot = preview.screenshot()
      lastPreview = snapshot
      guard let image = NSBitmapImageRep(data: snapshot.pngRepresentation)?.cgImage,
        let pixel = image.cropping(
          to: CGRect(x: image.width / 2, y: image.height * 9 / 10, width: 1, height: 1)),
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let bytes = context.data
      else { return false }
      // NSBitmapImageRep.colorAt returns calibrated RGB components even for an
      // sRGB PNG. Draw through the image's profile into sRGB before comparing.
      context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
      paperRGB = (0..<3).map { bytes.load(fromByteOffset: $0, as: UInt8.self) }
      return zip(paperRGB, [40, 42, 54]).allSatisfy { actual, expected in
        abs(Double(actual) / 255 - Double(expected) / 255) < 0.025
      }
    }
    expectation(for: paper, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    if let lastPreview {
      let image = XCTAttachment(screenshot: lastPreview)
      image.name = "clearness-dark-preview-sRGB-" + paperRGB.map(String.init).joined(separator: "-")
      image.lifetime = .keepAlways
      add(image)
    }
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertEqual(picker.value as? String, "Clearness Dark")
    picker.click()
    styleMenu.menuItems["None"].click()
    XCTAssertEqual(picker.value as? String, "None")
    picker.click()
    styleMenu.menuItems["Snowfolio"].click()
    let restored = NSPredicate { _, _ in settings.popUpButtons["documentFont"].isEnabled }
    expectation(for: restored, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "reading-style-picker-restored-to-snowfolio"
    image.lifetime = .keepAlways
    add(image)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Style undo checkpoint")
  }

  @MainActor
  func testEditorThemePickerSearchImportAndUndo() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("Snowfolio UI Theme.style")
    let bytes = Data(
      "editor\nforeground: 112233\nbackground: e0efff\nfont-size: 24px\ncustom-field: retained\n"
        .utf8)
    try bytes.write(to: file)
    let app = launch(arguments: ["-editorInsertPrefixInBlock", "NO"])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    let source = "1. First\n2. Second\n\n- Bullet"
    editor.typeText(source)
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Theme undo checkpoint")
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("source theme")
    let result = settings.outlines.firstMatch.staticTexts["Theme"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let picker = settings.popUpButtons["editorTheme"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(settings.frame.contains(picker.frame))
    picker.click()
    XCTAssertTrue(app.menuItems["Automatic"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.menuItems["Solarized (Dark)"].exists)
    app.menuItems["Solarized (Dark)"].click()
    XCTAssertEqual(picker.value as? String, "Solarized (Dark)")
    XCTAssertEqual(settings.buttons.matching(identifier: "importEditorTheme").count, 1)
    XCTAssertEqual(settings.buttons.matching(identifier: "reloadEditorThemes").count, 1)
    settings.buttons["importEditorTheme"].click()
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(file.path + "\n")
    let open = app.buttons["OKButton"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.click()
    let review = settings.sheets.firstMatch
    XCTAssertTrue(review.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(settings.sheets.count, 1)
    XCTAssertTrue(review.staticTexts["Review Theme"].exists)
    review.buttons["Import"].click()
    let imported = NSPredicate { _, _ in picker.value as? String == "Snowfolio UI Theme" }
    expectation(for: imported, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Theme undo checkpoint")
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Theme undo checkpoint")
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertEqual(picker.value as? String, "Snowfolio UI Theme")
    picker.click()
    app.menuItems["Automatic"].click()
    XCTAssertEqual(picker.value as? String, "Automatic")
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "editor-theme-library-restored-to-automatic"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testUnsavedAssetFolderChooserCancelAndHistory() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "Snowfolio Asset Checkpoint " + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("Original source")
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Asset folder checkpoint")
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("unsaved assets")
    let result = settings.outlines.firstMatch.staticTexts["Unsaved document assets"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let choose = settings.buttons["chooseUnsavedAssetFolder"]
    XCTAssertTrue(choose.waitForExistence(timeout: 5))
    XCTAssertEqual(settings.buttons.matching(identifier: "chooseUnsavedAssetFolder").count, 1)
    choose.click()
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(root.path + "\n")
    let open = app.buttons["OKButton"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.click()
    let status = settings.staticTexts["unsavedAssetFolderStatus"]
    let selected = NSPredicate { _, _ in
      status.label == root.path || status.value as? String == root.path
    }
    expectation(for: selected, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    choose.click()
    XCTAssertTrue(app.buttons["OKButton"].firstMatch.waitForExistence(timeout: 5))
    app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    XCTAssertTrue(selected.evaluate(with: nil))
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "unsaved-asset-folder-settings"
    image.lifetime = .keepAlways
    add(image)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Asset folder checkpoint")
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "Original source")
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Asset folder checkpoint")
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertTrue(selected.evaluate(with: nil))
    settings.buttons["clearUnsavedAssetFolder"].click()
    let cleared = NSPredicate { _, _ in
      status.label == "No folder selected" || status.value as? String == "No folder selected"
    }
    expectation(for: cleared, evaluatedWith: nil)
    waitForExpectations(timeout: 5)
    XCTAssertEqual(editor.value as? String, "Asset folder checkpoint")
  }

  @MainActor
  func testSavingUntitledUsesSavedFolderForRelativeImageExport() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let unsaved = root.appending(path: "Unsaved assets")
    let saved = root.appending(path: "Saved document")
    let exported = root.appending(path: "Export")
    for folder in [unsaved, saved, exported] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try XCTUnwrap(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII="
      ))
    try first.write(to: unsaved.appending(path: "ice.png"))
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8,
        bitsPerPixel: 32))
    bitmap.setColor(.systemBlue, atX: 0, y: 0)
    bitmap.setColor(.systemTeal, atX: 1, y: 0)
    let second = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    try second.write(to: saved.appending(path: "ice.png"))
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    let source = "![Ice](ice.png)"
    editor.click()
    editor.typeText(source)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("unsaved assets")
    let result = settings.outlines.firstMatch.staticTexts["Unsaved document assets"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5))
    result.click()
    settings.buttons["chooseUnsavedAssetFolder"].click()
    choosePanelDirectory(unsaved, in: app)
    app.buttons["OKButton"].firstMatch.click()
    let status = settings.staticTexts["unsavedAssetFolderStatus"]
    expectation(
      for: NSPredicate { _, _ in
        status.label == unsaved.path || status.value as? String == unsaved.path
      }, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    app.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(app.buttons["OKButton"].firstMatch.waitForExistence(timeout: 5))
    choosePanelDirectory(saved, in: app)
    let name = app.textFields.firstMatch
    name.click()
    app.typeKey("a", modifierFlags: .command)
    name.typeText("Saved.md")
    app.buttons["OKButton"].firstMatch.click()
    let file = saved.appending(path: "Saved.md")
    expectation(
      for: NSPredicate { _, _ in
        (try? Data(contentsOf: file)) == Data(source.utf8)
      }, evaluatedWith: nil)
    waitForExpectations(timeout: 10)
    app.typeKey("e", modifierFlags: [.command, .shift])
    let styles = app.checkBoxes["exportDocumentStyles"]
    XCTAssertTrue(styles.waitForExistence(timeout: 5))
    choosePanelDirectory(exported, in: app)
    app.buttons["OKButton"].firstMatch.click()
    expectation(
      for: NSPredicate { _, _ in
        let files =
          (try? FileManager.default.contentsOfDirectory(
            at: exported, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "html" } && !styles.exists
      }, evaluatedWith: nil)
    waitForExpectations(timeout: 10)
    let htmlFile = try XCTUnwrap(
      FileManager.default.contentsOfDirectory(at: exported, includingPropertiesForKeys: nil).first {
        $0.pathExtension == "html"
      })
    let html = try String(contentsOf: htmlFile, encoding: .utf8)
    XCTAssertTrue(html.contains("data:image/png;base64," + second.base64EncodedString()))
    XCTAssertFalse(html.contains("data:image/png;base64," + first.base64EncodedString()))
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.buttons["clearUnsavedAssetFolder"].click()
  }

  @MainActor
  private func choosePanelDirectory(_ directory: URL, in app: XCUIApplication) {
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(directory.path + "\n")
    XCTAssertTrue(app.buttons["OKButton"].firstMatch.waitForExistence(timeout: 5))
  }

  @MainActor
  func testEditorScrollPastEndPreservesSourceAndHistory() {
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    let original = "Original scrolling source"
    let replacement = "Scroll space history checkpoint"
    editor.click()
    editor.typeText(original)
    app.typeKey("a", modifierFlags: .command)
    editor.typeText(replacement)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("scroll past the end")
    let result = settings.outlines.firstMatch.staticTexts["Scroll past the end"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let toggle = settings.switches["editorScrollsPastEnd"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(settings.switches.matching(identifier: "editorScrollsPastEnd").count, 1)
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 0)
    toggle.click()
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 1)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "editor-scroll-past-end-settings"
    image.lifetime = .keepAlways
    add(image)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, replacement)
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, original)
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, replacement)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 1)
    toggle.click()
    XCTAssertEqual(toggle.value as? Int ?? Int(toggle.value as? String ?? ""), 0)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, replacement)
  }

  @MainActor
  func testEditorLineSpacingPreservesSourceAndHistory() {
    let app = launch(arguments: ["-editorInsertPrefixInBlock", "NO"])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    let source = "1. First\n2. Second\n\n- dfdfd\n"
    editor.typeText(source)
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey("a", modifierFlags: .command)
    let replacement = "Line spacing undo checkpoint"
    editor.typeText(replacement)
    XCTAssertEqual(editor.value as? String, replacement)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("line spacing")
    let result = settings.outlines.firstMatch.staticTexts["Line spacing"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let spacing = settings.textFields["editorLineSpacing"]
    XCTAssertTrue(spacing.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(settings.textFields.matching(identifier: "editorLineSpacing").count, 1)
    XCTAssertTrue(spacing.isEnabled)
    XCTAssertEqual(spacing.value as? String, "0")
    spacing.click()
    app.typeKey("a", modifierFlags: .command)
    spacing.typeText("12.5")
    app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
    XCTAssertEqual(spacing.value as? String, "12.5")
    let settingsImage = XCTAttachment(screenshot: settings.screenshot())
    settingsImage.name = "editor-line-spacing-settings"
    settingsImage.lifetime = .keepAlways
    add(settingsImage)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, replacement)
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, replacement)
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey("a", modifierFlags: .command)
    let selectionImage = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    selectionImage.name = "editor-line-spacing-mixed-list-selection"
    selectionImage.lifetime = .keepAlways
    add(selectionImage)
    app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
    let sourceImage = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    sourceImage.name = "editor-line-spacing-terminal-caret"
    sourceImage.lifetime = .keepAlways
    add(sourceImage)
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertEqual(spacing.value as? String, "12.5")
    spacing.click()
    app.typeKey("a", modifierFlags: .command)
    spacing.typeText("0")
    app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
    XCTAssertEqual(spacing.value as? String, "0")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, source)
  }

  @MainActor
  func testEditorColumnSettingsPreserveSourceAndHistory() {
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("Original column source")
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Column layout checkpoint")
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("maximum column")
    let result = settings.outlines.firstMatch.staticTexts["Maximum column width"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let maximum = settings.textFields["editorMaximumWidth"]
    XCTAssertTrue(maximum.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertFalse(maximum.isEnabled)
    let limit = settings.switches["editorWidthLimited"]
    XCTAssertTrue(limit.exists)
    limit.click()
    XCTAssertTrue(maximum.isEnabled)
    let limitState = limit.value as? Int ?? Int(limit.value as? String ?? "")
    XCTAssertEqual(limitState, 1)
    maximum.click()
    app.typeKey("a", modifierFlags: .command)
    maximum.typeText("450")
    app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
    XCTAssertEqual(maximum.value as? String, "450")
    XCTAssertTrue(settings.textFields["editorHorizontalInset"].exists)
    XCTAssertTrue(settings.textFields["editorVerticalInset"].exists)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "editor-column-settings"
    image.lifetime = .keepAlways
    add(image)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Column layout checkpoint")
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "Original column source")
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Column layout checkpoint")
    app.typeKey(",", modifierFlags: .command)
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    XCTAssertTrue(maximum.isEnabled)
    XCTAssertEqual(maximum.value as? String, "450")
    limit.click()
    XCTAssertFalse(maximum.isEnabled)
  }

  @MainActor
  func testCodePresentationSettingsRetainSourceAndHistory() {
    let app = launch(arguments: [
      "-markdownManualRender", "NO", "-htmlSyntaxHighlighting", "NO",
      "-htmlLineNumbers", "NO", "-htmlCodeBlockAccessory", "0",
      "-editorHorizontalInset", "24", "-editorVerticalInset", "24",
      "-editorWidthLimited", "NO", "-editorMaximumWidth", "1000",
    ])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    let source = "```swift:Snowfolio.swift\nlet value = 42\n```"
    editor.click()
    editor.typeText(source)
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Code history checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("code label")
    let result = settings.outlines.firstMatch.staticTexts["Code label"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let picker = settings.popUpButtons["previewCodeLabel"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(settings.popUpButtons.matching(identifier: "previewCodeLabel").count, 1)
    picker.click()
    let menu = app.menus.containing(.menuItem, identifier: "Language name").firstMatch
    XCTAssertTrue(menu.menuItems["None"].exists && menu.menuItems["Custom"].exists)
    menu.menuItems["Custom"].click()
    let numbers = settings.switches["previewCodeLineNumbers"]
    XCTAssertTrue(numbers.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertTrue(numbers.isEnabled)
    numbers.click()
    let state = numbers.value as? Int ?? Int(numbers.value as? String ?? "")
    XCTAssertEqual(state, 1)
    XCTAssertEqual(picker.value as? String, "Custom")
    let settingsImage = XCTAttachment(screenshot: settings.screenshot())
    settingsImage.name = "code-presentation-settings"
    settingsImage.lifetime = .keepAlways
    add(settingsImage)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    let preview = app.webViews.firstMatch
    let label = preview.staticTexts["Snowfolio.swift"].firstMatch
    XCTAssertTrue(label.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertEqual(editor.value as? String, source)
    editor.click()
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Code history checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
    XCTAssertTrue(label.waitForExistence(timeout: 8))
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "numbered-code-and-custom-label"
    image.lifetime = .keepAlways
    add(image)
  }

  @MainActor
  func testNoStyleHTMLExportStartsWithoutDocumentStyles() {
    let app = launch(arguments: [
      "-htmlTemplateName", "Default", "-htmlSyntaxHighlighting", "YES",
      "-htmlLineNumbers", "NO", "-htmlCodeBlockAccessory", "0",
      "-editorHorizontalInset", "24", "-editorVerticalInset", "24",
      "-editorWidthLimited", "NO", "-editorMaximumWidth", "1000",
    ])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    let source = "```swift\nlet value = 42\n```"
    editor.click()
    editor.typeText(source)
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    settings.outlines.firstMatch.staticTexts["Appearance"].firstMatch.click()
    let picker = settings.popUpButtons["readingStyle"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    picker.click()
    let menu = app.menus.containing(.menuItem, identifier: "Clearness Dark").firstMatch
    menu.menuItems["None"].click()
    XCTAssertEqual(picker.value as? String, "None")
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    app.typeKey("e", modifierFlags: [.command, .shift])
    let styles = app.checkBoxes["exportDocumentStyles"]
    let code = app.checkBoxes["exportCodeHighlighting"]
    XCTAssertTrue(styles.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(styles.value as? Int, 0)
    XCTAssertEqual(code.value as? Int, 1)
    styles.click()
    XCTAssertEqual(styles.value as? Int, 1)
    styles.click()
    let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    image.name = "no-document-style-export-default"
    image.lifetime = .keepAlways
    add(image)
    app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    XCTAssertTrue(styles.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, source)
  }

  @MainActor
  func testHTMLTemplateRecoveryPreservesSourceUndo() {
    let app = launch(arguments: ["-htmlTemplateName", "Unavailable legacy template"])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("Original source")
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Template recovery checkpoint")
    app.typeKey("e", modifierFlags: [.command, .shift])
    let alert = app.sheets.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 8), app.debugDescription)
    let explanation = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@ OR value CONTAINS %@",
        "The saved HTML template is unavailable", "The saved HTML template is unavailable")
    ).firstMatch
    XCTAssertTrue(explanation.waitForExistence(timeout: 8), app.debugDescription)
    XCTAssertFalse(app.checkBoxes["exportDocumentStyles"].exists)
    alert.buttons["OK"].click()
    XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    app.typeKey(",", modifierFlags: .command)
    let settings = app.windows["snowfolioSettings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    let search = settings.searchFields["settingsSearch"]
    search.click()
    search.typeText("HTML template")
    let result = settings.outlines.firstMatch.staticTexts["HTML template"].firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    result.click()
    let reset = settings.buttons["resetHTMLTemplate"]
    XCTAssertTrue(reset.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(settings.buttons.matching(identifier: "resetHTMLTemplate").count, 1)
    reset.click()
    XCTAssertTrue(reset.waitForNonExistence(timeout: 5))
    let status = settings.staticTexts.matching(identifier: "htmlTemplateStatus").matching(
      NSPredicate(format: "label == %@ OR value == %@", "Default", "Default")
    ).firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
    let image = XCTAttachment(screenshot: settings.screenshot())
    image.name = "html-template-recovered-default"
    image.lifetime = .keepAlways
    add(image)
    app.typeKey("w", modifierFlags: .command)
    XCTAssertTrue(settings.waitForNonExistence(timeout: 5))
    XCTAssertEqual(editor.value as? String, "Template recovery checkpoint")
    editor.click()
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, "Original source")
  }

  @MainActor
  func testHTMLExportOptionsUseFreshManualPreviewSource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = launch(arguments: [
      "-markdownManualRender", "YES", "-htmlTemplateName", "Default", "-htmlSyntaxHighlighting",
      "YES",
    ])
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("Old preview checkpoint")
    app.typeKey("r", modifierFlags: .command)
    let preview = app.webViews.firstMatch
    let old = preview.staticTexts["Old preview checkpoint"].firstMatch
    XCTAssertTrue(old.waitForExistence(timeout: 8), app.debugDescription)
    app.typeKey("a", modifierFlags: .command)
    let source = "# Fresh export checkpoint\n\n```swift\nlet value = 42\n```"
    editor.typeText(source)
    XCTAssertEqual(editor.value as? String, source)
    XCTAssertTrue(old.exists)
    // Establish one explicit native history step; multiline simulated typing
    // legitimately has more than one undo group.
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("Export history checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
    for styled in [false, true] {
      for highlighted in [false, true] {
        let folder = root.appendingPathComponent("\(styled)-\(highlighted)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        app.typeKey("e", modifierFlags: [.command, .shift])
        let styles = app.checkBoxes["exportDocumentStyles"]
        let code = app.checkBoxes["exportCodeHighlighting"]
        XCTAssertTrue(styles.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(code.exists)
        XCTAssertEqual(styles.value as? Int, 1)
        XCTAssertEqual(code.value as? Int, 1)
        if !styled { styles.click() }
        if !highlighted { code.click() }
        XCTAssertEqual(styles.value as? Int, styled ? 1 : 0)
        XCTAssertEqual(code.value as? Int, highlighted ? 1 : 0)
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.textFields["PathTextField"].firstMatch
        XCTAssertTrue(path.waitForExistence(timeout: 5), app.debugDescription)
        path.click()
        app.typeKey("a", modifierFlags: .command)
        path.typeText(folder.path + "\n")
        let save = app.buttons["OKButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        save.click()
        let finished = NSPredicate { _, _ in
          let files =
            (try? FileManager.default.contentsOfDirectory(
              at: folder, includingPropertiesForKeys: nil)) ?? []
          return files.filter { $0.pathExtension == "html" }.count == 1 && !styles.exists
        }
        expectation(for: finished, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        let files = try FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "html" }
        XCTAssertEqual(files.count, 1)
        let html = try String(contentsOf: XCTUnwrap(files.first), encoding: .utf8)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Fresh export checkpoint"))
        XCTAssertFalse(html.contains("Old preview checkpoint"))
        XCTAssertEqual(html.contains("id=\"document-style\""), styled)
        XCTAssertEqual(html.contains("id=\"code-style\""), highlighted)
        XCTAssertEqual(html.contains("token keyword"), highlighted)
        XCTAssertFalse(html.contains("<script"))
        XCTAssertEqual(editor.value as? String, source)
        XCTAssertTrue(old.exists)
      }
    }
    editor.click()
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(editor.value as? String, "Export history checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(editor.value as? String, source)
  }

  @MainActor
  func testOpenExistingMarkdownAndSave() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("unicode.md")
    let original = Data([0xEF, 0xBB, 0xBF]) + Data("# 中文 👩‍💻\r\n".utf8)
    try original.write(to: file)
    let app = launch()
    defer { app.terminate() }
    let editor = openDocument(file, in: app)
    XCTAssertEqual(editor.value as? String, "# 中文 👩‍💻\r\n")
    editor.click()
    app.typeKey("a", modifierFlags: .command)
    editor.typeText("# Edited\n")
    app.typeKey("s", modifierFlags: .command)
    let saved = NSPredicate { _, _ in
      (try? Data(contentsOf: file)) == Data([0xEF, 0xBB, 0xBF]) + Data("# Edited\n".utf8)
    }
    expectation(for: saved, evaluatedWith: nil)
    waitForExpectations(timeout: 8)
  }

  @MainActor
  func testSavedTabsRestoreSelectedDocumentAndIndependentUndo() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioTabRestoration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let alpha = directory.appendingPathComponent("tab-alpha.md")
    let beta = directory.appendingPathComponent("tab-beta.md")
    let alphaSource = "# Alpha 中文 👩‍💻\n\nFirst document checkpoint.\n"
    let betaSource = "# Beta e\u{301}\n\nSecond document checkpoint.\n"
    let alphaBytes = Data(alphaSource.utf8)
    let betaBytes = Data(betaSource.utf8)
    try alphaBytes.write(to: alpha)
    try betaBytes.write(to: beta)
    let app = launch(arguments: [
      "-ApplePersistenceIgnoreState", "NO", "-NSQuitAlwaysKeepsWindows", "YES",
      "-preferDocumentTabs", "YES",
    ])
    defer { app.terminate() }
    func activeEditor(showing source: String) -> XCUIElement {
      let editor = app.textViews["markdownSourceEditor"].firstMatch
      let matches = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in editor.exists && editor.value as? String == source },
        object: nil)
      let result = XCTWaiter().wait(for: [matches], timeout: 8)
      if result != .completed {
        let state = XCTAttachment(string: app.debugDescription)
        state.name = "native-tab-source-mismatch"
        state.lifetime = .keepAlways
        add(state)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "native-tab-source-mismatch"
        image.lifetime = .keepAlways
        add(image)
      }
      XCTAssertEqual(result, .completed)
      return editor
    }
    _ = openDocument(alpha, in: app)
    _ = activeEditor(showing: alphaSource)
    _ = openDocument(beta, in: app)
    _ = activeEditor(showing: betaSource)

    // Use the real native menu. It can already be disabled when the preferred
    // tab policy placed the two opened documents in the same tab group.
    app.menuBars.menuBarItems["Window"].click()
    let merge = app.menuItems["Merge All Windows"].firstMatch
    XCTAssertTrue(merge.waitForExistence(timeout: 5))
    if merge.isEnabled {
      merge.click()
    } else {
      app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    func expectOriginalBytes() {
      let original = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          (try? Data(contentsOf: alpha)) == alphaBytes && (try? Data(contentsOf: beta)) == betaBytes
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [original], timeout: 8), .completed)
    }
    func appendAndUndo(_ text: String, to source: String) {
      let editor = activeEditor(showing: source)
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      editor.typeText(text)
      XCTAssertEqual(editor.value as? String, source + text)
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(editor.value as? String, source)
      expectOriginalBytes()
    }

    func selectTab(_ name: String, showing source: String) -> XCUIElement {
      let tab = app.tabGroups.firstMatch.descendants(matching: .any).matching(
        NSPredicate(format: "title == %@", name)
      ).firstMatch
      XCTAssertTrue(tab.waitForExistence(timeout: 5), app.debugDescription)
      tab.click()
      return activeEditor(showing: source)
    }
    // A normal empty startup tab may also exist. Select the authored alpha tab
    // explicitly, then use Control-Tab to reach its adjacent beta document.
    // Undo must target only the selected file, regardless of the startup tab.
    _ = selectTab("tab-alpha.md", showing: alphaSource)
    appendAndUndo("Alpha edit", to: alphaSource)
    XCTAssertEqual(try Data(contentsOf: beta), betaBytes)
    app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: .control)
    appendAndUndo("Beta edit", to: betaSource)
    XCTAssertEqual(try Data(contentsOf: alpha), alphaBytes)
    let before = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    before.name = "native-saved-tabs-before-quit"
    before.lifetime = .keepAlways
    add(before)

    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    XCTAssertEqual(try Data(contentsOf: alpha), alphaBytes)
    XCTAssertEqual(try Data(contentsOf: beta), betaBytes)
    app.launch()
    let restored = activeEditor(showing: betaSource)
    // Do not click: the selected tab and its insertion position must restore.
    app.typeText("Restored beta")
    XCTAssertEqual(restored.value as? String, betaSource + "Restored beta")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(restored.value as? String, betaSource)
    expectOriginalBytes()
    let restoredAlpha = selectTab("tab-alpha.md", showing: alphaSource)
    app.typeText("Restored alpha")
    XCTAssertEqual(restoredAlpha.value as? String, alphaSource + "Restored alpha")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(restoredAlpha.value as? String, alphaSource)
    expectOriginalBytes()
    let after = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    after.name = "native-saved-tabs-restored"
    after.lifetime = .keepAlways
    add(after)
  }

  #if NATIVE_DOCUMENT_HOST
    @MainActor
    func testIndependentReadingPositionsSurviveQuitAndRelaunch() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioReadingRestoration-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let file = directory.appendingPathComponent("reading-positions.md")
      let source =
        "# Independent reading positions\r\n\r\n"
        + (1...160).map {
          "Paragraph \($0) 中文 👩‍💻 e\u{301}. A separate reading checkpoint in both panes.\r\n\r\n"
        }.joined()
      let bytes = Data([0xFF, 0xFE]) + (try XCTUnwrap(source.data(using: .utf16LittleEndian)))
      try bytes.write(to: file)
      let app = launch(arguments: [
        "-ApplePersistenceIgnoreState", "NO", "-NSQuitAlwaysKeepsWindows", "YES",
        "-AppleShowScrollBars", "Always", "-editorSyncScrolling", "NO",
      ])
      defer { app.terminate() }
      defer {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "native-reading-restoration-tree"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "native-reading-restoration-final"
        image.lifetime = .keepAlways
        add(image)
      }
      let editor = openDocument(file, in: app)
      let window = app.windows[file.lastPathComponent].firstMatch
      let loaded = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in editor.value as? String == source }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 8), .completed)
      let sourceScroll = window.scrollViews["markdownSourceScroll"].firstMatch
      let preview = window.descendants(matching: .any).matching(identifier: "markdownPreview")
        .firstMatch
      let previewScroll = preview.scrollViews.firstMatch
      let heading = preview.staticTexts.matching(
        NSPredicate(format: "value == %@", "Independent reading positions")
      ).firstMatch
      XCTAssertTrue(heading.waitForExistence(timeout: 8), app.debugDescription)
      func position(_ scroll: XCUIElement) throws -> Double {
        let bar = scroll.scrollBars.firstMatch
        guard bar.exists, let value = bar.value as? Double else {
          throw NSError(
            domain: "SnowfolioReadingRestoration", code: 1,
            userInfo: [
              NSLocalizedDescriptionKey: "Missing numeric scrollbar: \(scroll.debugDescription)"
            ])
        }
        return value
      }
      XCTAssertTrue(
        sourceScroll.scrollBars.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(
        previewScroll.scrollBars.firstMatch.waitForExistence(timeout: 5), app.debugDescription)
      editor.click()
      app.typeKey(XCUIKeyboardKey.upArrow.rawValue, modifierFlags: .command)
      XCTAssertLessThanOrEqual(try position(sourceScroll), 0.001)
      sourceScroll.scroll(byDeltaX: 0, deltaY: -1800)
      let sourceMoved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? position(sourceScroll)) ?? 0 > 0.03 }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [sourceMoved], timeout: 8), .completed)
      let sourcePosition = try position(sourceScroll)
      XCTAssertLessThanOrEqual(try position(previewScroll), 0.001)
      previewScroll.scroll(byDeltaX: 0, deltaY: -3200)
      let previewMoved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? position(previewScroll)) ?? 0 > 0.03 }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [previewMoved], timeout: 8), .completed)
      let previewPosition = try position(previewScroll)
      XCTAssertEqual(try position(sourceScroll), sourcePosition, accuracy: 0.002)
      XCTAssertEqual(editor.value as? String, source)
      XCTAssertEqual(try Data(contentsOf: file), bytes)
      let before = XCTAttachment(screenshot: window.screenshot())
      before.name = "native-independent-reading-before-quit"
      before.lifetime = .keepAlways
      add(before)
      app.typeKey("q", modifierFlags: .command)
      XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
      XCTAssertEqual(try Data(contentsOf: file), bytes)
      app.launch()
      let restored = app.windows[file.lastPathComponent].firstMatch
      let restoredEditor = restored.textViews["markdownSourceEditor"].firstMatch
      let restoredSource = restored.scrollViews["markdownSourceScroll"].firstMatch
      let restoredPreview = restored.descendants(matching: .any).matching(
        identifier: "markdownPreview"
      )
      .firstMatch.scrollViews.firstMatch
      let readingRestored = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          guard restoredEditor.exists, restoredEditor.value as? String == source,
            let sourceValue = try? position(restoredSource),
            let previewValue = try? position(restoredPreview)
          else { return false }
          return abs(sourceValue - sourcePosition) < 0.002
            && abs(previewValue - previewPosition) < 0.002
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [readingRestored], timeout: 8), .completed)
      let values = XCTAttachment(
        string:
          "Source before=\(sourcePosition), after=\(try position(restoredSource)); preview before=\(previewPosition), after=\(try position(restoredPreview))"
      )
      values.name = "native-independent-reading-positions"
      values.lifetime = .keepAlways
      add(values)
      // Do not click: the source caret at the beginning must restore independently
      // of both reading positions. Editing must still have native Undo ownership.
      app.typeText("Restored checkpoint. ")
      XCTAssertEqual(restoredEditor.value as? String, "Restored checkpoint. " + source)
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(restoredEditor.value as? String, source)
      let unchanged = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == bytes }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [unchanged], timeout: 8), .completed)
    }

    @MainActor
    func testSeparateTabGroupsRestoreWithoutMergingDocuments() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioSeparateGroups-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let names = ["group-alpha.md", "group-delta.md", "group-beta.md", "group-gamma.md"]
      let sources = names.map { "# \($0) 中文 👩‍💻\n\nIndependent group checkpoint.\n" }
      let files = names.map { directory.appendingPathComponent($0) }
      for (file, source) in zip(files, sources) { try Data(source.utf8).write(to: file) }
      let app = launch(arguments: [
        "-ApplePersistenceIgnoreState", "NO", "-NSQuitAlwaysKeepsWindows", "YES",
        "-preferDocumentTabs", "YES",
      ])
      defer { app.terminate() }
      defer {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "native-separate-tab-groups"
        tree.lifetime = .keepAlways
        add(tree)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "native-separate-tab-groups"
        image.lifetime = .keepAlways
        add(image)
      }
      func editor(in name: String, source: String) -> XCUIElement {
        let editor = app.windows[name].firstMatch.textViews["markdownSourceEditor"].firstMatch
        let loaded = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in editor.exists && editor.value as? String == source },
          object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 8), .completed)
        return editor
      }
      func selectWindow(_ name: String) {
        let menu = app.menuBars.menuBarItems["Window"]
        menu.click()
        let item = menu.menuItems[name].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.click()
      }
      func expectGroup(
        selected: String, containing included: [String], excluding excluded: [String]
      ) {
        let window = app.windows[selected].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8), app.debugDescription)
        let group = window.tabGroups.firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5), app.debugDescription)
        for name in included {
          XCTAssertTrue(
            group.descendants(matching: .any).matching(NSPredicate(format: "title == %@", name))
              .firstMatch.exists, app.debugDescription)
        }
        for name in excluded {
          XCTAssertFalse(
            group.descendants(matching: .any).matching(NSPredicate(format: "title == %@", name))
              .firstMatch.exists, app.debugDescription)
        }
      }
      func expectBytes() throws {
        for (file, source) in zip(files, sources) {
          XCTAssertEqual(try Data(contentsOf: file), Data(source.utf8))
        }
      }
      // Build the first two-file group, then split the third tab using the real
      // native command. The fourth open must join that originating group only.
      for index in 0...2 {
        _ = openDocument(files[index], in: app)
        _ = editor(in: names[index], source: sources[index])
      }
      let menu = app.menuBars.menuBarItems["Window"]
      menu.click()
      let detach = menu.menuItems["Move Tab to New Window"].firstMatch
      XCTAssertTrue(detach.waitForExistence(timeout: 5))
      XCTAssertTrue(detach.isEnabled)
      detach.click()
      _ = editor(in: names[2], source: sources[2])
      _ = openDocument(files[3], in: app)
      _ = editor(in: names[3], source: sources[3])
      expectGroup(
        selected: names[3], containing: [names[2], names[3]], excluding: [names[0], names[1]])
      selectWindow(names[1])
      let first = editor(in: names[1], source: sources[1])
      expectGroup(
        selected: names[1], containing: [names[0], names[1]], excluding: [names[2], names[3]])
      first.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      first.typeText("First group history")
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(first.value as? String, sources[1])
      selectWindow(names[3])
      let second = editor(in: names[3], source: sources[3])
      second.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      second.typeText("Second group history")
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(second.value as? String, sources[3])
      try expectBytes()
      app.typeKey("q", modifierFlags: .command)
      XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
      try expectBytes()
      app.launch()
      let restored = editor(in: names[3], source: sources[3])
      expectGroup(
        selected: names[3], containing: [names[2], names[3]], excluding: [names[0], names[1]])
      // No click: native restoration must retain the front group and its caret.
      app.typeText("Restored second group")
      XCTAssertEqual(restored.value as? String, sources[3] + "Restored second group")
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(restored.value as? String, sources[3])
      selectWindow(names[1])
      let restoredFirst = editor(in: names[1], source: sources[1])
      expectGroup(
        selected: names[1], containing: [names[0], names[1]], excluding: [names[2], names[3]])
      app.typeText("Restored first group")
      XCTAssertEqual(restoredFirst.value as? String, sources[1] + "Restored first group")
      app.typeKey("z", modifierFlags: .command)
      XCTAssertEqual(restoredFirst.value as? String, sources[1])
      try expectBytes()
    }
  #endif

  @MainActor
  func testNewTabsUseKeyboardAndNativePlusWithoutReusingEmptyDocuments() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioNewTabs-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("tab-anchor.md")
    let source = "# Saved anchor 中文 👩‍💻\n\nSeparate document checkpoint.\n"
    let bytes = Data(source.utf8)
    try bytes.write(to: file)
    let app = launch(arguments: ["-preferDocumentTabs", "YES"])
    defer { app.terminate() }
    let opened = openDocument(file, in: app)
    let loaded = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in opened.value as? String == source }, object: nil)
    XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 8), .completed)
    defer {
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "native-new-tabs-tree"
      tree.lifetime = .keepAlways
      add(tree)
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = "native-new-tabs-screen"
      image.lifetime = .keepAlways
      add(image)
    }
    let tabBar = app.tabGroups.firstMatch
    // The current SwiftUI host can start with only this saved document, so the
    // native tab bar is normally hidden. Show it before counting/creating tabs.
    if !tabBar.exists {
      #if NATIVE_DOCUMENT_HOST
        let menu = app.menuBars.menuBarItems["Window"]
      #else
        let menu = app.menuBars.menuBarItems["View"]
      #endif
      menu.click()
      let show = menu.menuItems["Show Tab Bar"].firstMatch
      XCTAssertTrue(show.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(show.isEnabled)
      show.click()
    }
    XCTAssertTrue(tabBar.waitForExistence(timeout: 5), app.debugDescription)
    let tabs = tabBar.children(matching: .tab)
    let initialCount = tabs.count
    XCTAssertGreaterThan(initialCount, 0)
    func expectTabs(_ count: Int, source: String) -> XCUIElement {
      let editor = app.textViews["markdownSourceEditor"].firstMatch
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          tabs.count == count && editor.exists && editor.value as? String == source
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 8), .completed)
      XCTAssertEqual(try? Data(contentsOf: file), bytes)
      return editor
    }
    // Repeating the command while the selected document is empty must create
    // another native document rather than reusing that empty tab.
    app.typeKey("t", modifierFlags: .command)
    _ = expectTabs(initialCount + 1, source: "")
    app.typeKey("t", modifierFlags: .command)
    let keyboardEditor = expectTabs(initialCount + 2, source: "")
    keyboardEditor.click()
    keyboardEditor.typeText("Keyboard tab checkpoint")
    XCTAssertEqual(keyboardEditor.value as? String, "Keyboard tab checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(keyboardEditor.value as? String, "")
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(keyboardEditor.value as? String, "Keyboard tab checkpoint")

    // This is AppKit's actual tab-bar plus button, identified in the native AX tree.
    let plus = tabBar.buttons["new tab"]
    XCTAssertTrue(plus.waitForExistence(timeout: 5), app.debugDescription)
    plus.click()
    let plusEditor = expectTabs(initialCount + 3, source: "")
    plusEditor.click()
    plusEditor.typeText("Plus tab checkpoint")
    XCTAssertEqual(plusEditor.value as? String, "Plus tab checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(plusEditor.value as? String, "")
    app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [.control, .shift])
    let previous = expectTabs(initialCount + 3, source: "Keyboard tab checkpoint")
    app.typeKey("z", modifierFlags: .command)
    XCTAssertEqual(previous.value as? String, "")
    app.typeKey("z", modifierFlags: [.command, .shift])
    XCTAssertEqual(previous.value as? String, "Keyboard tab checkpoint")
    let anchor = tabs.matching(NSPredicate(format: "title == %@", file.lastPathComponent))
      .firstMatch
    XCTAssertTrue(anchor.exists)
    anchor.click()
    _ = expectTabs(initialCount + 3, source: source)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }

  #if NATIVE_DOCUMENT_HOST
    @MainActor
    private func preservingRecoveryClipboard(_ action: () -> Void) {
      let board = NSPasteboard.general
      let saved = (board.pasteboardItems ?? []).map { item in
        item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
      }
      defer {
        board.clearContents()
        let items = saved.map { entries in
          let item = NSPasteboardItem()
          for (type, data) in entries { item.setData(data, forType: type) }
          return item
        }
        board.writeObjects(items)
      }
      action()
    }

    @MainActor
    private func pasteRecoveryText(_ text: String, in app: XCUIApplication) {
      preservingRecoveryClipboard {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
      }
    }

    @MainActor
    private func attachRecoveryState(_ name: String, app: XCUIApplication, note: String = "") {
      let state = XCTAttachment(string: note + "\n" + app.debugDescription)
      state.name = name
      state.lifetime = .keepAlways
      add(state)
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = name
      screenshot.lifetime = .keepAlways
      add(screenshot)
    }

    private enum RecoveryChoice: String {
      case revert = "Revert"
      case saveAnyway = "Save Anyway"
      case saveAs = "Save As…"
    }

    @MainActor
    func testPeriodicDirtyConflictRevertKeepsExternalSource() throws {
      try checkPeriodicDirtyConflict(choice: .revert)
    }

    @MainActor
    func testPeriodicDirtyConflictSaveAnywayKeepsExternalVersion() throws {
      try checkPeriodicDirtyConflict(choice: .saveAnyway)
    }

    @MainActor
    func testPeriodicDirtyConflictSaveAsKeepsBothFiles() throws {
      try checkPeriodicDirtyConflict(choice: .saveAs)
    }

    @MainActor
    private func checkPeriodicDirtyConflict(choice: RecoveryChoice) throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioPeriodicConflict-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("periodic-conflict.md")
      let recoveredFile = directory.appendingPathComponent("recovered-local.md")
      defer {
        try? NSFileVersion.removeOtherVersionsOfItem(at: file)
        try? NSFileVersion.removeOtherVersionsOfItem(at: recoveredFile)
        try? FileManager.default.removeItem(at: directory)
      }
      let original = "# Original 中文 👩‍💻\r\n"
      let originalBytes =
        Data([0xFF, 0xFE])
        + (try XCTUnwrap(original.data(using: .utf16LittleEndian)))
      try originalBytes.write(to: file)
      let app = launch(environment: ["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE": "1"])
      defer { app.terminate() }
      let editor = openDocument(file, in: app)
      XCTAssertEqual(editor.value as? String, original)
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      // One native paste transaction keeps the edit/external-write boundary short.
      // This actual app retains its normal2-second periodic autosave policy.
      pasteRecoveryText("X", in: app)
      let diskBeforeExternal = try Data(contentsOf: file)
      let external = "# External e\u{301} 中文 👩‍💻\n"
      let externalBytes = Data([0xEF, 0xBB, 0xBF]) + Data(external.utf8)
      let began = ProcessInfo.processInfo.systemUptime
      try externalBytes.write(to: file, options: .atomic)
      let local = original + "X"
      XCTAssertEqual(diskBeforeExternal, originalBytes, "The staged edit must still be unsaved")
      let surfaced = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          app.sheets.firstMatch.exists || app.dialogs.firstMatch.exists
            || app.alerts.firstMatch.exists
        }, object: nil)
      // No Save, deactivation, custom autosave delay or scripted edit precedes this.
      let outcome = XCTWaiter().wait(for: [surfaced], timeout: 35)
      attachRecoveryState(
        "native-periodic-dirty-conflict", app: app,
        note:
          "surfaceOutcome=\(outcome.rawValue) elapsed=\(ProcessInfo.processInfo.systemUptime - began) localPreserved=\(editor.value as? String == local) externalPreserved=\((try? Data(contentsOf: file)) == externalBytes)"
      )
      XCTAssertEqual(outcome, .completed)
      XCTAssertEqual(editor.value as? String, local)
      XCTAssertEqual(try Data(contentsOf: file), externalBytes)
      let action = app.sheets.firstMatch.buttons[choice.rawValue].firstMatch
      XCTAssertTrue(action.waitForExistence(timeout: 5), app.debugDescription)
      action.click()
      if choice == .saveAs {
        let save = app.buttons["OKButton"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5), app.debugDescription)
        choosePanelDirectory(directory, in: app)
        let name = app.textFields.firstMatch
        name.click()
        app.typeKey("a", modifierFlags: .command)
        name.typeText(recoveredFile.lastPathComponent)
        save.click()
      }
      let localBytes =
        Data([0xFF, 0xFE])
        + (try XCTUnwrap(local.data(using: .utf16LittleEndian)))
      let selectedFile = choice == .saveAs ? recoveredFile : file
      let selectedSource = choice == .revert ? external : local
      let selectedBytes = choice == .revert ? externalBytes : localBytes
      let restored = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          editor.value as? String == selectedSource
            && (try? Data(contentsOf: selectedFile)) == selectedBytes
            && !app.sheets.firstMatch.exists && !app.dialogs.firstMatch.exists
            && !app.alerts.firstMatch.exists
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [restored], timeout: 8), .completed)
      attachRecoveryState("native-periodic-conflict-\(choice)", app: app)
      if choice == .saveAs {
        XCTAssertEqual(try Data(contentsOf: file), externalBytes)
      } else {
        let preservedBytes = choice == .revert ? localBytes : externalBytes
        let preservedOther = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in
            (NSFileVersion.otherVersionsOfItem(at: file) ?? []).contains {
              (try? Data(contentsOf: $0.url)) == preservedBytes
            }
          }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [preservedOther], timeout: 8), .completed)
      }
      // Each native choice must establish the corresponding URL/encoding baseline.
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      let addition = "After recovery"
      editor.typeText(addition)
      app.typeKey("s", modifierFlags: .command)
      let additionBytes =
        choice == .revert
        ? Data(addition.utf8) : try XCTUnwrap(addition.data(using: .utf16LittleEndian))
      let expected = selectedBytes + additionBytes
      let saved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: selectedFile)) == expected },
        object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 8), .completed)
      if choice == .saveAs {
        XCTAssertEqual(try Data(contentsOf: file), externalBytes)
      }
    }

    @MainActor
    func testNativeVersionsBrowseAndRestoreExactPreviousBytes() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioNativeVersions-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("native-versions.md")
      defer {
        try? NSFileVersion.removeOtherVersionsOfItem(at: file)
        try? FileManager.default.removeItem(at: directory)
      }
      let original = "# Version one 中文 👩‍💻\r\ne\u{301}\r\n"
      let replacement = "# Version two 中文 👩‍💻\r\nRetain this newer revision too.\r\n"
      let bom = Data([0xFF, 0xFE])
      let originalBytes = bom + (try XCTUnwrap(original.data(using: .utf16LittleEndian)))
      let replacementBytes = bom + (try XCTUnwrap(replacement.data(using: .utf16LittleEndian)))
      try originalBytes.write(to: file)
      let app = launch(environment: ["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE": "1"])
      defer { app.terminate() }
      let editor = openDocument(file, in: app)
      XCTAssertEqual(editor.value as? String, original)
      editor.click()
      app.typeKey("a", modifierFlags: .command)
      pasteRecoveryText(replacement, in: app)
      XCTAssertEqual(editor.value as? String, replacement)
      app.typeKey("s", modifierFlags: .command)
      let saved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == replacementBytes },
        object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 8), .completed)
      func historyContains(_ bytes: Data) -> Bool {
        (NSFileVersion.otherVersionsOfItem(at: file) ?? []).contains {
          (try? Data(contentsOf: $0.url)) == bytes
        }
      }
      let recorded = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in historyContains(originalBytes) }, object: nil)
      let historyOutcome = XCTWaiter().wait(for: [recorded], timeout: 8)
      let versions = NSFileVersion.otherVersionsOfItem(at: file) ?? []
      // Native Save must create its own history. This test never injects versions
      // and never restores through a file-copy or NSFileVersion replacement API.
      app.menuBars.menuBarItems["File"].click()
      let browse = app.menuItems["Browse All Versions…"].firstMatch
      XCTAssertTrue(browse.waitForExistence(timeout: 5), app.debugDescription)
      XCTAssertTrue(browse.isEnabled)
      browse.click()
      let browser = app.windows["NSVersionBrowsingControls"]
      let restore = browser.buttons["Restore"].firstMatch
      let browserReady = restore.waitForExistence(timeout: 12)
      attachRecoveryState(
        "native-versions-before-restore", app: app,
        note:
          "nativeHistoryCount=\(versions.count) originalHistory=\(historyOutcome.rawValue) restoreExists=\(browserReady) currentBytes=\((try? Data(contentsOf: file)) == replacementBytes)"
      )
      XCTAssertEqual(historyOutcome, .completed)
      XCTAssertTrue(browserReady, app.debugDescription)
      let timeline = browser.sliders.firstMatch
      XCTAssertTrue(timeline.exists, app.debugDescription)
      // This native timeline omits AXOrientation, so XCTest's generic slider
      // adjustment cannot synthesize it. Use the observed browsing arrows.
      let navigation = browser.buttons.matching(
        NSPredicate(format: "title != %@ AND title != %@", "Done", "Restore"))
      XCTAssertEqual(navigation.count, 2)
      let originalPreview = app.textViews.matching(identifier: "markdownSourceEditor").matching(
        NSPredicate(format: "value == %@", original)
      ).firstMatch
      for _ in 0..<max(1, versions.count) {
        if originalPreview.exists { break }
        let older = try XCTUnwrap(navigation.allElementsBoundByIndex.first { $0.isEnabled })
        older.click()
        if originalPreview.waitForExistence(timeout: 5) { break }
      }
      let selectedOriginal = originalPreview.waitForExistence(timeout: 8)
      attachRecoveryState(
        "native-versions-original-selected", app: app,
        note: "originalPreview=\(selectedOriginal) timeline=\(String(describing: timeline.value))")
      XCTAssertTrue(selectedOriginal, app.debugDescription)
      preservingRecoveryClipboard {
        NSPasteboard.general.clearContents()
        originalPreview.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey("c", modifierFlags: .command)
        // Exact Copy establishes focus on the historical source, rather than
        // merely sending a rejected key to the surrounding Versions browser.
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), original)
        app.typeKey("x", modifierFlags: [])
        attachRecoveryState("native-versions-read-only-source", app: app)
        XCTAssertTrue(originalPreview.exists, "Typing must not alter the historical source")
        let currentPreview = app.textViews.matching(identifier: "markdownSourceEditor").matching(
          NSPredicate(format: "value == %@", replacement)
        ).firstMatch
        XCTAssertTrue(currentPreview.exists, "Historical browsing must not edit the current source")
        XCTAssertEqual(try? Data(contentsOf: file), replacementBytes)
        XCTAssertTrue(historyContains(originalBytes))
      }
      XCTAssertTrue(restore.isEnabled)
      restore.click()
      let confirm = app.sheets.buttons["Restore"].firstMatch
      if confirm.exists { confirm.click() }
      XCTAssertTrue(restore.waitForNonExistence(timeout: 12))
      let reverted = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          editor.exists && editor.value as? String == original
            && (try? Data(contentsOf: file)) == originalBytes
        }, object: nil)
      let restored = XCTWaiter().wait(for: [reverted], timeout: 8)
      attachRecoveryState("native-versions-restored", app: app)
      XCTAssertEqual(restored, .completed)
      let recoverableNewer = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in historyContains(replacementBytes) }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [recoverableNewer], timeout: 8), .completed)
    }
  #endif

  @MainActor
  func testMultipleDocumentWindows() {
    let app = launch()
    defer { app.terminate() }
    let editor = newDocument(in: app)
    editor.click()
    editor.typeText("first document")
    let before = app.windows.count
    app.typeKey("n", modifierFlags: .command)
    XCTAssertGreaterThan(app.windows.count, before)
    XCTAssertTrue(app.textViews["markdownSourceEditor"].firstMatch.exists)
  }
}
