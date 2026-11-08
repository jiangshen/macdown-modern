import AppKit
import EditorCore
import RenderingCore
import SwiftUI
import WebKit

public struct NativeMarkdownPreview: NSViewRepresentable {
  public let html: String
  public let directory: URL?
  public let assetAccess: DocumentAssetAccess?
  public let remoteImages: Bool
  public let style: DocumentStyle
  public let revision: UInt64?
  public var zoomScale: Double
  public let callouts: CalloutEditorController?
  public var scrolling: DocumentScrollCoordinator?
  public var openDroppedFiles: (@MainActor ([URL]) -> Bool)?
  public var onError: @MainActor (String?) -> Void

  public init(
    html: String, directory: URL?, remoteImages: Bool = false, style: DocumentStyle = .init(),
    assetAccess: DocumentAssetAccess? = nil, revision: UInt64? = nil,
    callouts: CalloutEditorController? = nil,
    openDroppedFiles: (@MainActor ([URL]) -> Bool)? = nil,
    scrolling: DocumentScrollCoordinator? = nil, zoomScale: Double = 1,
    onError: @escaping @MainActor (String?) -> Void = { _ in }
  ) {
    self.html = html
    self.directory = directory
    self.assetAccess = assetAccess
    self.remoteImages = remoteImages
    self.style = style
    self.revision = revision
    self.callouts = callouts
    self.onError = onError
    self.openDroppedFiles = openDroppedFiles
    self.scrolling = scrolling
    self.zoomScale = zoomScale
  }

  public func makeCoordinator() -> Coordinator { Coordinator() }

  static func configuration(
    handler: LocalResourceHandler, scrollHandler: (any WKScriptMessageHandler)? = nil
  ) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.setURLSchemeHandler(handler, forURLScheme: "mdasset")
    if let scrollHandler {
      configuration.userContentController.add(
        WeakScrollMessageHandler(scrollHandler), contentWorld: .defaultClient,
        name: "snowfolioScroll")
      configuration.userContentController.addUserScript(
        WKUserScript(
          source: PreviewScroll.bootstrap, injectionTime: .atDocumentEnd, forMainFrameOnly: true,
          in: .defaultClient))
    }
    return configuration
  }

  public func makeNSView(context: Context) -> WKWebView {
    let coordinator = context.coordinator
    let view = MarkdownPreviewWebView(
      frame: .zero,
      configuration: Self.configuration(handler: coordinator.resources, scrollHandler: coordinator))
    view.setAccessibilityIdentifier("markdownPreview")
    view.setAccessibilityLabel(String(localized: "Markdown preview"))
    view.registerForDraggedTypes([.fileURL])
    view.fileDrop.openFiles = openDroppedFiles
    coordinator.scrolling = scrolling
    scrolling?.attachPreview(coordinator)
    view.viewportLayoutChanged = { [weak coordinator] in coordinator?.scrolling?.layoutChanged() }
    view.navigationDelegate = coordinator
    coordinator.onError = onError
    coordinator.callouts = callouts
    coordinator.update(
      view, html: html, directory: directory, remoteImages: remoteImages, style: style,
      revision: revision, zoomScale: zoomScale, assetAccess: assetAccess)
    return view
  }

  public func updateNSView(_ view: WKWebView, context: Context) {
    if context.coordinator.scrolling !== scrolling {
      context.coordinator.scrolling?.detachPreview(context.coordinator)
      context.coordinator.scrolling = scrolling
    }
    scrolling?.attachPreview(context.coordinator)
    (view as? MarkdownPreviewWebView)?.fileDrop.openFiles = openDroppedFiles
    context.coordinator.onError = onError
    context.coordinator.callouts = callouts
    context.coordinator.update(
      view, html: html, directory: directory, remoteImages: remoteImages, style: style,
      revision: revision, zoomScale: zoomScale, assetAccess: assetAccess)
  }

  public static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    coordinator.scrolling?.detachPreview(coordinator)
    coordinator.scrolling = nil
    (view as? MarkdownPreviewWebView)?.viewportLayoutChanged = nil
    (view as? MarkdownPreviewWebView)?.fileDrop.openFiles = nil
    view.stopLoading()
    view.navigationDelegate = nil
    coordinator.resources.cancelAll()
    coordinator.resources.access = nil
    coordinator.resources.directory = nil
    coordinator.callouts?.close()
  }

  @MainActor
  public final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let resources = LocalResourceHandler()
    weak var scrolling: DocumentScrollCoordinator?
    private weak var scrollView: WKWebView?
    private var scrollContextRevision: UInt64?
    private var activatingScrollContext = false
    private var failedScrollRevision: UInt64?
    weak var callouts: CalloutEditorController?
    private var pendingRevision: UInt64?
    private var appliedRevision: UInt64?
    private var contentValid = false
    var onError: @MainActor (String?) -> Void = { _ in }
    private var navigation: WKNavigation?
    private var expectsInitialNavigation = false
    private var generation = UUID()
    private var ready = false
    private var applying = false
    private var zooming = false
    private var pendingZoom = 1.0
    private var failedZoom: Double?
    private var pendingHTML = ""
    private var pendingStyle = DocumentStyle()
    private var appliedStyle: DocumentStyle?
    private var appliedHTML: String?
    private var loadedRemoteImages: Bool?
    private var loadedDirectory: URL?
    private var loadedAssetAccessID: UUID?

    func update(
      _ view: WKWebView, html: String, directory: URL?, remoteImages: Bool,
      style: DocumentStyle = .init(), revision: UInt64? = nil, zoomScale: Double = 1,
      assetAccess: DocumentAssetAccess? = nil
    ) {
      scrollView = view
      pendingHTML = html
      pendingRevision = revision
      pendingStyle = style
      pendingZoom = zoomScale.isFinite ? min(16, max(0.25, zoomScale)) : 1
      if failedZoom != pendingZoom { failedZoom = nil }
      resources.directory = directory
      resources.access = assetAccess
      if loadedRemoteImages != remoteImages || loadedDirectory != directory
        || loadedAssetAccessID != assetAccess?.id
      {
        scrolling?.previewWillReload()
        ready = false
        scrollContextRevision = nil
        activatingScrollContext = false
        failedScrollRevision = nil
        generation = UUID()
        applying = false
        zooming = false
        failedZoom = nil
        resources.cancelAll()
        appliedHTML = nil
        appliedRevision = nil
        contentValid = false
        appliedStyle = style
        loadedRemoteImages = remoteImages
        loadedDirectory = directory
        loadedAssetAccessID = assetAccess?.id
        resources.beginNavigation()
        expectsInitialNavigation = true
        navigation = view.loadHTMLString(
          PreviewHTML.document(
            remoteImages: remoteImages, includeHighlighting: true, style: style, includeMath: true),
          baseURL: resources.baseURL)
      } else {
        applyLatest(to: view)
      }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard navigation === self.navigation else { return }
      expectsInitialNavigation = false
      ready = true
      onError(nil)
      applyLatest(to: webView)
    }

    private func applyLatest(to view: WKWebView) {
      guard ready, !applying else { return }
      if pendingStyle != appliedStyle {
        applyStyle(to: view)
        return
      }
      // HTML attributes and CSS identifiers distinguish canonically equivalent
      // Unicode sequences. Compare the actual published bytes, not Swift text equality.
      let sameHTML = appliedHTML.map { UTF8Text.equal($0, pendingHTML) } ?? false
      guard !sameHTML else {
        if contentValid {
          appliedRevision = pendingRevision
          if abs(view.pageZoom - pendingZoom) > 0.0001, failedZoom != pendingZoom {
            applyZoom(to: view)
          } else {
            activateScrollContext(in: view)
          }
        }
        return
      }
      let sent = pendingHTML
      let revision = pendingRevision
      let generation = generation
      applying = true
      view.callAsyncJavaScript(
        PreviewHTML.patch, arguments: ["html": sent], in: nil,
        in: .defaultClient
      ) { [weak self, weak view] result in
        guard let self, let view, self.generation == generation else { return }
        self.applying = false
        self.appliedHTML = sent
        switch result {
        case .success(let value):
          self.contentValid = (value as? Bool) == true
          self.appliedRevision = self.contentValid ? revision : nil
          self.onError(
            self.contentValid
              ? nil
              : String(localized: "The preview could not update. Reopen the document to try again.")
          )
        case .failure:
          self.contentValid = false
          self.appliedRevision = nil
          self.onError(
            String(localized: "The preview could not update. Reopen the document to try again."))
        }
        self.applyLatest(to: view)
      }
    }

    private func applyStyle(to view: WKWebView) {
      let sent = pendingStyle
      let generation = generation
      applying = true
      view.callAsyncJavaScript(
        PreviewHTML.updateStyle,
        arguments: ["css": sent.css, "codeCSS": sent.codeCSS, "bodyRoot": sent.usesBodyRoot],
        in: nil,
        in: .defaultClient
      ) { [weak self, weak view] result in
        guard let self, let view, self.generation == generation else { return }
        self.applying = false
        self.appliedStyle = sent
        switch result {
        case .success(let value):
          self.onError(
            (value as? Bool) == true
              ? nil : String(localized: "The document style could not update."))
        case .failure:
          self.onError(String(localized: "The document style could not update."))
        }
        self.applyLatest(to: view)
      }
    }

    private func applyZoom(to view: WKWebView) {
      let scale = pendingZoom
      let generation = generation
      applying = true
      zooming = true
      view.callAsyncJavaScript(PreviewZoom.capture, arguments: [:], in: nil, in: .defaultClient) {
        [weak self, weak view] result in
        guard let self, let view, self.generation == generation else { return }
        guard case .success(let value) = result,
          let data = try? JSONSerialization.data(withJSONObject: value),
          let anchor = try? JSONDecoder().decode(PreviewZoomAnchor.self, from: data),
          anchor.fraction.isFinite, (0...1).contains(anchor.fraction)
        else {
          self.failedZoom = scale
          self.applying = false
          self.zooming = false
          self.onError(String(localized: "The reading zoom could not update."))
          self.applyLatest(to: view)
          return
        }
        view.pageZoom = scale
        let position = anchor.position.flatMap { $0.isValid ? $0 : nil }
        view.callAsyncJavaScript(
          PreviewZoom.restore,
          arguments: [
            "line": position.map { $0.line as Any } ?? NSNull(),
            "atTop": position?.atTop ?? false, "atBottom": position?.atBottom ?? false,
            "fraction": anchor.fraction,
            "inputEpoch": anchor.inputEpoch.map { $0 as Any } ?? NSNull(),
          ], in: nil, in: .defaultClient
        ) { [weak self, weak view] result in
          guard let self, let view, self.generation == generation else { return }
          self.applying = false
          self.zooming = false
          if case .failure = result {
            self.onError(String(localized: "The preview reading position could not be restored."))
          }
          if case .success(let value) = result,
            let data = try? JSONSerialization.data(withJSONObject: value),
            let actual = try? JSONDecoder().decode(PreviewZoomAnchor.self, from: data)
          {
            self.scrolling?.previewPresentationChanged(
              to: actual.position, userInitiated: actual.inputEpoch != anchor.inputEpoch)
          }
          self.applyLatest(to: view)
        }
      }
    }

    func isReadyForScrolling(revision: UInt64) -> Bool {
      guard let view = scrollView else { return false }
      return ready && contentValid && !applying && appliedRevision == revision
        && scrollContextRevision == revision && view.window != nil
        && !view.isHiddenOrHasHiddenAncestor && view.bounds.height > 0
    }

    private func activateScrollContext(in view: WKWebView) {
      guard scrolling != nil, ready, contentValid, !applying,
        let revision = appliedRevision, !activatingScrollContext,
        failedScrollRevision != revision
      else { return }
      if scrollContextRevision == revision {
        scrolling?.layoutChanged()
        return
      }
      activatingScrollContext = true
      let generation = generation
      view.callAsyncJavaScript(
        PreviewScroll.activate,
        arguments: ["token": generation.uuidString, "revision": String(revision)],
        in: nil, in: .defaultClient
      ) { [weak self, weak view] result in
        guard let self, let view, self.generation == generation else { return }
        self.activatingScrollContext = false
        if case .success(let value) = result, (value as? Bool) == true,
          self.appliedRevision == revision
        {
          self.scrollContextRevision = revision
          self.scrolling?.layoutChanged()
        } else if self.appliedRevision == revision {
          self.failedScrollRevision = revision
          self.onError(
            String(localized: "Scroll linking could not start. Reopen the document to try again."))
        }
        if self.appliedRevision != revision { self.activateScrollContext(in: view) }
      }
    }

    func moveForScrolling(
      to position: MarkdownScrollPosition,
      completion: @escaping @MainActor () -> Void
    ) {
      guard position.isValid, let view = scrollView, let revision = appliedRevision,
        isReadyForScrolling(revision: revision)
      else {
        completion()
        return
      }
      view.callAsyncJavaScript(
        PreviewScroll.move,
        arguments: ["line": position.line, "atTop": position.atTop, "atBottom": position.atBottom],
        in: nil, in: .defaultClient
      ) { _ in completion() }
    }

    public func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard !zooming, message.name == "snowfolioScroll", message.frameInfo.isMainFrame,
        let view = scrollView, message.webView === view, view.window?.isVisible == true,
        !view.isHiddenOrHasHiddenAncestor, let body = message.body as? [String: Any],
        let data = try? JSONSerialization.data(withJSONObject: body),
        let value = try? JSONDecoder().decode(PreviewScrollMessage.self, from: data),
        value.token == generation.uuidString, let revision = UInt64(value.revision),
        revision == appliedRevision
      else { return }
      scrolling?.previewScrolled(
        value.position, revision: revision,
        programmatic: value.programmatic, settled: value.settled)
    }

    public func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
      guard navigation === self.navigation else { return }
      expectsInitialNavigation = false
      ready = false
      onError(String(localized: "The preview could not load. Reopen the document to try again."))
    }

    public func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      self.webView(webView, didFail: navigation, withError: error)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      expectsInitialNavigation = false
      ready = false
      onError(String(localized: "The preview stopped. Reopen the document to try again."))
    }

    private func showCalloutPicker(line: Int, in view: WKWebView) {
      guard ready, contentValid, !applying, let revision = appliedRevision, let callouts else {
        return
      }
      let generation = generation
      view.callAsyncJavaScript(
        "const icon = document.querySelector('a.md-callout-icon[href=\"mdcallout://icon/' + line + '\"]'); if (!icon) return ''; const r = icon.getBoundingClientRect(); return JSON.stringify([r.x,r.y,r.width,r.height]);",
        arguments: ["line": line], in: nil, in: .defaultClient
      ) { [weak self, weak view, weak callouts] result in
        guard let self, let view, let callouts, self.generation == generation,
          case .success(let value) = result, let json = value as? String,
          let data = json.data(using: .utf8),
          let values = try? JSONDecoder().decode([Double].self, from: data),
          values.count == 4, values.allSatisfy(\.isFinite)
        else { return }
        // DOM rectangles use CSS pixels; popover anchors use native view points.
        let scaled = values.map { $0 * view.pageZoom }
        let y = view.isFlipped ? scaled[1] : view.bounds.height - scaled[1] - scaled[3]
        let rect = NSRect(x: scaled[0], y: y, width: scaled[2], height: scaled[3]).intersection(
          view.bounds)
        guard !rect.isEmpty else { return }
        if !callouts.present(line: line, revision: revision, relativeTo: rect, in: view) {
          self.onError(
            String(localized: "The preview is updating. Choose the callout emoji again."))
        }
      }
    }

    public func webView(
      _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = navigationAction.request.url else {
        decisionHandler(.cancel)
        return
      }
      if navigationAction.navigationType == .linkActivated {
        if url.scheme == "mdcallout", url.host == "icon", url.query == nil, url.fragment == nil,
          let line = Int(url.path.dropFirst()), line > 0
        {
          showCalloutPicker(line: line, in: webView)
        } else if let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment,
          ["mdasset", "about"].contains(url.scheme ?? "")
        {
          webView.callAsyncJavaScript(
            "document.getElementById(id)?.scrollIntoView();",
            arguments: ["id": fragment], in: nil, in: .defaultClient)
        } else if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
          NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
      } else {
        // More than one app-owned load can be awaiting policy while a document's
        // directory/CSP changes. Keep the gate open until the current navigation
        // finishes; consuming it in the first callback can cancel the replacement.
        // Only the current exact skeleton URL (or about:blank) is allowed, never arbitrary assets.
        let skeletonURL =
          url.absoluteString == "about:blank" || url == resources.baseURL
        let initial =
          expectsInitialNavigation && navigationAction.navigationType == .other && skeletonURL
        decisionHandler(initial ? .allow : .cancel)
      }
    }
  }
}

@MainActor
final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
  var directory: URL?
  var access: DocumentAssetAccess?
  private var resourceHost = "document"
  var baseURL: URL { URL(string: "mdasset://" + resourceHost + "/")! }

  func beginNavigation() {
    // A relative name can mean different bytes in another folder. Distinct origins
    // prevent WebKit's decoded-image cache from reusing the previous grant's image.
    resourceHost = "document-" + UUID().uuidString.lowercased()
  }

  private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    let key = ObjectIdentifier(urlSchemeTask)
    guard let directory, let request = urlSchemeTask.request.url,
      request.scheme == "mdasset", request.host == resourceHost,
      var components = URLComponents(url: request, resolvingAgainstBaseURL: false)
    else {
      urlSchemeTask.didFailWithError(LocalPreviewResourceError.forbiddenURL)
      return
    }
    components.host = "document"
    guard let url = components.url else {
      urlSchemeTask.didFailWithError(LocalPreviewResourceError.forbiddenURL)
      return
    }
    let access = access
    tasks[key] = Task { [weak self] in
      defer {
        withExtendedLifetime(access) {}
        self?.tasks[key] = nil
      }
      do {
        let resource = try await LocalPreviewResource.load(url, relativeTo: directory)
        try Task.checkCancellation()
        let response = URLResponse(
          url: url, mimeType: resource.mimeType,
          expectedContentLength: resource.data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(resource.data)
        urlSchemeTask.didFinish()
      } catch is CancellationError {
        // WebKit has already stopped this request.
      } catch {
        guard !Task.isCancelled else { return }
        urlSchemeTask.didFailWithError(error)
      }
    }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
    tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
  }

  func cancelAll() {
    for task in tasks.values { task.cancel() }
    tasks.removeAll()
  }
}

private struct PreviewZoomAnchor: Decodable {
  let position: MarkdownScrollPosition?
  let fraction: Double
  let inputEpoch: Int?
}

private struct PreviewScrollMessage: Decodable {
  let token: String
  let revision: String
  let position: MarkdownScrollPosition
  let programmatic: Bool
  let settled: Bool
}

@MainActor
private final class WeakScrollMessageHandler: NSObject, WKScriptMessageHandler {
  private weak var target: (any WKScriptMessageHandler)?
  init(_ target: any WKScriptMessageHandler) { self.target = target }
  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    target?.userContentController(userContentController, didReceive: message)
  }
}
