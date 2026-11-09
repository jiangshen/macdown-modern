import AppKit
import DocumentCore
import Synchronization

/// Native document ownership with the same SwiftUI workspace. NSDocument owns
/// coordination, saving, Versions and window restoration; the model owns source.
@objc(SnowfolioNativeDocument)
@MainActor
open class NativeMarkdownDocument: NSDocument {
  private nonisolated let loadedContents = Mutex(TextFileContents())
  private var loadedModel: MarkdownDocument?
  private let fileMonitor = NativeDocumentFileMonitor()
  private var isClosed = false
  let workspaceState = DocumentWorkspaceState()
  private static let workspaceStateKey = "snowfolioWorkspaceState"

  // NSDocument's URL remains thread-safe. UI observation crosses to the main
  // actor asynchronously and reads the current URL, rather than a stale capture.
  nonisolated open override var fileURL: URL? {
    get { super.fileURL }
    set {
      super.fileURL = newValue
      Task { @MainActor [weak self] in
        guard let self, !self.isClosed else { return }
        self.loadedModel?.nativeFileLocationChanged()
        self.fileMonitor.didChange = { [weak self] url in
          guard let self, !self.isClosed, self.fileURL == url,
            NSFileCoordinator.filePresenters.contains(where: { ($0 as AnyObject) === self })
          else { return }
          self.presentedItemOperationQueue.addOperation { @Sendable [weak self] in
            guard let self, self.fileURL == url,
              NSFileCoordinator.filePresenters.contains(where: { ($0 as AnyObject) === self })
            else { return }
            self.presentedItemDidChange()
          }
        }
        self.fileMonitor.observe(self.fileURL)
      }
    }
  }

  open override class var autosavesInPlace: Bool { true }

  open override func close() {
    isClosed = true
    fileMonitor.stop()
    super.close()
  }

  public var markdownDocument: MarkdownDocument {
    if let loadedModel { return loadedModel }
    let model = MarkdownDocument()
    model.acceptNativeLoad(loadedContents.withLock { $0 })
    model.attachNativeFileDocument(self)
    loadedModel = model
    return model
  }

  open override func makeWindowControllers() {
    addWindowController(
      NativeDocumentWindowController(
        document: self, preferences: NativeDocumentPreferences.shared, state: workspaceState))
    workspaceState.didChange = { [weak self] in self?.invalidateRestorableState() }
  }

  open override func encodeRestorableState(with coder: NSCoder) {
    super.encodeRestorableState(with: coder)
    if let data = try? workspaceState.encoded() {
      coder.encode(data, forKey: Self.workspaceStateKey)
    }
  }

  open override func restoreState(with coder: NSCoder) {
    super.restoreState(with: coder)
    if coder.containsValue(forKey: Self.workspaceStateKey),
      let data = coder.decodeObject(of: NSData.self, forKey: Self.workspaceStateKey) as Data?
    {
      workspaceState.restore(from: data)
    }
  }

  /// Hosts with a custom source view attach it here before editing begins.
  public func attachSourceEditor(_ editor: NSTextView) {
    markdownDocument.attachSourceEditor(editor)
  }

  public func detachSourceEditor(_ editor: NSTextView) {
    loadedModel?.detachSourceEditor(editor)
  }

  nonisolated open override func read(from data: Data, ofType typeName: String) throws {
    let snapshot = try TextFileContents(decoding: data)
    loadedContents.withLock { $0 = snapshot }
    #if DEBUG
      DocumentLifecycleTrace.note("native read bytes=\(data.count)")
    #endif
  }

  open override func data(ofType typeName: String) throws -> Data {
    loadedModel?.prepareSourceEditorsForSave()
    let snapshot = loadedModel?.fileContents ?? loadedContents.withLock { $0 }
    #if DEBUG
      DocumentLifecycleTrace.note("native write utf16=\(snapshot.text.utf16.count)")
    #endif
    return try snapshot.encoded()
  }

  open override func revert(toContentsOf url: URL, ofType typeName: String) throws {
    // Native NSDocument retains conflict, coordination, Versions and error ownership.
    try super.revert(toContentsOf: url, ofType: typeName)
    loadedModel?.acceptNativeLoad(loadedContents.withLock { $0 })
  }
}
