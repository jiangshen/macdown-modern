import AppKit
import RenderingCore
import SwiftUI
import WebKit

public struct NativeMarkdownPreview: NSViewRepresentable {
  public let html: String
  public let directory: URL?
  public let remoteImages: Bool
  public let style: DocumentStyle
  public let revision: UInt64?
  public let callouts: CalloutEditorController?
  public var onError: @MainActor (String?) -> Void

  public init(
    html: String, directory: URL?, remoteImages: Bool = false, style: DocumentStyle = .init(),
    revision: UInt64? = nil,
    callouts: CalloutEditorController? = nil,
    onError: @escaping @MainActor (String?) -> Void = { _ in }
  ) {
    self.html = html
    self.directory = directory
    self.remoteImages = remoteImages
    self.style = style
    self.revision = revision
    self.callouts = callouts
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
    coordinator.callouts = callouts
    coordinator.update(
      view, html: html, directory: directory, remoteImages: remoteImages, style: style,
      revision: revision)
    return view
  }

  public func updateNSView(_ view: WKWebView, context: Context) {
    context.coordinator.onError = onError
    context.coordinator.callouts = callouts
    context.coordinator.update(
      view, html: html, directory: directory, remoteImages: remoteImages, style: style,
      revision: revision)
  }

  public static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
    view.stopLoading()
    view.navigationDelegate = nil
    coordinator.resources.cancelAll()
    coordinator.callouts?.close()
  }

  @MainActor
  public final class Coordinator: NSObject, WKNavigationDelegate {
    let resources = LocalResourceHandler()
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
    private var pendingHTML = ""
    private var pendingStyle = DocumentStyle()
    private var appliedStyle: DocumentStyle?
    private var appliedHTML: String?
    private var loadedRemoteImages: Bool?
    private var loadedDirectory: URL?

    func update(
      _ view: WKWebView, html: String, directory: URL?, remoteImages: Bool,
      style: DocumentStyle = .init(), revision: UInt64? = nil
    ) {
      pendingHTML = html
      pendingRevision = revision
      pendingStyle = style
      resources.directory = directory
      if loadedRemoteImages != remoteImages || loadedDirectory != directory {
        ready = false
        generation = UUID()
        applying = false
        resources.cancelAll()
        appliedHTML = nil
        appliedRevision = nil
        contentValid = false
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
      guard pendingHTML != appliedHTML else {
        if contentValid { appliedRevision = pendingRevision }
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

    private func showCalloutPicker(line: Int, in view: WKWebView) {
      guard ready, contentValid, let revision = appliedRevision, let callouts else { return }
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
        let y = view.isFlipped ? values[1] : view.bounds.height - values[1] - values[3]
        let rect = NSRect(x: values[0], y: y, width: values[2], height: values[3]).intersection(
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
        } else if let fragment = url.fragment, ["mdasset", "about"].contains(url.scheme ?? "") {
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
