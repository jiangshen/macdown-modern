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
    let (document, _) = try await controller.openDocument(
      withContentsOf: request.fileURL, display: true)
    guard let position = request.location else { return }
    let model = try await DocumentWorkspaceRegistry.shared.model(
      for: document, controller: controller)
    let revision = model.revision
    let offset = try await position.utf16Offset(in: model.text)
    try Task.checkCancellation()
    // A user's newer edit wins over a location computed from the earlier text.
    guard revision == model.revision, controller.documents.contains(where: { $0 === document })
    else { return }
    model.navigate(toUTF16Offset: offset)
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
