import Foundation
import XCTest

final class DocumentTypeTests: XCTestCase {
  @MainActor
  func testExtensionlessAndUnfamiliarTextOpenWithoutChangingBytesAndBinaryIsRejected() async throws
  {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bare = directory.appendingPathComponent("README")
    let bareSource = "# Extensionless text\r\n中文 🧊 e\u{301}\r\n"
    let bareBytes =
      Data([0xff, 0xfe]) + (try XCTUnwrap(bareSource.data(using: .utf16LittleEndian)))
    try bareBytes.write(to: bare)
    let custom = directory.appendingPathComponent("draft.snowfolio-text")
    let customSource = "# Unfamiliar extension\r\nKeep every byte.\r\n"
    let customBytes = Data([0xef, 0xbb, 0xbf]) + Data(customSource.utf8)
    try customBytes.write(to: custom)
    let invalid = directory.appendingPathComponent("unsupported-binary.snowfolio-text")
    let invalidBytes = Data([0xff, 0x00, 0x80])
    try invalidBytes.write(to: invalid)
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
      "-editorSyntaxHighlighting", "NO",
    ]
    app.launch()
    defer { app.terminate() }
    func capture(_ name: String) {
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = name
      image.lifetime = .keepAlways
      add(image)
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = name + "-hierarchy"
      tree.lifetime = .keepAlways
      add(tree)
    }
    func open(_ file: URL) {
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
    }
    for (file, source, bytes) in [
      (bare, bareSource, bareBytes), (custom, customSource, customBytes),
    ] {
      open(file)
      let editor = app.windows[file.lastPathComponent].firstMatch
        .textViews["markdownSourceEditor"].firstMatch
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in editor.exists && editor.value as? String == source },
        object: nil)
      let result = await XCTWaiter.fulfillment(of: [ready], timeout: 8)
      if result != .completed { capture("generic-document-open-failure") }
      XCTAssertEqual(result, .completed, app.debugDescription)
      XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    capture("generic-text-files-opened")
    open(invalid)
    let alert = app.dialogs.matching(NSPredicate(format: "label == 'alert'")).firstMatch
    let rejected = alert.waitForExistence(timeout: 5)
    if !rejected { capture("generic-binary-rejection-failure") }
    XCTAssertTrue(rejected, app.debugDescription)
    XCTAssertFalse(app.windows[invalid.lastPathComponent].firstMatch.exists)
    XCTAssertEqual(try Data(contentsOf: invalid), invalidBytes)
    capture("generic-binary-rejected")
    app.buttons["OK"].firstMatch.click()
    XCTAssertEqual(try Data(contentsOf: bare), bareBytes)
    XCTAssertEqual(try Data(contentsOf: custom), customBytes)
  }
}
