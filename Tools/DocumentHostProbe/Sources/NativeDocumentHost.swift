#if APPKIT_DOCUMENT_HOST_PROBE
  import AppKit
  import Synchronization

  /// Independent control using only public native document/undo/file-presenter behavior.
  @objc(ProbeNativeDocument)
  @MainActor
  final class ProbeNativeDocument: NSDocument, NSTextViewDelegate {
    private nonisolated let source = Mutex("")
    private weak var editor: NSTextView?

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

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
      try super.revert(toContentsOf: url, ofType: typeName)
      editor?.string = source.withLock { $0 }
    }

    override func makeWindowControllers() {
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
      text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
      text.string = source.withLock { $0 }
      text.delegate = self
      text.setAccessibilityIdentifier("stockDocumentEditor")
      text.setAccessibilityLabel("Document host comparison text")
      scroll.documentView = text
      window.contentView = scroll
      editor = text
      addWindowController(NSWindowController(window: window))
      window.center()
      window.makeFirstResponder(text)
    }

    func undoManager(for view: NSTextView) -> UndoManager? { undoManager }

    func textDidChange(_ notification: Notification) {
      guard let editor else { return }
      let text = editor.string
      source.withLock { $0 = text }
      NSLog("NativeDocumentProbe native edit utf16=%ld", text.utf16.count)
    }
  }

  @main
  @MainActor
  final class ProbeNativeApplication: NSObject, NSApplicationDelegate {
    static func main() {
      let app = NSApplication.shared
      let delegate = ProbeNativeApplication()
      app.delegate = delegate
      app.setActivationPolicy(.regular)
      withExtendedLifetime(delegate) { app.run() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
      _ = NSDocumentController.shared
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
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
  }
#endif
