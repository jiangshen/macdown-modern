import AppKit
import DocumentCore
import SwiftUI
import Testing

@testable import SnowfolioUI

@Suite("Document opening workspace ownership", .serialized, NativeUIExclusive())
@MainActor
struct DocumentWorkspaceRegistryTests {
  enum TestError: Error { case timeout }
  private func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    throw TestError.timeout
  }

  @Test("Late workspace attachment wakes exactly the owning document without polling")
  func lateAttachment() async throws {
    _ = NSApplication.shared
    let registry = DocumentWorkspaceRegistry()
    let owner = NSDocument()
    let controller = NSDocumentController.shared
    let window = makeWindow()
    owner.addWindowController(NSWindowController(window: window))
    controller.addDocument(owner)
    defer { owner.close() }
    let pending = Task { try await registry.model(for: owner, controller: controller) }
    try await waitFor { registry.waitingCount == 1 }
    let model = MarkdownDocument(contents: .init(text: "owned source"))
    registry.register(model, in: window)
    #expect(try await pending.value === model)
    #expect(registry.waitingCount == 0)
    let unrelated = MarkdownDocument()
    registry.unregister(window, matching: unrelated)
    #expect(try await registry.model(for: owner, controller: controller) === model)
    registry.unregister(window, matching: model)
  }

  @Test(
    "A file link waits for its initial snapshot, including a genuinely empty file",
    arguments: ["", "A\r\n🧊e\u{301} target\r\n"])
  func initialFileLoad(source: String) async throws {
    _ = NSApplication.shared
    let registry = DocumentWorkspaceRegistry()
    let owner = NSDocument()
    owner.fileURL = URL(fileURLWithPath: "/tmp/link-initial-load-\(UUID().uuidString).md")
    let controller = NSDocumentController.shared
    let window = makeWindow()
    owner.addWindowController(NSWindowController(window: window))
    controller.addDocument(owner)
    defer { owner.close() }
    let model = MarkdownDocument()
    registry.register(model, in: window)
    var completed = false
    let pending = Task {
      let result = try await registry.model(for: owner, controller: controller)
      completed = true
      return result
    }
    defer { pending.cancel() }
    try await waitFor { completed || registry.waitingCount == 1 }
    #expect(!completed, "A window exists before the reference host applies its first file snapshot")
    model.acceptNativeLoad(TextFileContents(text: source))
    // Loading itself must wake the request; a duplicate window registration is
    // neither guaranteed by the host nor needed for event-driven readiness.
    #expect(try await pending.value === model)
    #expect(model.text == source && model.loadRevision == 1)
    #expect(registry.waitingCount == 0)
  }

  @Test("Cancellation during the initial read ignores its later completion and releases the model")
  func cancelInitialFileLoad() async throws {
    _ = NSApplication.shared
    let registry = DocumentWorkspaceRegistry()
    let owner = NSDocument()
    owner.fileURL = URL(fileURLWithPath: "/tmp/link-cancelled-read-\(UUID().uuidString).md")
    let controller = NSDocumentController.shared
    let window = makeWindow()
    owner.addWindowController(NSWindowController(window: window))
    controller.addDocument(owner)
    defer { owner.close() }
    var model: MarkdownDocument? = MarkdownDocument()
    weak let observed = model
    registry.register(try #require(model), in: window)
    let pending = Task { try await registry.model(for: owner, controller: controller) }
    defer { pending.cancel() }
    try await waitFor { registry.waitingCount == 1 }
    pending.cancel()
    await #expect(throws: CancellationError.self) { try await pending.value }
    model?.acceptNativeLoad(TextFileContents(text: "late source"))
    await Task.yield()
    #expect(registry.waitingCount == 0)
    model = nil
    #expect(observed == nil)
  }

  @Test("A released workspace in another window never hides the live model")
  func multipleWindows() async throws {
    _ = NSApplication.shared
    let registry = DocumentWorkspaceRegistry()
    let owner = NSDocument()
    let controller = NSDocumentController.shared
    let first = makeWindow()
    let second = makeWindow()
    owner.addWindowController(NSWindowController(window: first))
    owner.addWindowController(NSWindowController(window: second))
    controller.addDocument(owner)
    defer { owner.close() }
    for (live, released) in [(first, second), (second, first)] {
      let model = MarkdownDocument(contents: .init(text: "live source"))
      var obsolete: MarkdownDocument? = MarkdownDocument()
      weak let observed = obsolete
      if let obsolete { registry.register(obsolete, in: released) }
      obsolete = nil
      #expect(observed == nil)
      registry.register(model, in: live)
      #expect(try await registry.model(for: owner, controller: controller) === model)
      registry.unregister(live, matching: model)
    }
  }

  @Test("Cancelled lookup releases its continuation and deadline")
  func cancellation() async throws {
    _ = NSApplication.shared
    let registry = DocumentWorkspaceRegistry()
    let owner = NSDocument()
    let controller = NSDocumentController.shared
    controller.addDocument(owner)
    defer { owner.close() }
    let pending = Task { try await registry.model(for: owner, controller: controller) }
    try await waitFor { registry.waitingCount == 1 }
    pending.cancel()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(registry.waitingCount == 0)
  }

  @Test("A workspace registration does not retain its source model")
  func weakOwnership() {
    _ = NSApplication.shared
    let registry = DocumentWorkspaceRegistry()
    let window = makeWindow()
    defer { window.close() }
    var model: MarkdownDocument? = MarkdownDocument()
    weak let observed = model
    if let model { registry.register(model, in: window) }
    model = nil
    #expect(observed == nil)
  }

  @Test("A location request reveals a hidden source pane without changing bytes or Undo")
  func revealSource() async throws {
    _ = NSApplication.shared
    let domain = "LinkWorkspace." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = "A\r\n🧊e\u{301} xyz\r\nLast\n"
    let bytes = Data([0xff, 0xfe]) + (try #require(source.data(using: .utf16LittleEndian)))
    let document = MarkdownDocument(contents: try TextFileContents(decoding: bytes))
    let state = DocumentWorkspaceState()
    state.mode = .preview
    let undo = UndoManager()
    let commands = NativeWorkspaceCommandContext()
    let host = NSHostingController(
      rootView: NativeDocumentWorkspace(
        document: document, preferences: preferences, state: state, hostUndoManager: undo,
        commandContext: commands, openFile: { _ in }))
    let window = makeWindow()
    window.contentViewController = host
    window.orderFront(nil)
    defer { window.close() }
    try await waitFor { commands.editor?.coordinator?.editor != nil }
    let editor = try #require(commands.editor?.coordinator?.editor)
    let location = try #require(DocumentSourceLocation(line: 2, column: 6))
    document.navigate(toUTF16Offset: try await location.utf16Offset(in: source))
    try await waitFor {
      state.mode == .split && !editor.isHiddenOrHasHiddenAncestor
        && editor.selectedRange() == NSRange(location: 8, length: 0)
    }
    #expect(window.firstResponder === editor)
    #expect(!undo.canUndo)
    #expect(document.revision == 0)
    #expect(try document.fileContents.encoded() == bytes)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 1000, height: 650),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.animationBehavior = .none
    return window
  }
}
