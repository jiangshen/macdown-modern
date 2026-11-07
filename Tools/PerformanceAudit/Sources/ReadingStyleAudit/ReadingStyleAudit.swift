import AppKit
import Foundation
import RenderingCore
import WebKit

/// Development-only WebKit bridge/layout measurements. This executable is never
/// linked into the application and its fixture contains no user documents.
@main
@MainActor
struct ReadingStyleAudit {
  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3, let bytes = Int(arguments[0]),
      (100_000...10_000_000).contains(bytes), let iterations = Int(arguments[1]),
      (2...100).contains(iterations)
    else {
      throw NSError(
        domain: "ReadingStyleAudit", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Usage: ReadingStyleAudit HTML_BYTES ITERATIONS BASELINE_JS_FILE"
        ])
    }
    let baseline = try String(contentsOfFile: arguments[2], encoding: .utf8)
    try await run(bytes: bytes, iterations: iterations, baseline: baseline)
  }

  static func run(bytes: Int, iterations: Int, baseline: String) async throws {
    _ = NSApplication.shared
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 400), configuration: configuration)
    let host = NSWindow(
      contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
    host.isReleasedWhenClosed = false
    host.contentView = web
    defer {
      web.stopLoading()
      host.contentView = nil
      host.close()
    }
    let unit =
      "<p data-sourcepos='1:1-1:16'>Writing 中文 words <strong>bold</strong> and <code>code</code>.</p>"
    let body = String(repeating: unit, count: max(2, bytes / unit.utf8.count))
    web.loadHTMLString(PreviewHTML.document(body: body), baseURL: nil)
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    var ready = false
    while ContinuousClock.now < deadline {
      if (try? await web.callAsyncJavaScript(
        "return document.querySelectorAll('p').length > 1;", arguments: [:], in: nil,
        contentWorld: .defaultClient)) as? Bool == true
      {
        ready = true
        break
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    guard ready else { throw CocoaError(.coderReadCorrupt) }
    _ = try await web.callAsyncJavaScript(
      """
      window.scrollTo(0,500);
      const p=document.querySelectorAll('p');
      window.getSelection().setBaseAndExtent(p[1].firstChild,6,p[0].firstChild,2);
      window.expectedSelection=window.getSelection().getRangeAt(0).toString();
      await document.fonts.ready; return true;
      """, arguments: [:], in: nil, contentWorld: .defaultClient)
    var records: [[String: Any]] = []
    var size = 16.0
    for roundIndex in 0..<iterations {
      var order = [("before", baseline), ("after", PreviewHTML.updateStyle)]
      if roundIndex.isMultiple(of: 2) == false { order.reverse() }
      for (version, script) in order {
        size = size == 16 ? 18 : 16
        let style = DocumentStyle(textSize: size)
        let wrapped =
          "const started=performance.now(); const ok=(()=>{\n" + script
          + "\n})(); return {milliseconds:performance.now()-started,ok,selected:window.getSelection().getRangeAt(0).toString()===window.expectedSelection};"
        guard
          let value = try await web.callAsyncJavaScript(
            wrapped, arguments: ["css": style.css, "codeCSS": style.codeCSS, "bodyRoot": false],
            in: nil, contentWorld: .defaultClient) as? [String: Any],
          let elapsed = value["milliseconds"] as? Double, elapsed.isFinite,
          value["ok"] as? Bool == true, value["selected"] as? Bool == true
        else { throw CocoaError(.coderReadCorrupt) }
        records.append([
          "version": version, "round": roundIndex, "pointSize": size, "milliseconds": elapsed,
        ])
      }
    }
    let output: [String: Any] = [
      "fixtureHTMLBytes": body.utf8.count, "targetBytes": bytes, "iterationsPerVersion": iterations,
      "records": records,
      "scope":
        "WebKit isolated-world script and forced CSS layout for native notebook typography changes; selection retained. Excludes app launch, parsing, typing, SwiftUI, publication IPC and compositor paint. Hidden fixed 700x400 native window; alternating version order, 16/18px font size.",
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    let data = try JSONSerialization.data(
      withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
