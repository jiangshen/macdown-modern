import AppKit
import Synchronization
import XCTest

final class DocumentHostProbeTests: XCTestCase {
  @MainActor
  private func open(_ file: URL) -> (XCUIApplication, XCUIElement) {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
    ]
    app.launch()
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
    XCTAssertTrue(editor.waitForExistence(timeout: 8))
    return (app, editor)
  }

  @MainActor
  private func fixture() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
  private func replaceExternally(_ data: Data, at file: URL) throws {
    let state = WriteState()
    let completed = XCTestExpectation(description: "Stock probe external write")
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.addOperation {
      let result = Result<Void, Error> { try data.write(to: file, options: .atomic) }
      state.result.withLock { $0 = result }
      completed.fulfill()
    }
    XCTAssertEqual(XCTWaiter().wait(for: [completed], timeout: 8), .completed)
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
  private func checkReload(afterAutosave: Bool) throws {
    let file = try fixture()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let original = try String(contentsOf: file, encoding: .utf8)
    let (app, editor) = open(file)
    defer { app.terminate() }
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
    try replaceExternally(bytes, at: file)
    app.activate()
    let reloaded = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in editor.value as? String == external }, object: nil)
    let outcome = XCTWaiter().wait(for: [reloaded], timeout: 8)
    let observation = XCTAttachment(
      string:
        "afterAutosave=\(afterAutosave); reload=\(outcome.rawValue); externalBytesRetained=\((try? Data(contentsOf: file)) == bytes)\n"
        + app.debugDescription)
    observation.name = "stock-document-reload"
    observation.lifetime = .keepAlways
    add(observation)
    XCTAssertEqual(outcome, .completed)
    XCTAssertEqual(editor.value as? String, external)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
  }

  @MainActor
  func testUndoRestoresSavedBytes() throws {
    let file = try fixture()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let original = try String(contentsOf: file, encoding: .utf8)
    let (app, editor) = open(file)
    defer { app.terminate() }
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
