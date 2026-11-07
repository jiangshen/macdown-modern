import AppKit
import XCTest

final class DocumentLifecycleTests: XCTestCase {
  @MainActor
  private func launch(arguments: [String] = []) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
      "-editorThemeSelection", "automatic", "-readingStyleSelection", "snowfolio",
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
