import AppKit
import Carbon
import DocumentCore

/// Get-URL events share normal NSDocument opening; the file reader, writer, Undo
/// and conflict policy remain owned by the selected document host.
@MainActor
public final class DocumentURLController: NSObject {
  private var pending: [DocumentOpenRequest] = []
  private var task: Task<Void, Never>?

  public func install() {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(receive(_:withReplyEvent:)),
      forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
  }

  @objc private func receive(
    _ event: NSAppleEventDescriptor,
    withReplyEvent reply: NSAppleEventDescriptor
  ) {
    do {
      guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
        let url = URL(string: value)
      else { throw DocumentOpenRequestError.unsupportedLink }
      pending.append(try DocumentOpenRequest(link: url))
      drain()
    } catch {
      reply.setParam(NSAppleEventDescriptor(int32: -1703), forKeyword: AEKeyword(keyErrorNumber))
      reply.setParam(
        NSAppleEventDescriptor(string: error.localizedDescription),
        forKeyword: AEKeyword(keyErrorString))
      _ = NSApp.presentError(error)
    }
  }

  private func drain() {
    guard task == nil else { return }
    task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.task = nil }
      while !self.pending.isEmpty {
        let request = self.pending.removeFirst()
        do { try await self.open(request) } catch is CancellationError { return } catch {
          _ = NSApp.presentError(error)
        }
      }
    }
  }

  public func open(_ request: DocumentOpenRequest) async throws {
    let controller = NSDocumentController.shared
    #if DEBUG
      DocumentLifecycleTrace.note("link open begin")
    #endif
    let (document, _) = try await controller.openDocument(
      withContentsOf: request.fileURL, display: true)
    #if DEBUG
      if DocumentLifecycleTrace.enabled {
        DocumentLifecycleTrace.note(
          "link open returned native=\(document is NativeMarkdownDocument) member=\(controller.documents.contains { $0 === document }) docs=\(controller.documents.count)"
        )
      }
    #endif
    guard let position = request.location else { return }
    let model = try await DocumentWorkspaceRegistry.shared.model(
      for: document, controller: controller)
    let revision = model.revision
    #if DEBUG
      DocumentLifecycleTrace.note(
        "link model ready revision=\(revision) load=\(model.loadRevision) utf16=\(model.text.utf16.count)"
      )
    #endif
    let offset = try await position.utf16Offset(in: model.text)
    try Task.checkCancellation()
    #if DEBUG
      if DocumentLifecycleTrace.enabled {
        DocumentLifecycleTrace.note(
          "link computed offset=\(offset) revision=\(revision) now=\(model.revision) load=\(model.loadRevision) member=\(controller.documents.contains { $0 === document })"
        )
      }
    #endif
    // A user's newer edit wins over a location computed from the earlier text.
    guard revision == model.revision, controller.documents.contains(where: { $0 === document })
    else { return }
    model.navigate(toUTF16Offset: offset)
    #if DEBUG
      DocumentLifecycleTrace.note("link published selection offset=\(offset)")
    #endif
  }
}

/// SwiftUI retains this adaptor even when no document window is open.
@MainActor
public final class DocumentURLAppDelegate: NSObject, NSApplicationDelegate {
  private let links = DocumentURLController()
  public func applicationWillFinishLaunching(_ notification: Notification) { links.install() }
  public func applicationDidFinishLaunching(_ notification: Notification) { links.install() }
  public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
