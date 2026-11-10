import AppKit
import Darwin
import DocumentCore
import Foundation
import SnowfolioUI
import SwiftUI

/// Development-only component measurements. Does not activate or edit the user's app.
@main
struct NativeEditorAudit {
  @MainActor
  static func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3, ["prose", "mixed", "long-line"].contains(arguments[0]),
      let bytes = Int(arguments[1]), (1_000...10_000_000).contains(bytes),
      let iterations = Int(arguments[2]), (20...500).contains(iterations)
    else {
      throw failure("Usage: NativeEditorAudit prose|mixed|long-line BYTES ITERATIONS(20...500)")
    }
    _ = NSApplication.shared
    let source = fixture(workload: arguments[0], bytes: bytes)
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let manager = UndoManager()
    manager.groupsByEvent = false
    let content = NativeMarkdownEditor(
      document: document, hostUndoManager: manager, syntaxHighlighting: false)
    let hosting = NSHostingView(rootView: content)
    // Fixed viewport is a controlled benchmark variable, not product window sizing.
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    window.contentView = hosting
    defer { window.close() }
    let clock = ContinuousClock()
    let setupStart = clock.now
    settle(hosting)
    guard let editor = textView(in: hosting), editor.textLayoutManager != nil,
      editor.string.utf8.elementsEqual(source.utf8)
    else { throw failure("Native TextKit 2 source view did not mount with the expected fixture.") }
    let setupMilliseconds = milliseconds(setupStart.duration(to: clock.now))
    // Test the start, middle and end so a late mismatch does not hide an O(n) comparison.
    var records: [[String: Any]] = []
    for (position, rawOffset) in [
      ("start", 0), ("middle", editor.string.utf16.count / 2),
      ("end", editor.string.utf16.count),
    ] {
      let text = editor.string as NSString
      var offset = rawOffset
      if offset < text.length, (0xDC00...0xDFFF).contains(text.character(at: offset)) {
        offset -= 1
      }
      editor.setSelectedRange(NSRange(location: offset, length: 0))
      var samples: [Double] = []
      let revision = document.revision
      for index in 0..<(iterations + 5) {
        editor.breakUndoCoalescing()
        manager.beginUndoGrouping()
        let start = clock.now
        editor.insertText("x", replacementRange: editor.selectedRange())
        let elapsed = milliseconds(start.duration(to: clock.now))
        manager.endUndoGrouping()
        if index >= 5 { samples.append(elapsed) }
        // Let representable reflection run between commands, outside command timing.
        settle(hosting)
      }
      guard document.revision > revision,
        document.text.utf8.elementsEqual(editor.string.utf8),
        manager.canUndo, editor.textLayoutManager != nil
      else { throw failure("Insertion did not update the real model/Undo/TextKit 2 state.") }
      let edited = document.text
      for _ in 0..<(iterations + 5) { manager.undo() }
      settle(hosting)
      guard document.text.utf8.elementsEqual(source.utf8),
        editor.string.utf8.elementsEqual(source.utf8), manager.canRedo
      else { throw failure("Native Undo did not restore the exact fixture.") }
      manager.redo()
      settle(hosting)
      guard document.text.utf8.elementsEqual(editor.string.utf8),
        !document.text.utf8.elementsEqual(source.utf8),
        document.text.utf8.count == source.utf8.count + 1,
        edited.utf8.count == source.utf8.count + iterations + 5
      else { throw failure("Native Redo did not restore one insertion.") }
      manager.undo()
      settle(hosting)
      guard document.text.utf8.elementsEqual(source.utf8) else {
        throw failure("Final native Undo did not preserve the fixture.")
      }
      manager.removeAllActions()
      let sorted = samples.sorted()
      records.append([
        "position": position, "samplesMilliseconds": samples,
        "medianMilliseconds": sorted[sorted.count / 2],
        "p95Milliseconds": sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
        "maximumMilliseconds": sorted.last ?? 0,
      ])
    }
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw failure("getrusage failed.") }
    let record: [String: Any] = [
      "workload": arguments[0], "fixtureBytes": source.utf8.count,
      "iterationsPerPosition": iterations, "discardedWarmupsPerPosition": 5,
      "viewport": ["width": 800, "height": 600],
      "initialMountMilliseconds": setupMilliseconds, "positions": records,
      "processPeakResidentBytes": usage.ru_maxrss,
      "exactSourceUndoRedo": true, "textKit2": true,
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
      "scope":
        "NativeMarkdownEditor component synchronous insertText command through the actual delegate/model/Undo pipeline; syntax disabled, hidden fixed viewport. Excludes keyboard event delivery, visible layout/painting, full workspace, background parser/preview, file IO, app launch and energy. Not end-to-end typing p95 or full M6 acceptance.",
    ]
    let data = try JSONSerialization.data(
      withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }

  @MainActor
  private static func textView(in view: NSView) -> NSTextView? {
    if let editor = view as? NSTextView,
      editor.identifier?.rawValue == "markdownSourceEditor"
    {
      return editor
    }
    for child in view.subviews {
      if let editor = textView(in: child) { return editor }
    }
    return nil
  }

  @MainActor
  private static func settle(_ view: NSView) {
    view.layoutSubtreeIfNeeded()
    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
    view.layoutSubtreeIfNeeded()
  }

  private static func fixture(workload: String, bytes: Int) -> String {
    let unit: String
    switch workload {
    case "mixed":
      unit = """
        ## A notebook section

        Local **Markdown**, [a link](https://example.invalid), 中文 👩‍💻 é and `code`.

        1. First item
        2. Second item

        | Column | Value |
        | --- | --- |
        | One | Two |

        ```swift
        let title = "Snowfolio"
        ```

        """ + "\n"
    case "long-line": unit = "Unicode 中文 👩‍💻 **bold** and `code` in a long paragraph. "
    default: unit = "A calm paragraph for writing and reading with Unicode 中文 👩‍💻 é.\n\n"
    }
    return String(repeating: unit, count: bytes / unit.utf8.count)
      + String(repeating: "x", count: bytes % unit.utf8.count)
  }

  private static func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "NativeEditorAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
