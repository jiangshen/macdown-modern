import AppKit
import XCTest

final class DocumentLinksTests: XCTestCase {
  @MainActor
  func testDocumentLinksOpenNavigateAndReuseAcrossLaunches() async throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("URL 中文 #%.md")
    let source = "first\r\n🧊e\u{301} target\r\nZ-last\r\n"
    let bom = Data([0xff, 0xfe])
    let bytes = bom + (try XCTUnwrap(source.data(using: .utf16LittleEndian)))
    try bytes.write(to: file)
    let cold = directory.appendingPathComponent("cold-link.md")
    let coldSource = "Q-cold\r\nrest\r\n"
    try Data(coldSource.utf8).write(to: cold)
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
      "-editorThemeSelection", "automatic", "-readingStyleSelection", "snowfolio",
      "-editorSyntaxHighlighting", "NO", "-editorShowWordCount", "NO",
    ]
    app.launchEnvironment["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE"] = "1"
    app.launch()
    defer { app.terminate() }
    let running = try XCTUnwrap(
      NSRunningApplication.runningApplications(
        withBundleIdentifier: "local.macdown.modern"
      ).first)
    let target = try XCTUnwrap(running.bundleURL)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    configuration.createsNewApplicationInstance = false
    configuration.arguments = app.launchArguments
    configuration.environment = app.launchEnvironment
    func open(_ file: URL, line: Int, column: Int, scheme: String = "snowfolio") async throws {
      var parts = URLComponents()
      parts.scheme = scheme
      parts.host = "open"
      parts.queryItems = [
        .init(name: "url", value: file.absoluteString),
        .init(name: "line", value: String(line)), .init(name: "column", value: String(column)),
      ]
      let url = try XCTUnwrap(parts.url)
      _ = try await NSWorkspace.shared.open(
        [url], withApplicationAt: target,
        configuration: configuration)
    }
    func editor(for file: URL) -> XCUIElement {
      app.windows.matching(NSPredicate(format: "title == %@", file.lastPathComponent))
        .firstMatch.textViews["markdownSourceEditor"].firstMatch
    }
    func waitForSource(_ text: String, file: URL) async {
      let view = editor(for: file)
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          view.exists && view.value as? String == text
        }, object: nil)
      let result = await XCTWaiter.fulfillment(of: [ready], timeout: 8)
      if result != .completed {
        let image = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        image.name = "document-link-source-failure"
        image.lifetime = .keepAlways
        add(image)
      }
      XCTAssertEqual(result, .completed, app.debugDescription)
    }
    func waitForBytes(_ bytes: Data, file: URL) async {
      let saved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          (try? Data(contentsOf: file)) == bytes
        }, object: nil)
      let result = await XCTWaiter.fulfillment(of: [saved], timeout: 8)
      XCTAssertEqual(result, .completed)
    }
    try await open(file, line: 2, column: 6)
    await waitForSource(source, file: file)
    XCTAssertEqual(try Data(contentsOf: file), bytes)
    // No click or selection command establishes this caret. The URL must do it.
    app.typeText("LINK")
    let edited = source.replacingOccurrences(of: "target", with: "LINKtarget")
    await waitForSource(edited, file: file)
    app.typeKey("z", modifierFlags: .command)
    await waitForSource(source, file: file)
    let windows = app.windows.count
    // The original scheme remains compatible with existing external integrations.
    try await open(file, line: 3, column: 1, scheme: "x-macdown")
    await waitForSource(source, file: file)
    XCTAssertEqual(app.windows.count, windows)
    app.typeText("AGAIN")
    await waitForSource(source.replacingOccurrences(of: "Z-last", with: "AGAINZ-last"), file: file)
    app.typeKey("z", modifierFlags: .command)
    await waitForSource(source, file: file)
    app.typeKey("s", modifierFlags: .command)
    await waitForBytes(bytes, file: file)
    let warmImage = XCTAttachment(
      screenshot: app.windows.matching(
        NSPredicate(format: "title == %@", file.lastPathComponent)
      ).firstMatch.screenshot())
    warmImage.name = "document-link-existing-file-and-location"
    warmImage.lifetime = .keepAlways
    add(warmImage)
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
    try await open(cold, line: 2, column: 3, scheme: "x-snowfolio")
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
    await waitForSource(coldSource, file: cold)
    app.typeText("COLD")
    await waitForSource("Q-cold\r\nreCOLDst\r\n", file: cold)
    app.typeKey("z", modifierFlags: .command)
    await waitForSource(coldSource, file: cold)
    app.typeKey("s", modifierFlags: .command)
    await waitForBytes(Data(coldSource.utf8), file: cold)
    let image = XCTAttachment(
      screenshot: app.windows.matching(
        NSPredicate(format: "title == %@", cold.lastPathComponent)
      ).firstMatch.screenshot())
    image.name = "document-link-cold-launch-and-location"
    image.lifetime = .keepAlways
    add(image)
  }
}
