import AppKit

/// First-party, test-only structural implementation of the original plug-in API.
/// This bundle is copied into the UI test runner, never the shipped app.
@objc(SnowfolioPluginFixture)
@MainActor
final class SnowfolioPluginFixture: NSObject {
  private var runs = 0

  override init() {
    super.init()
    record("construct")
  }

  @objc var name: String {
    record("name")
    return "Glacial Fixture"
  }

  @objc func plugInDidInitialize() { record("initialize") }

  @objc func run(_ sender: AnyObject?) -> Bool {
    runs += 1
    record("run:\(runs)")
    guard runs <= 2, sender is NSMenuItem,
      let document = NSDocumentController.shared.currentDocument,
      document.fileURL?.lastPathComponent == "plugin-encoding.md",
      document.responds(to: NSSelectorFromString("markdown")),
      document.responds(to: NSSelectorFromString("setMarkdown:")),
      let source = document.value(forKey: "markdown") as? String
    else { return false }
    let original = "# Native plug-in\r\n中文 👩‍💻 e\u{301}\r\n"
    let expected = runs == 1 ? original : original + "\r\nPlug-in run 1 🧊"
    guard source.utf8.elementsEqual(expected.utf8) else { return false }
    document.setValue(source + "\r\nPlug-in run \(runs) 🧊", forKey: "markdown")
    return true
  }

  private func record(_ event: String) {
    guard let path = ProcessInfo.processInfo.environment["SNOWFOLIO_PLUGIN_FIXTURE_EVENTS"] else {
      return
    }
    let url = URL(fileURLWithPath: path)
    let existing = (try? Data(contentsOf: url)) ?? Data()
    try? (existing + Data((event + "\n").utf8)).write(to: url)
  }
}
