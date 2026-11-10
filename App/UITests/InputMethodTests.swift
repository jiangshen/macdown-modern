#if NATIVE_DOCUMENT_HOST
  import AppKit
  import ApplicationServices
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
      let transcript = Mutex(["AX trusted=\(AXIsProcessTrusted())"])
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
      transcript.withLock {
        $0.append("Selected system Pinyin; original=\(InputSources.id(input.original))")
      }
      let running = try XCTUnwrap(
        NSRunningApplication.runningApplications(withBundleIdentifier: "local.macdown.modern").first
      )
      let application = AXUIElementCreateApplication(running.processIdentifier)
      func attribute(_ element: AXUIElement, _ name: CFString) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        return (error, value)
      }
      let focus = attribute(application, kAXFocusedUIElementAttribute as CFString)
      transcript.withLock { $0.append("Focused AX query=\(focus.0.rawValue)") }
      XCTAssertEqual(focus.0, .success, "Read-only AX permission is required; do not bypass it")
      let focused = try XCTUnwrap(focus.1) as! AXUIElement
      XCTAssertEqual(
        attribute(focused, kAXIdentifierAttribute as CFString).1 as? String, "markdownSourceEditor")
      func markedRange() -> CFRange? {
        let result = attribute(
          focused, NSAccessibility.Attribute.textInputMarkedRangeAttribute.rawValue as CFString)
        guard result.0 == .success, let raw = result.1, CFGetTypeID(raw) == AXValueGetTypeID()
        else {
          return nil
        }
        let value = raw as! AXValue
        var range = CFRange()
        guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else {
          return nil
        }
        return range
      }
      app.typeKey("n", modifierFlags: [])
      app.typeKey("i", modifierFlags: [])
      let marked = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in (markedRange()?.length ?? 0) > 0 }, object: nil)
      let markedOutcome = XCTWaiter().wait(for: [marked], timeout: 8)
      let range = markedRange()
      let preedit = editor.value as? String ?? ""
      let rawMarked = attribute(
        focused, NSAccessibility.Attribute.textInputMarkedRangeAttribute.rawValue as CFString)
      transcript.withLock {
        $0.append(
          "marked query=\(rawMarked.0.rawValue), range=\(String(describing: range)), source=\(preedit.debugDescription)"
        )
      }
      let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      image.name = "native-pinyin-live-marked-candidates"
      image.lifetime = .keepAlways
      add(image)
      let candidates = XCUIApplication(bundleIdentifier: "com.apple.inputmethod.SCIM")
      let candidateTree = XCTAttachment(
        string: "state=\(candidates.state.rawValue)\n"
          + (candidates.state == .notRunning ? "not running" : candidates.debugDescription))
      candidateTree.name = "native-pinyin-candidate-state"
      candidateTree.lifetime = .keepAlways
      add(candidateTree)
      XCTAssertEqual(
        markedOutcome, .completed, "Real system keystrokes must produce marked preedit")
      let actualRange = try XCTUnwrap(range)
      XCTAssertEqual(actualRange.location, original.utf16.count)
      XCTAssertEqual(actualRange.length, 2)
      XCTAssertEqual(preedit, original + "ni")
      app.typeKey(" ", modifierFlags: [])
      let committed = original + "你"
      expectSource(committed)
      XCTAssertTrue(markedRange() == nil || markedRange()?.length == 0)
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
        $0.append("Real marked ni → 你; Undo/Redo and Save preserve UTF16LE BOM/CRLF/Unicode bytes.")
      }
    }
  }
#endif
