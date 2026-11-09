import AppKit
import Observation

/// Public window/document ownership connects both hosts to their shared model.
/// Weak entries never keep closed windows or documents alive.
@MainActor
final class DocumentWorkspaceRegistry {
  static let shared = DocumentWorkspaceRegistry()
  private let models = NSMapTable<NSWindow, MarkdownDocument>.weakToWeakObjects()
  private var waiters: [UUID: Waiter] = [:]
  var waitingCount: Int { waiters.count }

  private struct Waiter {
    weak var document: NSDocument?
    let controller: NSDocumentController
    let continuation: CheckedContinuation<MarkdownDocument, any Error>
    let deadline: Task<Void, Never>
  }

  func register(_ document: MarkdownDocument, in window: NSWindow) {
    guard models.object(forKey: window) !== document else { return }
    models.setObject(document, forKey: window)
    for id in Array(waiters.keys) { resolve(id) }
  }

  func unregister(_ window: NSWindow, matching document: MarkdownDocument?) {
    guard models.object(forKey: window) === document else { return }
    models.removeObject(forKey: window)
  }

  private func currentModel(for document: NSDocument, controller: NSDocumentController)
    -> MarkdownDocument?
  {
    if let native = document as? NativeMarkdownDocument { return native.markdownDocument }
    for window in models.keyEnumerator().allObjects.compactMap({ $0 as? NSWindow }) {
      if controller.document(for: window) === document,
        let model = models.object(forKey: window)
      {
        // The reference host can attach its window before applying the initial
        // snapshot. Empty loaded files are distinguished by the load revision.
        guard document.fileURL == nil || model.loadRevision > 0 else { continue }
        return model
      }
    }
    return nil
  }

  func model(for document: NSDocument, controller: NSDocumentController) async throws
    -> MarkdownDocument
  {
    try Task.checkCancellation()
    if let model = currentModel(for: document, controller: controller) { return model }
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        let deadline = Task { @MainActor [weak self] in
          do { try await Task.sleep(for: .seconds(8)) } catch { return }
          self?.finish(id, with: .failure(DocumentLinkError.locationUnavailable))
        }
        waiters[id] = Waiter(
          document: document, controller: controller,
          continuation: continuation, deadline: deadline)
        resolve(id)
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(id, with: .failure(CancellationError())) }
    }
  }

  private func resolve(_ id: UUID) {
    guard let waiter = waiters[id] else { return }
    guard let owner = waiter.document else {
      finish(id, with: .failure(DocumentLinkError.locationUnavailable))
      return
    }
    let model = withObservationTracking {
      currentModel(for: owner, controller: waiter.controller)
    } onChange: { [weak self] in
      // Observation fires before the new value is stored. Recheck on the next
      // actor turn, and ignore notifications after cancellation or completion.
      Task { @MainActor [weak self] in self?.resolve(id) }
    }
    if let model { finish(id, with: .success(model)) }
  }

  private func finish(_ id: UUID, with result: Result<MarkdownDocument, any Error>) {
    guard let waiter = waiters.removeValue(forKey: id) else { return }
    waiter.deadline.cancel()
    waiter.continuation.resume(with: result)
  }
}

enum DocumentLinkError: Error, LocalizedError {
  case locationUnavailable
  var errorDescription: String? {
    String(
      localized: "The document opened, but its location could not be shown. Try the link again.")
  }
}
