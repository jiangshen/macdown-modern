import AppKit
import WebKit

public enum DocumentOutputError: Error, Sendable {
  case navigationFailed, timedOut, resourceFailed, printFailed
}

/// A separate, immutable render surface keeps export independent of preview mode,
/// delayed live renders, scroll position and edits made while the save panel is open.
@MainActor
final class NativeWebOutput: NSObject, WKNavigationDelegate {
  let view: WKWebView
  private let host: NSWindow
  private var navigation: WKNavigation?
  private var expectsInitialNavigation = false
  private var pending: CheckedContinuation<Void, any Error>?
  private var timeout: Task<Void, Never>?

  override init() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    view = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 720, height: 900), configuration: configuration)
    host = NSWindow(
      contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
    host.contentView = view
    super.init()
    view.navigationDelegate = self
  }

  func prepare(html: String, remoteImages: Bool = false) async throws {
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pending = continuation
        expectsInitialNavigation = true
        navigation = view.loadHTMLString(html, baseURL: nil)
        timeout = Task { [weak self] in
          do { try await Task.sleep(for: .seconds(20)) } catch { return }
          self?.finish(.failure(DocumentOutputError.timedOut))
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
    }
    try Task.checkCancellation()
    // WebKit's navigation callback precedes image decoding and font readiness.
    let resourcesReady: Bool = try await withCheckedThrowingContinuation { continuation in
      view.callAsyncJavaScript(
        Self.waitForResources, arguments: ["remoteImages": remoteImages], in: nil,
        in: .defaultClient
      ) {
        result in
        switch result {
        case .success(let value): continuation.resume(returning: value as? Bool ?? false)
        case .failure(let error): continuation.resume(throwing: error)
        }
      }
    }
    try Task.checkCancellation()
    guard resourcesReady else { throw DocumentOutputError.resourceFailed }
  }

  func makePrintOperation(info: NSPrintInfo, showPanel: Bool) -> NSPrintOperation {
    let operation = view.printOperation(with: info)
    operation.showsPrintPanel = showPanel
    operation.showsProgressPanel = showPanel
    operation.canSpawnSeparateThread = true
    return operation
  }

  func printDocument(info: NSPrintInfo, for window: NSWindow, showPanel: Bool) async -> Bool {
    let operation = makePrintOperation(info: info, showPanel: showPanel)
    return await NativePrintSession().run(operation, for: window)
  }

  func close() {
    finish(.failure(CancellationError()))
    view.stopLoading()
    view.navigationDelegate = nil
    host.contentView = nil
  }

  private func finish(_ result: Result<Void, any Error>) {
    timeout?.cancel()
    timeout = nil
    let continuation = pending
    pending = nil
    continuation?.resume(with: result)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard navigation === self.navigation else { return }
    finish(.success(()))
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    guard navigation === self.navigation else { return }
    finish(.failure(error))
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    self.webView(webView, didFail: navigation, withError: error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(.failure(DocumentOutputError.navigationFailed))
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    let initial =
      expectsInitialNavigation && navigationAction.navigationType == .other
      && navigationAction.request.url?.scheme == "about"
    if initial { expectsInitialNavigation = false }
    decisionHandler(initial ? .allow : .cancel)
  }

  static func printInfo(allPages: Bool = false) -> NSPrintInfo {
    let info = NSPrintInfo(
      dictionary: NSPrintInfo.shared.dictionary() as? [NSPrintInfo.AttributeKey: Any] ?? [:])
    if allPages { info.dictionary()[NSPrintInfo.AttributeKey.allPages] = true }
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    info.isVerticallyCentered = false
    info.topMargin = 50
    info.bottomMargin = 50
    info.leftMargin = 36
    info.rightMargin = 36
    return info
  }

  private static let waitForResources = """
    const images = [...document.images].filter(image => image.src.startsWith('data:') || (remoteImages && image.src.startsWith('https:')));
    const ready = Promise.all(images.map(image => {
      if (image.complete) return Promise.resolve(image.naturalWidth > 0);
      return new Promise(resolve => {
        image.addEventListener('load', () => resolve(true), {once:true});
        image.addEventListener('error', () => resolve(false), {once:true});
      });
    })).then(async results => { await document.fonts.ready; return results.every(Boolean); });
    return await Promise.race([ready, new Promise(resolve => setTimeout(() => resolve(false), 10000))]);
    """
}

@MainActor
private final class NativePrintSession: NSObject {
  private var continuation: CheckedContinuation<Bool, Never>?

  func run(_ operation: NSPrintOperation, for window: NSWindow) async -> Bool {
    defer { continuation = nil }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      operation.runModal(
        for: window, delegate: self,
        didRun: #selector(completed(_:success:contextInfo:)), contextInfo: nil)
    }
  }

  @objc nonisolated private func completed(
    _ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?
  ) {
    // AppKit may invoke the delegate on its print worker thread. Only the
    // Boolean result crosses back; UI objects and context pointers stay there.
    Task { @MainActor [weak self] in
      guard let self else { return }
      let completion = self.continuation
      self.continuation = nil
      completion?.resume(returning: success)
    }
  }
}
