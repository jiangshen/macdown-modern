import AppKit
import DocumentCore
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

public enum DocumentMergeError: Error, Equatable, Sendable {
  case conflictingExternalChange
}

/// The macOS 27 document host owns file coordination, autosave, Versions and windows.
/// This reference model owns the source; views and background readers use snapshots.
@MainActor
@Observable
public final class MarkdownDocument: SwiftUI.Document {
  nonisolated public static let markdownType = UTType(
    importedAs: "net.daringfireball.markdown",
    conformingTo: .plainText)
  nonisolated public static let readableContentTypes = [markdownType, UTType.plainText]

  public private(set) var text: String
  public private(set) var revision: UInt64 = 0
  public private(set) var loadRevision: UInt64 = 0
  public private(set) var selectionRequest: EditorSelectionRequest?
  private let configuration: URLDocumentConfiguration?
  @ObservationIgnored private weak var nativeFileDocument: NSDocument?
  private var nativeLocationRevision: UInt64 = 0
  public var fileURL: URL? {
    if let configuration { return configuration.fileURL }
    // Observe invalidation, but read the host's current URL even before its
    // main-actor notification arrives (for example immediately after Save As).
    _ = nativeLocationRevision
    return nativeFileDocument?.fileURL
  }

  func attachNativeFileDocument(_ document: NSDocument) {
    nativeFileDocument = document
    nativeFileLocationChanged()
  }

  func nativeFileLocationChanged() { nativeLocationRevision &+= 1 }

  public func navigate(toUTF16Offset offset: Int) {
    selectionRequest = EditorSelectionRequest(offset: offset)
  }
  @ObservationIgnored private var baseline: TextFileContents
  @ObservationIgnored private let sourceEditors = NSHashTable<NSTextView>.weakObjects()

  func attachSourceEditor(_ editor: NSTextView) { sourceEditors.add(editor) }
  func detachSourceEditor(_ editor: NSTextView) { sourceEditors.remove(editor) }

  /// AppKit requires a typing checkpoint when saving, so later coalesced edits
  /// register with the native document's dirty-state and Undo machinery again.
  func prepareSourceEditorsForSave() {
    let editors = sourceEditors.allObjects
    #if DEBUG
      if DocumentLifecycleTrace.enabled {
        DocumentLifecycleTrace.note(
          "save checkpoint editors=\(editors.count) coalescing=\(editors.filter { $0.isCoalescingUndo }.count) marked=\(editors.filter { $0.hasMarkedText() }.count)"
        )
      }
    #endif
    for editor in editors where !editor.hasMarkedText() {
      editor.breakUndoCoalescing()
    }
  }

  public init(
    contents: TextFileContents = TextFileContents(),
    configuration: URLDocumentConfiguration? = nil
  ) {
    self.configuration = configuration
    baseline = contents
    text = contents.text
  }

  nonisolated public func reader(configuration: sending ReadConfiguration)
    -> sending FileWrapperDocumentReader<TextFileContents>
  {
    FileWrapperDocumentReader(configuration) { wrapper in
      #if DEBUG
        if DocumentLifecycleTrace.enabled {
          DocumentLifecycleTrace.note("convert file wrapper regular=\(wrapper.isRegularFile)")
        }
      #endif
      guard let data = wrapper.regularFileContents else {
        throw CocoaError(.fileReadCorruptFile)
      }
      #if DEBUG
        DocumentLifecycleTrace.note("read file wrapper bytes=\(data.count)")
      #endif
      return try TextFileContents(decoding: data)
    }
  }

  nonisolated public func writer(configuration: sending WriteConfiguration)
    -> sending FileWrapperDocumentWriter<TextFileContents>
  {
    FileWrapperDocumentWriter(configuration) { snapshot, _ in
      #if DEBUG
        DocumentLifecycleTrace.note("create write wrapper utf16=\(snapshot.text.utf16.count)")
      #endif
      return FileWrapper(regularFileWithContents: try snapshot.encoded())
    }
  }

  public func snapshot(contentType: UTType) async throws -> sending TextFileContents {
    prepareSourceEditorsForSave()
    #if DEBUG
      if DocumentLifecycleTrace.enabled {
        DocumentLifecycleTrace.note(
          "snapshot revision=\(revision) utf16=\(text.utf16.count) load=\(loadRevision)")
      }
    #endif
    return fileContents
  }

  /// Shared byte-preserving snapshot for either native document host.
  var fileContents: TextFileContents { baseline.replacingText(with: text) }

  public func apply(
    snapshot: sending TextFileContents,
    previous: sending TextFileContents?
  ) async throws {
    #if DEBUG
      if DocumentLifecycleTrace.enabled {
        DocumentLifecycleTrace.note(
          "apply revision=\(revision) previous=\(previous != nil) previousMatches=\(previous.map { text.utf8.elementsEqual($0.text.utf8) } ?? false) incomingMatches=\(text.utf8.elementsEqual(snapshot.text.utf8))"
        )
      }
    #endif
    if let previous,
      !text.utf8.elementsEqual(previous.text.utf8),
      !text.utf8.elementsEqual(snapshot.text.utf8)
    {
      // A native host can present a conflict rather than silently losing local edits.
      // Three-way text merging is intentionally not attempted by this adapter.
      throw DocumentMergeError.conflictingExternalChange
    }
    acceptNativeLoad(snapshot)
  }

  /// NSDocument invokes this only after its own coordinated read/revert succeeds.
  /// The SwiftUI adapter keeps its existing merge guard above.
  func acceptNativeLoad(_ snapshot: TextFileContents) {
    baseline = snapshot
    text = snapshot.text
    revision &+= 1
    loadRevision &+= 1
  }

  /// Programmatic changes must register with the host's undo manager for dirty-state
  /// detection and autosave. Native NSTextView typing registers its own inverse edits.
  public func replaceText(with replacement: String, undoManager: UndoManager?) {
    guard !replacement.utf8.elementsEqual(text.utf8) else { return }
    let previous = text
    undoManager?.registerUndo(withTarget: self) { [weak undoManager] document in
      document.replaceText(with: previous, undoManager: undoManager)
    }
    text = replacement
    revision &+= 1
  }

  /// Called only by the native editor after an edit registered with the same undo manager.
  public func acceptNativeEdit(_ replacement: String) {
    guard !replacement.utf8.elementsEqual(text.utf8) else { return }
    text = replacement
    revision &+= 1
    #if DEBUG
      if DocumentLifecycleTrace.enabled {
        DocumentLifecycleTrace.note("accept native revision=\(revision) utf16=\(text.utf16.count)")
      }
    #endif
  }
}

public struct EditorSelectionRequest: Equatable {
  public let id = UUID()
  public let offset: Int
}

#if DEBUG
  /// Opt-in lifecycle diagnostics contain only operation/state metadata, never text or URLs.
  enum DocumentLifecycleTrace {
    static let enabled =
      ProcessInfo.processInfo.environment["SNOWFOLIO_TRACE_DOCUMENT_LIFECYCLE"] == "1"
    static func note(_ message: String) {
      if enabled { NSLog("SnowfolioDocument %@", message) }
    }
  }
#endif
