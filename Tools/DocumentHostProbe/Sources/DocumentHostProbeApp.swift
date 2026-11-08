#if !APPKIT_DOCUMENT_HOST_PROBE
  import Foundation
  import Observation
  import SwiftUI
  import UniformTypeIdentifiers

  #if DIRECT_URL_DOCUMENT_HOST_PROBE
    // The same document host with Apple's alternative URL-based reader/writer.
    // The host coordinates access; these types do not register another presenter.
    struct ProbeURLReader: DocumentReader {
      @concurrent
      func read(from source: sending URL, progress: consuming Subprogress) async throws
        -> sending String
      {
        let data = try Data(contentsOf: source)
        guard let text = String(data: data, encoding: .utf8) else {
          throw CocoaError(.fileReadCorruptFile)
        }
        NSLog("StockDocumentProbe direct read bytes=%ld", data.count)
        return text
      }
    }

    struct ProbeURLWriter: DocumentWriter {
      @concurrent
      func write(
        snapshot: sending String, to destination: sending URL,
        previous: sending String?, progress: consuming Subprogress
      ) async throws {
        NSLog("StockDocumentProbe direct write utf16=%ld", snapshot.utf16.count)
        try Data(snapshot.utf8).write(to: destination, options: .atomic)
      }
    }
  #endif

  // Document/TextEditor control with FileWrapper or direct URL I/O, no Snowfolio model,
  // editor, preview, merge policy, commands, preferences or third-party dependencies.
  @MainActor @Observable
  final class ProbeDocument: Document {
    nonisolated static let readableContentTypes = [UTType.plainText]
    var text = ""

    #if DIRECT_URL_DOCUMENT_HOST_PROBE
      nonisolated func reader(configuration: sending ReadConfiguration) -> sending ProbeURLReader {
        ProbeURLReader()
      }

      nonisolated func writer(configuration: sending WriteConfiguration) -> sending ProbeURLWriter {
        ProbeURLWriter()
      }
    #else
      nonisolated func reader(configuration: sending ReadConfiguration)
        -> sending FileWrapperDocumentReader<String>
      {
        FileWrapperDocumentReader(configuration) { wrapper in
          guard let data = wrapper.regularFileContents,
            let text = String(data: data, encoding: .utf8)
          else { throw CocoaError(.fileReadCorruptFile) }
          NSLog("StockDocumentProbe read bytes=%ld", data.count)
          return text
        }
      }

      nonisolated func writer(configuration: sending WriteConfiguration)
        -> sending FileWrapperDocumentWriter<String>
      {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
          NSLog("StockDocumentProbe write utf16=%ld", snapshot.utf16.count)
          return FileWrapper(regularFileWithContents: Data(snapshot.utf8))
        }
      }

    #endif

    func snapshot(contentType: UTType) async throws -> sending String {
      NSLog("StockDocumentProbe snapshot utf16=%ld", text.utf16.count)
      return text
    }

    func apply(snapshot: sending String, previous: sending String?) async throws {
      NSLog("StockDocumentProbe apply utf16=%ld previous=%d", snapshot.utf16.count, previous != nil)
      text = snapshot
    }
  }

  struct ProbeEditor: View {
    @Bindable var document: ProbeDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
      TextEditor(text: $document.text)
        .accessibilityIdentifier("stockDocumentEditor")
        .onAppear {
          NSLog("StockDocumentProbe presenters=%ld", NSFileCoordinator.filePresenters.count)
        }
        .onChange(of: document.text) { previous, _ in
          // Matches Apple's migration example, including its manual model undo.
          undoManager?.registerUndo(withTarget: document) { document in
            document.text = previous
          }
        }
        .frame(minWidth: 600, minHeight: 360)
    }
  }

  @main
  struct DocumentHostProbeApp: App {
    var body: some Scene {
      DocumentGroup { (document: ProbeDocument) in
        ProbeEditor(document: document)
      } makeDocument: { _, _ in
        ProbeDocument()
      }
    }
  }
#endif
