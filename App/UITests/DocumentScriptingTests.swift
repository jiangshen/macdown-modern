#if NATIVE_DOCUMENT_HOST
  import AppKit
  import XCTest

  /// Exercise Snowfolio's public scripting interface in its actual app process.
  /// AppleScript is not used to control another app or drive desktop UI.
  final class DocumentScriptingTests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
      continueAfterFailure = false
      let app = XCUIApplication()
      app.launchArguments = [
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
        "-preferDocumentTabs", "NO", "-markdownManualRender", "YES",
        "-htmlSyntaxHighlighting", "NO", "-readingStyleSelection", "snowfolio",
      ]
      app.launch()
      return app
    }

    private func escaped(_ value: String) -> String {
      value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func literal(_ value: String) -> String {
      "(\""
        + escaped(value)
        .replacingOccurrences(of: "\r", with: "\" & (character id 13) & \"")
        .replacingOccurrences(of: "\n", with: "\" & (character id 10) & \"") + "\")"
    }

    @MainActor
    private func execute(_ body: String) throws -> NSAppleEventDescriptor {
      let target = try XCTUnwrap(
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.macdown.modern")
          .first?.bundleURL)
      // Use the running test bundle's dictionary, not an older installed copy.
      let script = try XCTUnwrap(
        NSAppleScript(
          source: """
            tell application "\(escaped(target.path))"
            \(body)
            end tell
            """))
      var error: NSDictionary?
      let result = script.executeAndReturnError(&error)
      if let error {
        throw NSError(
          domain: "SnowfolioDocumentScripting",
          code: (error["NSAppleScriptErrorNumber"] as? Int) ?? -1,
          userInfo: [NSLocalizedDescriptionKey: error.description])
      }
      return result
    }

    @MainActor
    private func waitForSource(_ expected: String, in app: XCUIApplication) -> XCUIElement {
      let editor = app.textViews["markdownSourceEditor"].firstMatch
      let ready = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in editor.exists && editor.value as? String == expected },
        object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 8), .completed, app.debugDescription)
      return editor
    }

    @MainActor
    func testScriptedTextUndoAutosaveAndManualHTMLCache() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioScriptEvents-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let file = directory.appendingPathComponent("scripting-encoding.md")
      let original = "# Script original 中文 👩‍💻\r\n\r\ne\u{301}\r\n"
      let replacement = "# Script changed 中文 👩‍💻\r\n\r\ne\u{301} retained\r\n"
      let bom = Data([0xFF, 0xFE])
      try (bom + XCTUnwrap(original.data(using: .utf16LittleEndian))).write(to: file)
      let app = launch()
      defer { app.terminate() }
      let document = "document \(literal(file.lastPathComponent))"
      let opened = try execute(
        "open (POSIX file \(literal(file.path)))\nreturn text of \(document)")
      XCTAssertEqual(opened.stringValue, original)
      let editor = waitForSource(original, in: app)
      XCTAssertEqual(try execute("return name of \(document)").stringValue, file.lastPathComponent)
      XCTAssertEqual(
        try execute("return POSIX path of (file of \(document))").stringValue, file.path)
      let firstRender = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          (try? self.execute("return html of \(document)").stringValue)?.contains("Script original")
            == true
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [firstRender], timeout: 8), .completed)
      let cached = try XCTUnwrap(execute("return html of \(document)").stringValue)
      _ = try execute("set text of \(document) to \(literal(replacement))")
      _ = waitForSource(replacement, in: app)
      XCTAssertEqual(try execute("return html of \(document)").stringValue, cached)
      XCTAssertTrue(try execute("return modified of \(document)").booleanValue)
      editor.click()
      app.typeKey("z", modifierFlags: .command)
      _ = waitForSource(original, in: app)
      app.typeKey("z", modifierFlags: [.command, .shift])
      _ = waitForSource(replacement, in: app)
      let expectedBytes = bom + (try XCTUnwrap(replacement.data(using: .utf16LittleEndian)))
      let autosaved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == expectedBytes },
        object: nil)
      // No script or keyboard Save precedes this active autosave assertion.
      XCTAssertEqual(XCTWaiter().wait(for: [autosaved], timeout: 35), .completed)
      XCTAssertEqual(try execute("return html of \(document)").stringValue, cached)
      app.buttons["Render"].firstMatch.click()
      let refreshed = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          (try? self.execute("return html of \(document)").stringValue)?.contains("Script changed")
            == true
        }, object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [refreshed], timeout: 8), .completed)
      let screenshot = XCTAttachment(screenshot: app.screenshot())
      screenshot.name = "native-scripted-document"
      screenshot.lifetime = .keepAlways
      add(screenshot)
      _ = try execute("save \(document)\nclose \(document) saving yes")
      XCTAssertEqual(try Data(contentsOf: file), expectedBytes)
      _ = try execute("quit saving no")
      XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }

    @MainActor
    func testScriptedCreationSaveFormatsAndClose() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioScriptFormats-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let app = launch()
      defer { app.terminate() }
      for format in ["Markdown", "Text", "Data"] {
        let file = directory.appendingPathComponent("script-\(format).md")
        let source = "# \(format) 中文 👩‍💻\r\ne\u{301}\r\n"
        let result = try execute(
          """
          set d to make new document with properties {text:\(literal(source))}
          save d in (POSIX file \(literal(file.path))) as \(format)
          set savedText to text of d
          close d saving no
          return savedText
          """)
        XCTAssertEqual(result.stringValue, source)
        let saved = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == Data(source.utf8) },
          object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 8), .completed)
      }
      _ = try execute("quit saving no")
      XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }
  }
#endif
