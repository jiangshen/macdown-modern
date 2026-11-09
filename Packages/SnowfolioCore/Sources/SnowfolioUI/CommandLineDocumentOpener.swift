import AppKit
import Darwin
import DocumentCore

@MainActor
enum CommandLineDocumentOpener {
  static func open(_ request: CommandLineLaunchRequest) async throws {
    let controller = NSDocumentController.shared
    var failures: [any Error] = []
    if let data = request.pipedData, let contents = request.pipedContents {
      do {
        let document = try controller.openUntitledDocumentAndDisplay(true)
        let model = try await DocumentWorkspaceRegistry.shared.model(
          for: document, controller: controller)
        try Task.checkCancellation()
        guard controller.documents.contains(where: { $0 === document }) else {
          throw CancellationError()
        }
        guard model.revision == model.loadRevision, model.text.isEmpty,
          !model.sourceEditorsHaveMarkedText, !document.isDocumentEdited
        else {
          throw NSError(
            domain: "SnowfolioCLI", code: 3,
            userInfo: [
              NSLocalizedDescriptionKey: String(
                localized:
                  "The new document was edited before piped text could be imported. Run the command again."
              )
            ])
        }
        // This is a fresh Untitled document, never a replacement for an existing
        // user's source. Preserve BOM/newlines as its initial UTF-8 snapshot.
        model.acceptNativeLoad(contents)
        if !data.isEmpty { document.updateChangeCount(.changeDone) }
        model.navigate(toUTF16Offset: 0)
      } catch is CancellationError { throw CancellationError() } catch { failures.append(error) }
    }
    for (index, file) in request.files.enumerated() {
      do {
        #if DEBUG
          DocumentLifecycleTrace.note("command line file begin index=\(index)")
        #endif
        try await prepareFile(file)
        _ = try await controller.openDocument(withContentsOf: file, display: true)
        #if DEBUG
          DocumentLifecycleTrace.note("command line file opened index=\(index)")
        #endif
      } catch is CancellationError { throw CancellationError() } catch {
        #if DEBUG
          let failure = error as NSError
          DocumentLifecycleTrace.note(
            "command line file failed index=\(index) domain=\(failure.domain) code=\(failure.code)")
        #endif
        failures.append(error)
      }
    }
    if request.files.isEmpty, request.pipedData == nil, controller.documents.isEmpty {
      _ = try controller.openUntitledDocumentAndDisplay(true)
    }
    if let failure = failures.first {
      if failures.count == 1 { throw failure }
      throw NSError(
        domain: "SnowfolioCLI", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: String(localized: "Some documents could not be opened."),
          NSLocalizedFailureReasonErrorKey: failures.map(\.localizedDescription).joined(
            separator: "\n"),
          NSMultipleUnderlyingErrorsKey: failures,
        ])
    }
  }

  /// Preserve the CLI's missing-file behavior without the old unchecked create
  /// that could overwrite an existing file. Normal NSDocument opening owns reads.
  @concurrent nonisolated private static func prepareFile(_ file: URL) async throws {
    try Task.checkCancellation()
    try file.withUnsafeFileSystemRepresentation { path in
      guard let path else { throw CommandLineInvocationError.invalidPath }
      let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o666))
      if descriptor >= 0 {
        _ = Darwin.close(descriptor)
      } else {
        let failure = errno
        if failure != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO) }
      }
    }
  }
}
