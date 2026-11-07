import XCTest

final class DocumentLifecycleTests: XCTestCase {
  @MainActor
  private func launch(arguments: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
    ]
    app.launchArguments += arguments
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
      NSPredicate(format: "label CONTAINS %@", "**Fence checkpoint**")
    ).firstMatch
    let prose = preview.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "Fence checkpoint", "**")
    ).firstMatch
    XCTAssertTrue(code.waitForExistence(timeout: 8), app.debugDescription)
    func setFences() {
      app.typeKey(",", modifierFlags: .command)
      let settings = app.windows["com_apple_SwiftUI_Settings_window"]
      XCTAssertTrue(settings.waitForExistence(timeout: 5))
      settings.toolbars.buttons["Markdown"].click()
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
  func testOpenExistingMarkdownAndSave() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("unicode.md")
    let original = Data([0xEF, 0xBB, 0xBF]) + Data("# 中文 👩‍💻\r\n".utf8)
    try original.write(to: file)
    let app = launch()
    defer { app.terminate() }
    app.typeKey("o", modifierFlags: .command)
    let panel = app.descendants(matching: .any)["open-panel"].firstMatch
    XCTAssertTrue(panel.waitForExistence(timeout: 5))
    app.typeKey("g", modifierFlags: [.command, .shift])
    let pathField = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(pathField.waitForExistence(timeout: 5))
    pathField.click()
    app.typeKey("a", modifierFlags: .command)
    pathField.typeText(file.path + "\n")
    let open = app.buttons["OKButton"].firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: 5))
    open.click()
    let editor = app.textViews["markdownSourceEditor"].firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: 8))
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
