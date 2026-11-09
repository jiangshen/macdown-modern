import AppKit
import XCTest

final class CommandLineTests: XCTestCase {
  private struct Result: Sendable {
    let status: Int32
    let output: String
    let error: String
    let seconds: Double
  }

  @concurrent private static func runTool(
    _ tool: URL, arguments: [String], directory: URL, input: Data? = nil,
    delayedInput: Bool = false
  ) async throws -> Result {
    let process = Process()
    process.executableURL = tool
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = ProcessInfo.processInfo.environment.filter {
      ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"].contains($0.key)
    }
    process.environment?["SNOWFOLIO_TRACE_CLI"] = "1"
    let output = Pipe()
    let error = Pipe()
    let stdin = Pipe()
    process.standardOutput = output
    process.standardError = error
    process.standardInput = stdin
    let started = ProcessInfo.processInfo.systemUptime
    try process.run()
    if delayedInput { try await Task.sleep(for: .milliseconds(200)) }
    if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
    try stdin.fileHandleForWriting.close()
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while process.isRunning, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(25))
    }
    guard !process.isRunning else {
      process.terminate()
      throw NSError(
        domain: "CommandLineTests", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "CLI launch did not complete within 20 seconds."])
    }
    return Result(
      status: process.terminationStatus,
      output: String(
        decoding: try output.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self),
      error: String(decoding: try error.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self),
      seconds: ProcessInfo.processInfo.systemUptime - started)
  }

  @MainActor
  func testBundledCommandLineOpensFilesAndDelayedPipesAcrossLaunches() async throws {
    continueAfterFailure = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("🧊 #%.md")
    let original = "# Existing 中文\r\ne\u{301}\r\n"
    let originalBytes =
      Data([0xFF, 0xFE]) + (try XCTUnwrap(original.data(using: .utf16LittleEndian)))
    try originalBytes.write(to: file)
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
      "-editorThemeSelection", "automatic", "-editorSyntaxHighlighting", "NO",
    ]
    app.launchEnvironment["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE"] = "1"
    app.launch()
    defer { app.terminate() }
    defer {
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "command-line-final-hierarchy"
      tree.lifetime = .keepAlways
      add(tree)
      let image = XCTAttachment(screenshot: app.screenshot())
      image.name = "command-line-final-state"
      image.lifetime = .keepAlways
      add(image)
    }
    let running = try XCTUnwrap(
      NSRunningApplication.runningApplications(withBundleIdentifier: "local.macdown.modern").first)
    let bundle = try XCTUnwrap(running.bundleURL)
    let tool = bundle.appendingPathComponent("Contents/Helpers/snowfolio")
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: tool.path))
    let help = try await Self.runTool(tool, arguments: ["--help"], directory: directory)
    XCTAssertEqual(help.status, 0, help.error)
    XCTAssertTrue(help.output.contains("Usage: snowfolio"))
    let version = try await Self.runTool(tool, arguments: ["--version"], directory: directory)
    XCTAssertEqual(version.status, 0, version.error)
    XCTAssertTrue(version.output.contains("Snowfolio 0.2.0"))
    let unknown = try await Self.runTool(
      tool, arguments: ["--unknown", "never-created.md"], directory: directory)
    XCTAssertEqual(unknown.status, 64)
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("never-created.md").path))

    func source(_ text: String) -> XCUIElement {
      app.textViews.matching(
        NSPredicate(format: "identifier == 'markdownSourceEditor' AND value == %@", text)
      ).firstMatch
    }
    func waitForSource(_ text: String) async {
      let view = source(text)
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in view.exists }, object: nil)
      let result = await XCTWaiter.fulfillment(of: [ready], timeout: 8)
      if result != .completed {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "command-line-source-failure"
        image.lifetime = .keepAlways
        add(image)
      }
      XCTAssertEqual(result, .completed, app.debugDescription)
    }
    let pipedText = "# Piped notebook\r\n中文 🧊 e\u{301}\r\n"
    let pipedBytes = Data([0xEF, 0xBB, 0xBF]) + Data(pipedText.utf8)
    let warm = try await Self.runTool(
      tool, arguments: [file.lastPathComponent, "./" + file.lastPathComponent, "new.md", "--help"],
      directory: directory, input: pipedBytes, delayedInput: true)
    let launchTrace = XCTAttachment(
      string: "status=\(warm.status) seconds=\(warm.seconds)\n\(warm.error)")
    launchTrace.name = "command-line-routing-metadata"
    launchTrace.lifetime = .keepAlways
    add(launchTrace)
    XCTAssertEqual(warm.status, 0, warm.error)
    XCTAssertGreaterThanOrEqual(warm.seconds, 0.2)
    await waitForSource(pipedText)
    await waitForSource(original)
    XCTAssertEqual(
      app.windows.matching(NSPredicate(format: "title == %@", file.lastPathComponent)).count, 1)
    for name in ["new.md", "--help"] {
      let appeared = app.windows[name].firstMatch.waitForExistence(timeout: 8)
      if !appeared {
        // Fatal XCTest failures may skip Swift defers. Capture before asserting.
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "command-line-new-file-failure"
        image.lifetime = .keepAlways
        add(image)
      }
      XCTAssertTrue(appeared, app.debugDescription)
    }
    XCTAssertEqual(try Data(contentsOf: file), originalBytes)
    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("new.md")), Data())
    // After the first filename --help is a literal filename, as in the original CLI.
    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("--help")), Data())
    // These independent windows overlap exactly. Clicking the background editor's
    // coordinates reaches the front document; select its native Window menu item.
    let pipedWindow = try XCTUnwrap(
      app.windows.allElementsBoundByIndex.first { window in
        window.textViews.matching(
          NSPredicate(format: "identifier == 'markdownSourceEditor' AND value == %@", pipedText)
        ).firstMatch.exists
      })
    let windowMenu = app.menuBars.menuBarItems["Window"]
    windowMenu.click()
    let pipedItem = windowMenu.menuItems[pipedWindow.label].firstMatch
    XCTAssertTrue(pipedItem.waitForExistence(timeout: 5), app.debugDescription)
    pipedItem.click()
    XCTAssertEqual(
      app.windows.firstMatch.textViews["markdownSourceEditor"].firstMatch.value as? String,
      pipedText, app.debugDescription)
    source(pipedText).click()
    app.typeKey("s", modifierFlags: .command)
    XCTAssertTrue(app.buttons["OKButton"].firstMatch.waitForExistence(timeout: 5))
    app.typeKey("g", modifierFlags: [.command, .shift])
    let path = app.textFields["PathTextField"].firstMatch
    XCTAssertTrue(path.waitForExistence(timeout: 5))
    path.click()
    app.typeKey("a", modifierFlags: .command)
    path.typeText(directory.path + "\n")
    let name = app.textFields["saveAsNameTextField"].firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: 5))
    name.click()
    app.typeKey("a", modifierFlags: .command)
    name.typeText("piped.md")
    app.buttons["OKButton"].firstMatch.click()
    let savedPipe = directory.appendingPathComponent("piped.md")
    let saved = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in (try? Data(contentsOf: savedPipe)) == pipedBytes },
      object: nil)
    let saveResult = await XCTWaiter.fulfillment(of: [saved], timeout: 8)
    XCTAssertEqual(saveResult, .completed)
    let warmImage = XCTAttachment(screenshot: app.screenshot())
    warmImage.name = "command-line-pipe-save-and-file-reuse"
    warmImage.lifetime = .keepAlways
    add(warmImage)
    app.typeKey("w", modifierFlags: [.command, .option])
    app.typeKey("q", modifierFlags: .command)
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))

    let cold = directory.appendingPathComponent("cold.md")
    let coldText = "# Cold file\r\nkeep\r\n"
    try Data(coldText.utf8).write(to: cold)
    let coldPipe = "# Cold pipe\nArrived from stdin.\n"
    let launched = try await Self.runTool(
      tool, arguments: [cold.path], directory: directory, input: Data(coldPipe.utf8))
    XCTAssertEqual(launched.status, 0, launched.error)
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
    await waitForSource(coldText)
    await waitForSource(coldPipe)
    XCTAssertEqual(try Data(contentsOf: cold), Data(coldText.utf8))
    let coldImage = XCTAttachment(screenshot: app.screenshot())
    coldImage.name = "command-line-cold-launch-file-and-stdin"
    coldImage.lifetime = .keepAlways
    add(coldImage)
  }
}
