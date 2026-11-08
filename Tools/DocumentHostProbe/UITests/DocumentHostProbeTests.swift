import AppKit
import Synchronization
import XCTest

final class DocumentHostProbeTests: XCTestCase {
  @MainActor
  private func launch() -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
    ]
    #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
      app.launchEnvironment["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE"] = "1"
    #endif
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
    let editor = app.textViews["stockDocumentEditor"].firstMatch
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
