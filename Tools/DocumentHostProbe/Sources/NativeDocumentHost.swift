#if APPKIT_DOCUMENT_HOST_PROBE
  import AppKit
  import Synchronization

  #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
    import SnowfolioUI
    typealias ProbeDocumentBase = NativeMarkdownDocument
  #else
    typealias ProbeDocumentBase = NSDocument
  #endif

  /// The same native editor hosts either the independent control or the shared adapter.
  @objc(ProbeNativeDocument)
  @MainActor
  final class ProbeNativeDocument: ProbeDocumentBase, NSTextViewDelegate {
    private weak var editor: NSTextView?

    #if !PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
      private nonisolated let source = Mutex("")

      override class var autosavesInPlace: Bool { true }

      nonisolated override func read(from data: Data, ofType typeName: String) throws {
        guard let text = String(data: data, encoding: .utf8) else {
          throw CocoaError(.fileReadCorruptFile)
        }
        NSLog("NativeDocumentProbe read bytes=%ld", data.count)
        source.withLock { $0 = text }
      }

      override func data(ofType typeName: String) throws -> Data {
        let snapshot = source.withLock { $0 }
        NSLog("NativeDocumentProbe write utf16=%ld", snapshot.utf16.count)
        return Data(snapshot.utf8)
      }

    #endif

    private var sourceText: String {
      #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
        markdownDocument.text
      #else
        source.withLock { $0 }
      #endif
    }

    nonisolated override func presentedItemDidChange() {
      NSLog("NativeDocumentProbe presented item changed")
      super.presentedItemDidChange()
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
      NSLog("NativeDocumentProbe revert")
      try super.revert(toContentsOf: url, ofType: typeName)
      editor?.string = sourceText
    }

    override func makeWindowControllers() {
      #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
        super.makeWindowControllers()
      #else
        let window = NSWindow(
          contentRect: NSRect(x: 0, y: 0, width: 900, height: 500),
          styleMask: [.titled, .closable, .miniaturizable, .resizable],
          backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: window.contentLayoutRect)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.autoresizingMask = [.width, .height]
        let text = NSTextView(usingTextLayoutManager: true)
        text.frame = scroll.contentView.bounds
        text.isRichText = false
        text.allowsUndo = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(
          width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.string = sourceText
        text.delegate = self
        #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
          attachSourceEditor(text)
        #endif
        text.setAccessibilityIdentifier("stockDocumentEditor")
        text.setAccessibilityLabel("Document host comparison text")
        scroll.documentView = text
        window.contentView = scroll
        editor = text
        addWindowController(NSWindowController(window: window))
        window.center()
        window.makeFirstResponder(text)
      #endif
      let registered = NSFileCoordinator.filePresenters.contains { ($0 as AnyObject) === self }
      NSLog("NativeDocumentProbe presenter registered=%d", registered)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textDidChange(_ notification: Notification) {
      guard let editor else { return }
      let text = editor.string
      #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
        markdownDocument.acceptNativeEdit(text)
      #else
        source.withLock { $0 = text }
      #endif
      NSLog("NativeDocumentProbe native edit utf16=%ld", text.utf16.count)
    }
  }

  @main
  @MainActor
  final class ProbeNativeApplication: NSObject, NSApplicationDelegate {
    #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
      private var menus: NativeApplicationMenuController?
      private var paintControl: NativeWebKitPaintControl?
    #endif
    static func main() {
      let app = NSApplication.shared
      let delegate = ProbeNativeApplication()
      app.delegate = delegate
      app.setActivationPolicy(.regular)
      withExtendedLifetime(delegate) { app.run() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
      #if PRODUCTION_NATIVE_DOCUMENT_HOST_PROBE
        let requested = ProcessInfo.processInfo.environment["SNOWFOLIO_PROBE_AUTOSAVE_DELAY"]
          .flatMap(Double.init)
        NSDocumentController.shared.autosavingDelay =
          requested.flatMap { (2...30).contains($0) ? $0 : nil } ?? 2
      #else
        _ = NSDocumentController.shared
      #endif
      #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
        let menus = NativeApplicationMenuController()
        self.menus = menus
        menus.install()
      #else
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
          let root = NSMenuItem()
          let submenu = NSMenu(title: title)
          root.submenu = submenu
          main.addItem(root)
          return submenu
        }
        let application = menu("DocumentHostProbe")
        application.addItem(
          withTitle: "Quit DocumentHostProbe", action: #selector(NSApplication.terminate(_:)),
          keyEquivalent: "q")
        let file = menu("File")
        file.addItem(
          withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)),
          keyEquivalent: "n")
        file.addItem(
          withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)),
          keyEquivalent: "o")
        file.addItem(
          withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let edit = menu("Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
          withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
      #endif
    }

    #if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
      func applicationDidFinishLaunching(_ notification: Notification) {
        guard let path = ProcessInfo.processInfo.environment["SNOWFOLIO_PROBE_PAINT_OUTPUT"] else {
          return
        }
        let control = NativeWebKitPaintControl(
          output: URL(fileURLWithPath: path, isDirectory: true))
        paintControl = control
        control.showWindow(nil)
        control.window?.makeKeyAndOrderFront(nil)
      }
    #endif

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
  }
#endif
