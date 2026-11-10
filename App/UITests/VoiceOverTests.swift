#if NATIVE_DOCUMENT_HOST
  import AppKit
  import Synchronization
  import XCTest

  final class VoiceOverTests: XCTestCase {
    @MainActor
    func testNativeSourceAndToolbarSpeechNavigationPreserveEncodedUndo() throws {
      continueAfterFailure = false
      executionTimeAllowance = 180
      let manager = FileManager.default
      let directory = manager.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("Snowfolio-VoiceOver-" + UUID().uuidString)
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      addTeardownBlock { try? manager.removeItem(at: directory) }
      let file = directory.appendingPathComponent("voiceover-native.md")
      let original = "# VoiceOver notebook\r\n\r\nA native paragraph. 中文 👩‍💻 e\u{301}\r\n"
      let bytes = Data([0xff, 0xfe]) + (try XCTUnwrap(original.data(using: .utf16LittleEndian)))
      try bytes.write(to: file)
      let app = XCUIApplication()
      app.launchArguments = [
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
        "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
        "-readingStyleSelection", "snowfolio", "-markdownManualRender", "NO",
      ]
      app.launch()
      addTeardownBlock { @MainActor in app.terminate() }
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
      let window = app.windows.matching(NSPredicate(format: "title == %@", file.lastPathComponent))
        .firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: 8), app.debugDescription)
      let editor = window.textViews["markdownSourceEditor"].firstMatch
      XCTAssertTrue(editor.waitForExistence(timeout: 8))
      func expectSource(_ source: String) {
        let ready = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in
            guard let value = editor.value as? String else { return false }
            return value.utf8.elementsEqual(source.utf8)
          }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [ready], timeout: 8), .completed, app.debugDescription)
      }
      expectSource(original)
      let service = XCUIDevice.shared.voiceOverService
      let initiallyEnabled = service.isEnabled
      let transcript = Mutex(["VoiceOver initially enabled=\(initiallyEnabled)"])
      addTeardownBlock { @MainActor in
        if !initiallyEnabled && service.isEnabled { try service.disable() }
        XCTAssertEqual(service.isEnabled, initiallyEnabled, "Restore the original VoiceOver state")
      }
      // XCTest's stop-on-failure interruption can bypass Swift defer. Registered
      // teardown blocks preserve evidence and restore the disposable desktop.
      addTeardownBlock { @MainActor in
        let record = XCTAttachment(string: transcript.withLock { $0.joined(separator: "\n") })
        record.name = "native-voiceover-speech"
        record.lifetime = .keepAlways
        self.add(record)
        let tree = XCTAttachment(string: app.debugDescription + "\n" + service.debugDescription)
        tree.name = "native-voiceover-state"
        tree.lifetime = .keepAlways
        self.add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "native-voiceover-source-and-toolbar"
        shot.lifetime = .keepAlways
        self.add(shot)
      }
      func speech(_ phase: String, _ action: () throws -> XCUIVoiceOverService.Output) throws
        -> String
      {
        let value = try action().utterance
        transcript.withLock { $0.append(phase + ": " + value) }
        XCTAssertFalse(value.isEmpty, "VoiceOver must produce actual speech")
        return value
      }
      if !initiallyEnabled { try service.enable() }
      XCTAssertTrue(service.isEnabled)
      app.activate()
      editor.click()
      // Mouse/keyboard focus and the VoiceOver cursor are independent. Move the
      // cursor explicitly rather than accepting the startup greeting as speech.
      app.typeKey(.F4, modifierFlags: [.control, .option, .shift, .function])
      _ = try speech("source-value", { try service.currentSpeech() })
      // Focusing an active text area reads its current line. Ask VoiceOver to
      // describe the focused item to verify its spoken label and role as well.
      app.typeKey(.F3, modifierFlags: [.control, .option, .function])
      let sourceSpeech = try speech("source-description", { try service.currentSpeech() })
      XCTAssertTrue(sourceSpeech.localizedCaseInsensitiveContains("Markdown source"), sourceSpeech)
      XCTAssertTrue(
        sourceSpeech.localizedCaseInsensitiveContains("text")
          || sourceSpeech.localizedCaseInsensitiveContains("edit"), sourceSpeech)
      _ = try speech("forward", { try service.moveForward() })
      let backward = try speech("backward", { try service.moveBackward() })
      XCTAssertTrue(backward.localizedCaseInsensitiveContains("Markdown source"), backward)
      // Navigate through VoiceOver to the toolbar and activate its real control.
      app.typeKey(.home, modifierFlags: [.control, .option, .command])
      _ = try speech("window-top", { try service.currentSpeech() })
      var foundRender = false
      for step in 0..<32 {
        var value = try speech("toolbar-\(step)", { try service.moveForward() })
        if value.localizedCaseInsensitiveContains("toolbar") {
          value = try speech("enter-toolbar", { try service.moveIn() })
        }
        if value.localizedCaseInsensitiveContains("Render")
          || value.localizedCaseInsensitiveContains("Update the Markdown preview"),
          value.localizedCaseInsensitiveContains("button")
        {
          foundRender = true
          break
        }
      }
      XCTAssertTrue(foundRender, transcript.withLock { $0.joined(separator: "\n") })
      app.typeKey(" ", modifierFlags: [.control, .option])
      expectSource(original)
      XCTAssertEqual(try Data(contentsOf: file), bytes)
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      editor.typeText("VoiceOver edit")
      expectSource(original + "VoiceOver edit")
      app.typeKey("z", modifierFlags: .command)
      expectSource(original)
      app.typeKey("s", modifierFlags: .command)
      XCTAssertEqual(try Data(contentsOf: file), bytes)
      transcript.withLock {
        $0.append("Native typing/Undo/Save retains exact UTF16LE BOM/CRLF/Unicode bytes.")
      }
    }
  }
#endif
