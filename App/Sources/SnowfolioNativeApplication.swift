#if NATIVE_DOCUMENT_HOST
  import AppKit
  import SnowfolioUI

  /// The full native document host is selected explicitly for migration checks.
  /// NSDocumentController owns documents, windows, file coordination and quit/save.
  @main
  @MainActor
  final class SnowfolioNativeApplication: NSObject, NSApplicationDelegate {
    private var menus: NativeApplicationMenuController?

    static func main() {
      let application = NSApplication.shared
      let delegate = SnowfolioNativeApplication()
      application.delegate = delegate
      application.setActivationPolicy(.regular)
      withExtendedLifetime(delegate) { application.run() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
      guard menus == nil else { return }
      NativeMarkdownDocument.registerScriptingCoercions()
      NSDocumentController.shared.autosavingDelay = 2
      let menus = NativeApplicationMenuController()
      self.menus = menus
      menus.install()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  }
#endif
