#if NATIVE_DOCUMENT_HOST
  import AppKit
  import Carbon.HIToolbox
  import Synchronization
  import XCTest

  /// Real system input-method coverage on a disposable desktop, without an app backdoor.
  final class InputMethodTests: XCTestCase {
    @MainActor
    private final class InputSources {
      let original = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
      let sources: [TISInputSource]
      let initiallyEnabled: [Bool]

      init() throws {
        let filter = [kTISPropertyBundleID as String: "com.apple.inputmethod.SCIM"] as CFDictionary
        let available = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
        let all = available as! [TISInputSource]
        let parent = try XCTUnwrap(all.first { Self.id($0) == "com.apple.inputmethod.SCIM" })
        let pinyin = try XCTUnwrap(all.first { Self.id($0) == "com.apple.inputmethod.SCIM.ITABC" })
        sources = [parent, pinyin]
        initiallyEnabled = sources.map(Self.enabled)
      }

      static func id(_ source: TISInputSource) -> String {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
          return ""
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
      }

      static func enabled(_ source: TISInputSource) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else {
          return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
      }

      func selectPinyin() {
        for source in sources where !Self.enabled(source) {
          XCTAssertEqual(TISEnableInputSource(source), noErr)
        }
        XCTAssertEqual(TISSelectInputSource(sources[1]), noErr)
        XCTAssertEqual(
          Self.id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()), Self.id(sources[1]))
      }

      func restore() {
        XCTAssertEqual(TISSelectInputSource(original), noErr)
        for index in sources.indices.reversed() where !initiallyEnabled[index] {
          XCTAssertEqual(TISDisableInputSource(sources[index]), noErr)
        }
        XCTAssertEqual(
          Self.id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()), Self.id(original))
        XCTAssertEqual(sources.map(Self.enabled), initiallyEnabled)
      }
    }

    @MainActor
    func testRealPinyinMarkedCompositionCommitUndoRedoAndEncodedSave() throws {
      continueAfterFailure = false
      executionTimeAllowance = 180
      let manager = FileManager.default
      let directory = manager.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("Snowfolio-Pinyin-" + UUID().uuidString)
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      addTeardownBlock { try? manager.removeItem(at: directory) }
      let file = directory.appendingPathComponent("pinyin-native.md")
      let original = "# Input check\r\n\r\nUnicode 👩‍💻 e\u{301}\r\n\r\n"
      func encoded(_ value: String) throws -> Data {
        Data([0xff, 0xfe]) + (try XCTUnwrap(value.data(using: .utf16LittleEndian)))
      }
      let originalBytes = try encoded(original)
      try originalBytes.write(to: file)
      let app = XCUIApplication()
      app.launchArguments = [
        "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
        "-AppleWindowTabbingMode", "manual", "-preferDocumentTabs", "NO",
        "-readingStyleSelection", "snowfolio", "-markdownManualRender", "NO",
      ]
      app.launch()
      addTeardownBlock { @MainActor in app.terminate() }
      let transcript = Mutex(["Public TIS input selection and XCTest candidate UI"])
      addTeardownBlock { @MainActor in
        let text = XCTAttachment(string: transcript.withLock { $0.joined(separator: "\n") })
        text.name = "native-pinyin-transcript"
        text.lifetime = .keepAlways
        self.add(text)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "native-pinyin-final-state"
        tree.lifetime = .keepAlways
        self.add(tree)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "native-pinyin-final-desktop"
        shot.lifetime = .keepAlways
        self.add(shot)
      }
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
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      let input = try InputSources()
      // Teardown blocks run even if XCTest interrupts this method at an assertion.
      addTeardownBlock { @MainActor in input.restore() }
      input.selectPinyin()
      // Reestablish the text client after the asynchronous system source change.
      editor.click()
      app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: .command)
      transcript.withLock {
        $0.append("Selected system Pinyin; original=\(InputSources.id(input.original))")
      }
      let candidates = XCUIApplication(bundleIdentifier: "com.apple.inputmethod.SCIM")
      func compose(_ phase: String) {
        // typeText/paste can bypass the input method. Real individual keys must
        // produce both preedit and an actual Chinese candidate in the system UI.
        app.typeKey("n", modifierFlags: [])
        app.typeKey("i", modifierFlags: [])
        let candidate = candidates.descendants(matching: .any).matching(
          NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "你", "你")
        ).firstMatch
        let ready = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in
            candidates.state != .notRunning && candidate.exists
          }, object: nil)
        let available = XCTWaiter().wait(for: [ready], timeout: 8) == .completed
        let preedit = editor.value as? String ?? ""
        transcript.withLock {
          $0.append("\(phase): candidate=\(available), preedit=\(preedit.debugDescription)")
          $0.append(
            "sourceAfterKeys=\(InputSources.id(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))"
          )
          $0.append(
            "inputProcesses="
              + NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter {
                $0.localizedCaseInsensitiveContains("input")
              }.joined(separator: ","))
        }
        let tree = XCTAttachment(
          string: "state=\(candidates.state.rawValue)\n"
            + (candidates.state == .notRunning ? "not running" : candidates.debugDescription))
        tree.name = "native-pinyin-candidates-" + phase
        tree.lifetime = .keepAlways
        self.add(tree)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "native-pinyin-live-preedit-" + phase
        image.lifetime = .keepAlways
        self.add(image)
        XCTAssertTrue(available, "The real system candidate UI must offer 你")
        expectSource(original + "ni")
        XCTAssertEqual(try? Data(contentsOf: file), originalBytes)
      }
      compose("cancel")
      app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
      expectSource(original)
      XCTAssertEqual(try Data(contentsOf: file), originalBytes)
      compose("commit")
      app.typeKey(" ", modifierFlags: [])
      let committed = original + "你"
      expectSource(committed)
      app.typeKey("s", modifierFlags: .command)
      XCTAssertEqual(try Data(contentsOf: file), try encoded(committed))
      app.typeKey("z", modifierFlags: .command)
      expectSource(original)
      app.typeKey("z", modifierFlags: [.command, .shift])
      expectSource(committed)
      app.typeKey("s", modifierFlags: .command)
      XCTAssertEqual(try Data(contentsOf: file), try encoded(committed))
      app.typeKey("z", modifierFlags: .command)
      expectSource(original)
      app.typeKey("s", modifierFlags: .command)
      XCTAssertEqual(try Data(contentsOf: file), originalBytes)
      transcript.withLock {
        $0.append(
          "Real Pinyin candidate/preedit, Escape cancellation, ni → 你; Undo/Redo and Save preserve UTF16LE BOM/CRLF/Unicode bytes."
        )
      }
    }
  }
#endif
