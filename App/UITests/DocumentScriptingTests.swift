#if NATIVE_DOCUMENT_HOST
  import AppKit
  import Carbon
  import Synchronization
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
      #if TEMPORARY_SCRIPTING_CONSENT_APPROVED
        approveTemporaryAutomationConsent(in: app)
      #endif
      return app
    }

    #if TEMPORARY_SCRIPTING_CONSENT_APPROVED
      private final class PermissionResult: Sendable {
        let status = Mutex<OSStatus?>(nil)
      }

      @MainActor
      private func approveTemporaryAutomationConsent(in app: XCUIApplication) {
        // The user authorized this exact prompt on disposable test machines.
        // This build flag is supplied only by the temporary hosted test scopes.
        let monitor = addUIInterruptionMonitor(withDescription: "Snowfolio test automation consent")
        {
          alert in
          let text =
            alert.label + " "
            + alert.staticTexts.allElementsBoundByIndex.map {
              $0.label + " " + ($0.value as? String ?? "")
            }.joined(separator: " ")
          guard text.contains("SnowfolioUITests-Runner"),
            text.contains("“Snowfolio”") || text.contains("\"Snowfolio\""),
            alert.buttons["Allow"].exists
          else { return false }
          alert.buttons["Allow"].click()
          return true
        }
        defer { removeUIInterruptionMonitor(monitor) }
        let permission = PermissionResult()
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        // Apple's synchronous permission API explicitly requires a background
        // thread. Keep the test's main thread available for the native prompt.
        queue.addOperation { @Sendable in
          let address = NSAppleEventDescriptor(bundleIdentifier: "local.macdown.modern")
          let status = AEDeterminePermissionToAutomateTarget(
            address.aeDesc, AEEventClass(kAECoreSuite), AEEventID(kAEGetData), true)
          permission.status.withLock { $0 = status }
        }
        // These installed system app identifiers were verified from their Info.plists.
        // macOS may present this prompt outside the tested app's interruption tree.
        let promptOwnerIDs = ["com.apple.coreservices.uiagent", "com.apple.UserNotificationCenter"]
        let promptOwners = promptOwnerIDs.map { XCUIApplication(bundleIdentifier: $0) }
        let render = app.buttons["Render"].firstMatch
        XCTAssertTrue(render.waitForExistence(timeout: 8))
        let finished = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in
            if permission.status.withLock({ $0 != nil }) { return true }
            for owner in promptOwners where owner.state != .notRunning {
              let containers =
                owner.alerts.allElementsBoundByIndex
                + owner.dialogs.allElementsBoundByIndex + owner.windows.allElementsBoundByIndex
              for window in containers {
                let text =
                  window.label + " "
                  + window.staticTexts.allElementsBoundByIndex.map {
                    $0.label + " " + ($0.value as? String ?? "")
                  }.joined(separator: " ")
                guard text.contains("SnowfolioUITests-Runner"),
                  text.contains("wants access to control"),
                  text.contains("“Snowfolio”") || text.contains("\"Snowfolio\""),
                  window.buttons["Allow"].exists
                else { continue }
                let image = XCTAttachment(screenshot: window.screenshot())
                image.name = "authorized-own-app-consent-prompt"
                image.lifetime = .keepAlways
                self.add(image)
                window.buttons["Allow"].click()
                return permission.status.withLock { $0 != nil }
              }
            }
            // Retain the ordinary app interruption path if the system attaches
            // the prompt there; all acceptance remains guarded to the same pair.
            render.click()
            return permission.status.withLock { $0 != nil }
          }, object: nil)
        let outcome = XCTWaiter().wait(for: [finished], timeout: 35)
        let status = permission.status.withLock { $0 }
        let record = XCTAttachment(
          string:
            "temporaryOwnAppPermission=\(String(describing: status)) outcome=\(outcome.rawValue)")
        record.name = "native-script-consent-result"
        record.lifetime = .keepAlways
        add(record)
        if outcome != .completed {
          let owners = promptOwners.enumerated().map { index, owner in
            "owner=\(promptOwnerIDs[index]) state=\(owner.state.rawValue)\n"
              + (owner.state == .notRunning ? "not running" : owner.debugDescription)
          }.joined(separator: "\n")
          let diagnostic = XCTAttachment(
            string:
              "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")\n"
              + owners)
          diagnostic.name = "temporary-consent-owner-state"
          diagnostic.lifetime = .keepAlways
          add(diagnostic)
        }
        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(status, OSStatus(noErr))
      }
    #endif

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
      let running = try XCTUnwrap(
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.macdown.modern")
          .first)
      let target = try XCTUnwrap(running.bundleURL)
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
        let observation = XCTAttachment(
          string: """
            targetPID=\(running.processIdentifier) bundle=\(running.bundleIdentifier ?? "nil")
            finishedLaunching=\(running.isFinishedLaunching) terminated=\(running.isTerminated)
            target=\(target.path)
            script=\(script.source ?? "nil")
            error=\(error)
            """)
        observation.name = "native-script-event-failure"
        observation.lifetime = .keepAlways
        add(observation)
        if !running.isTerminated {
          let image = XCTAttachment(screenshot: XCUIApplication().screenshot())
          image.name = "native-script-target-on-failure"
          image.lifetime = .keepAlways
          add(image)
        }
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
        try execute("return file of \(document)").fileURLValue?.standardizedFileURL,
        file.standardizedFileURL)
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
    func testScriptedInitialDataObjectReferencesAndReadOnlyErrors() throws {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "SnowfolioScriptContracts-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: directory) }
      let file = directory.appendingPathComponent("initial-data.md")
      let source = "# Initial data 中文 👩‍💻\r\ne\u{301}\r\n"
      let app = launch()
      defer { app.terminate() }
      let initialDocuments = try execute("return documents")
      XCTAssertEqual(initialDocuments.descriptorType, typeAEList)
      let initialCount = initialDocuments.numberOfItems
      let made = try execute(
        "make new document with data \(literal(source))\nreturn text of document 1")
      XCTAssertEqual(made.stringValue, source)
      _ = waitForSource(source, in: app)
      XCTAssertEqual(try execute("return documents").numberOfItems, initialCount + 1)
      XCTAssertEqual(try execute("return text of item 1 of documents").stringValue, source)
      XCTAssertEqual(try execute("return text of document of window 1").stringValue, source)
      XCTAssertGreaterThan(try execute("return id of window 1").int32Value, 0)
      let beforeHTML = try execute("return html of document 1").stringValue
      do {
        _ = try execute("set html of document 1 to \(literal("Must remain read only"))")
        XCTFail("The public read-only HTML property must reject assignment")
      } catch let error as NSError {
        XCTAssertEqual(error.code, -10006)
      }
      XCTAssertEqual(try execute("return html of document 1").stringValue, beforeHTML)
      XCTAssertEqual(try execute("return text of document 1").stringValue, source)
      do {
        _ = try execute("return text of document \(literal(UUID().uuidString))")
        XCTFail("A nonexistent document must report an object-resolution error")
      } catch let error as NSError {
        XCTAssertEqual(error.code, -1728)
      }
      _ = try execute(
        "close document 1 saving yes saving in (POSIX file \(literal(file.path)))")
      let saved = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (try? Data(contentsOf: file)) == Data(source.utf8) },
        object: nil)
      XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 8), .completed)
      XCTAssertEqual(try execute("return documents").numberOfItems, initialCount)
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
      // Text is also an AppleScript type keyword. Send the dictionary's exact
      // public enumeration codes so lexical ambiguity cannot alter this event.
      for (format, eventCode) in [("Markdown", "md  "), ("Text", "txt "), ("Data", "data")] {
        let file = directory.appendingPathComponent("script-\(format).md")
        let source = "# \(format) 中文 👩‍💻\r\ne\u{301}\r\n"
        let result = try execute(
          """
          set d to make new document with properties {text:\(literal(source))}
          save d in (POSIX file \(literal(file.path))) as «constant savf\(eventCode)»
          -- Cocoa returned a name specifier for the untitled document. Save
          -- changes that name, so resolve its new public document name.
          set savedDocument to document \(literal(file.lastPathComponent))
          set savedText to text of savedDocument
          close savedDocument saving no
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
