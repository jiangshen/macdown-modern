import AppKit
import RenderingCore
import SwiftUI
import WebKit

public struct NativeMarkdownPreview: NSViewRepresentable {
  public let html: String
  public let directory: URL?
  public let remoteImages: Bool
  public let style: DocumentStyle
  public var onError: @MainActor (String?) -> Void

  public init(
    html: String, directory: URL?, remoteImages: Bool = false, style: DocumentStyle = .init(),
    onError: @escaping @MainActor (String?) -> Void = { _ in }
  ) {
    self.html = html
    self.directory = directory
    self.remoteImages = remoteImages
    self.style = style
    self.onError = onError
  }

  public func makeCoordinator() -> Coordinator { Coordinator() }

  static func configuration(handler: LocalResourceHandler) -> WKWebViewConfiguration {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.setURLSchemeHandler(handler, forURLScheme: "mdasset")
    return configuration
  }

  public func makeNSView(context: Context) -> WKWebView {
    let coordinator = context.coordinator
    let view = WKWebView(
      frame: .zero, configuration: Self.configuration(handler: coordinator.resources))
    view.setAccessibilityIdentifier("markdownPreview")
    view.setAccessibilityLabel(String(localized: "Markdown preview"))
    view.navigationDelegate = coordinator
    coordinator.onError = onError
    coordinator.update(
      view, html: html, directory: directory, remoteImages: remoteImages, style: style)
    return view
  }

  public func updateNSView(_ view: WKWebView, context: Context) {
    context.coordinator.onError = onError
    context.coordinator.update(
      view, html: html, directory: directory, remoteImages: remoteImages, style: style)
  }

  public static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.stopLoading()
    view.navigationDelegate = nil
    coordinator.resources.cancelAll()
  }

  @MainActor
  public final class Coordinator: NSObject, WKNavigationDelegate {
    let resources = LocalResourceHandler()
    var onError: @MainActor (String?) -> Void = { _ in }
    private var navigation: WKNavigation?
    private var expectsInitialNavigation = false
    private var generation = UUID()
    private var ready = false
    private var applying = false
    private var pendingHTML = ""
    private var pendingStyle = DocumentStyle()
    private var appliedStyle: DocumentStyle?
    private var appliedHTML: String?
    private var loadedRemoteImages: Bool?
    private var loadedDirectory: URL?

    func update(
      _ view: WKWebView, html: String, directory: URL?, remoteImages: Bool,
      style: DocumentStyle = .init()
    ) {
      pendingHTML = html
      pendingStyle = style
      resources.directory = directory
      if loadedRemoteImages != remoteImages || loadedDirectory != directory {
        ready = false
        generation = UUID()
        applying = false
        resources.cancelAll()
        appliedHTML = nil
        appliedStyle = style
        loadedRemoteImages = remoteImages
        loadedDirectory = directory
        expectsInitialNavigation = true
        navigation = view.loadHTMLString(
          PreviewHTML.document(remoteImages: remoteImages, style: style),
          baseURL: URL(string: "mdasset://document/"))
      } else {
        applyLatest(to: view)
      }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard navigation === self.navigation else { return }
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
      guard pendingHTML != appliedHTML else { return }
      let sent = pendingHTML
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
          self.onError(
            (value as? Bool) == true
              ? nil
              : String(localized: "The preview could not update. Reopen the document to try again.")
          )
        case .failure:
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
        PreviewHTML.updateStyle, arguments: ["css": sent.css], in: nil, in: .defaultClient
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

    public func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
      guard navigation === self.navigation else { return }
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
      ready = false
      onError(String(localized: "The preview stopped. Reopen the document to try again."))
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
        if let fragment = url.fragment, ["mdasset", "about"].contains(url.scheme ?? "") {
          webView.callAsyncJavaScript(
            "document.getElementById(id)?.scrollIntoView();",
            arguments: ["id": fragment], in: nil, in: .defaultClient)
        } else if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
          NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
      } else {
        let initial =
          expectsInitialNavigation && navigationAction.navigationType == .other
          && ["about", "mdasset"].contains(url.scheme ?? "")
        if initial { expectsInitialNavigation = false }
        decisionHandler(initial ? .allow : .cancel)
      }
    }
  }
}

@MainActor
final class LocalResourceHandler: NSObject, WKURLSchemeHandler {
  var directory: URL?
  private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    let key = ObjectIdentifier(urlSchemeTask)
    guard let directory, let url = urlSchemeTask.request.url else {
      urlSchemeTask.didFailWithError(LocalPreviewResourceError.forbiddenURL)
      return
    }
    tasks[key] = Task { [weak self] in
      defer { self?.tasks[key] = nil }
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
