import AppKit
import DocumentCore
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
  public var fileURL: URL? { configuration?.fileURL }

  public func navigate(toUTF16Offset offset: Int) {
    selectionRequest = EditorSelectionRequest(offset: offset)
  }
  @ObservationIgnored private var baseline: TextFileContents

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
      guard let data = wrapper.regularFileContents else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return try TextFileContents(decoding: data)
    }
  }

  nonisolated public func writer(configuration: sending WriteConfiguration)
    -> sending FileWrapperDocumentWriter<TextFileContents>
  {
    FileWrapperDocumentWriter(configuration) { snapshot, _ in
      FileWrapper(regularFileWithContents: try snapshot.encoded())
    }
  }

  public func snapshot(contentType: UTType) async throws -> sending TextFileContents {
    baseline.replacingText(with: text)
  }

  public func apply(
    snapshot: sending TextFileContents,
    previous: sending TextFileContents?
  ) async throws {
    if let previous,
      !text.utf8.elementsEqual(previous.text.utf8),
      !text.utf8.elementsEqual(snapshot.text.utf8)
    {
      // A native host can present a conflict rather than silently losing local edits.
      // Three-way text merging is intentionally not attempted by this adapter.
      throw DocumentMergeError.conflictingExternalChange
    }
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
  }
}

public struct EditorSelectionRequest: Equatable {
  public let id = UUID()
  public let offset: Int
}
