import AppKit
import DocumentCore
import Synchronization

/// Native document ownership for the AppKit host migration. Window composition is
/// supplied by the app; this type owns coordinated loading, saving and byte format.
@objc(SnowfolioNativeDocument)
@MainActor
open class NativeMarkdownDocument: NSDocument {
  private nonisolated let loadedContents = Mutex(TextFileContents())
  private var loadedModel: MarkdownDocument?

  open override class var autosavesInPlace: Bool { true }

  public var markdownDocument: MarkdownDocument {
    if let loadedModel { return loadedModel }
    let model = MarkdownDocument(contents: loadedContents.withLock { $0 })
    loadedModel = model
    return model
  }

  nonisolated open override func read(from data: Data, ofType typeName: String) throws {
    let snapshot = try TextFileContents(decoding: data)
    loadedContents.withLock { $0 = snapshot }
    #if DEBUG
      DocumentLifecycleTrace.note("native read bytes=\(data.count)")
    #endif
  }

  open override func data(ofType typeName: String) throws -> Data {
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
