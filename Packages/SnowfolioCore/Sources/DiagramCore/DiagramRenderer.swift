import AppKit
import Foundation
import MathCore
import WebKit

/// A separate web-content process supplies DOM measurements and WebAssembly.
/// Only bundled engines run in its client world; Markdown never becomes code.
@MainActor
public final class DiagramRenderer: NSObject, WKNavigationDelegate {
  public static let shared = DiagramRenderer()
  private struct Request {
    let id: UUID
    let source: String
    let kind: DiagramKind
    let key: String
    let continuation: CheckedContinuation<RenderedDiagram, any Error>
  }
  private enum Failure: Error { case unavailable, invalid }
  private struct Output: Decodable {
    let ok: Bool
    let svg: String?
    let warning: Bool?
  }

  private let deadline: Duration
  private var queued: [Request] = []
  private var active: Request?
  private var operation: Task<Void, Never>?
  private var timeout: Task<Void, Never>?
  private var web: WKWebView?
  private var navigation: WKNavigation?
  private var expectsNavigation = false
  private var ready = false
  private var epoch = UUID()
  private var waiting: CheckedContinuation<String, any Error>?
  private var loaded: Set<String> = []
  private var cache: [String: RenderedDiagram] = [:]
  private var cacheBytes = 0
  var hasPendingWork: Bool { active != nil || !queued.isEmpty }
  var hasWorker: Bool { web != nil }

  public init(timeout: Duration = .seconds(15)) {
    deadline = timeout
    super.init()
  }

  public func render(_ source: String, kind: DiagramKind) async throws -> RenderedDiagram {
    try Task.checkCancellation()
    guard source.utf8.count <= 65_536 else { return .failure(.tooLarge) }
    let key = RenderedDiagram.key(source: source, kind: kind)
    if let result = cache[key] { return result }
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard !Task.isCancelled else {
          continuation.resume(throwing: CancellationError())
          return
        }
        queued.append(
          Request(id: id, source: source, kind: kind, key: key, continuation: continuation))
        startNext()
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancel(id) }
    }
  }

  private func startNext() {
    guard active == nil else { return }
    while !queued.isEmpty {
      let request = queued.removeFirst()
      if let cached = cache[request.key] {
        request.continuation.resume(returning: cached)
        continue
      }
      active = request
      operation = Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          try await ensureWorker()
          try await ensureEngine(request.kind)
          let light = try await renderSVG(request.source, kind: request.kind, dark: false)
          try Task.checkCancellation()
          let dark = try await renderSVG(request.source, kind: request.kind, dark: true)
          try Task.checkCancellation()
          let lightSVG = try await DiagramSVG.sanitize(light.svg, variant: "light")
          let darkSVG = try await DiagramSVG.sanitize(dark.svg, variant: "dark")
          try Task.checkCancellation()
          finish(
            request.id,
            result: .success(
              RenderedDiagram(
                lightSVG: lightSVG, darkSVG: darkSVG,
                issue: light.warning || dark.warning ? .rendererWarning : nil)))
        } catch is CancellationError {
          finish(request.id, result: .failure(CancellationError()))
        } catch DiagramSVGError.tooLarge {
          finish(request.id, result: .success(.failure(.tooLarge)))
        } catch DiagramSVGError.unsafe {
          finish(request.id, result: .success(.failure(.unsafeOutput)))
        } catch Failure.unavailable {
          finish(request.id, result: .success(.failure(.unavailableEngine)))
        } catch {
          finish(request.id, result: .success(.failure(.invalidSource)))
        }
      }
      timeout = Task { @MainActor [weak self] in
        guard let self else { return }
        do { try await Task.sleep(for: deadline) } catch { return }
        guard active?.id == request.id else { return }
        operation?.cancel()
        resetWorker()
        finish(request.id, result: .success(.failure(.timedOut)))
      }
      return
    }
  }

  private func finish(_ id: UUID, result: Result<RenderedDiagram, any Error>) {
    guard let request = active, request.id == id else { return }
    timeout?.cancel()
    timeout = nil
    operation = nil
    active = nil
    if case .success(let value) = result, value.isRendered {
      let cost =
        request.source.utf8.count + (value.lightSVG?.utf8.count ?? 0)
        + (value.darkSVG?.utf8.count ?? 0)
      if cost <= 8_388_608 {
        if cache.count >= 32 || cacheBytes + cost > 8_388_608 {
          cache.removeAll(keepingCapacity: true)
          cacheBytes = 0
        }
        cache[request.key] = value
        cacheBytes += cost
      }
    }
    request.continuation.resume(with: result)
    startNext()
  }

  private func cancel(_ id: UUID) {
    if let index = queued.firstIndex(where: { $0.id == id }) {
      queued.remove(at: index).continuation.resume(throwing: CancellationError())
    } else if active?.id == id {
      operation?.cancel()
      resetWorker()
      finish(id, result: .failure(CancellationError()))
    }
  }

  public func close() {
    let pending = queued
    queued.removeAll()
    for request in pending { request.continuation.resume(throwing: CancellationError()) }
    if let id = active?.id { cancel(id) } else { resetWorker() }
    cache.removeAll()
    cacheBytes = 0
  }

  private func resetWorker() {
    epoch = UUID()
    ready = false
    expectsNavigation = false
    navigation = nil
    loaded.removeAll()
    web?.stopLoading()
    web?.navigationDelegate = nil
    web = nil
    resolve(.failure(CancellationError()))
  }

  private func ensureWorker() async throws {
    try Task.checkCancellation()
    if ready, web != nil { return }
    // A failed or terminated worker has lost its JavaScript globals.
    // Engine readiness and late callbacks belong to this new instance only.
    epoch = UUID()
    loaded.removeAll()
    _ = NSApplication.shared
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let view = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
    view.navigationDelegate = self
    web = view
    expectsNavigation = true
    _ = try await withCheckedThrowingContinuation { continuation in
      waiting = continuation
      navigation = view.loadHTMLString(
        Self.skeleton,
        baseURL: URL(string: "https://snowfolio.invalid/"))
    }
    try Task.checkCancellation()
  }

  private func ensureEngine(_ kind: DiagramKind) async throws {
    let name = kind.isMermaid ? "Mermaid" : "Viz"
    if loaded.contains(name) { return }
    let current = epoch
    let source = try await DiagramResources.script(name)
    try Task.checkCancellation()
    guard current == epoch else { throw CancellationError() }
    _ = try await execute(source + "\n;void 0;", arguments: nil)
    try Task.checkCancellation()
    guard current == epoch else { throw CancellationError() }
    loaded.insert(name)
  }

  private func renderSVG(_ source: String, kind: DiagramKind, dark: Bool) async throws -> (
    svg: String, warning: Bool
  ) {
    let json = try await execute(
      Self.renderScript,
      arguments: ["source": source, "kind": kind.rawValue, "dark": dark])
    guard json.utf8.count <= 4_194_304, let data = json.data(using: .utf8),
      let result = try? JSONDecoder().decode(Output.self, from: data), result.ok,
      let svg = result.svg
    else { throw Failure.invalid }
    return (svg, result.warning == true)
  }

  private func execute(_ script: String, arguments: [String: Any]?) async throws -> String {
    try Task.checkCancellation()
    guard let view = web, ready, waiting == nil else { throw Failure.unavailable }
    let current = epoch
    return try await withCheckedThrowingContinuation { continuation in
      waiting = continuation
      let completed: @MainActor (Result<Any, any Error>) -> Void = {
        [weak self, weak view] result in
        guard let self, let view, self.web === view, self.epoch == current else { return }
        switch result {
        case .success(let value): self.resolve(.success(value as? String ?? ""))
        case .failure: self.resolve(.failure(Failure.unavailable))
        }
      }
      if let arguments {
        view.callAsyncJavaScript(
          script, arguments: arguments, in: nil, in: .defaultClient, completionHandler: completed)
      } else {
        view.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: completed)
      }
    }
  }

  private func resolve(_ result: Result<String, any Error>) {
    let continuation = waiting
    waiting = nil
    continuation?.resume(with: result)
  }

  public func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
    guard view === web, navigation === self.navigation else { return }
    self.navigation = nil
    expectsNavigation = false
    ready = true
    resolve(.success(""))
  }
  public func webView(_ view: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
  {
    guard view === web, navigation === self.navigation else { return }
    ready = false
    expectsNavigation = false
    resolve(.failure(Failure.unavailable))
  }
  public func webView(
    _ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    webView(view, didFail: navigation, withError: error)
  }
  public func webViewWebContentProcessDidTerminate(_ view: WKWebView) {
    guard view === web else { return }
    ready = false
    resolve(.failure(Failure.unavailable))
  }
  public func webView(
    _ view: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    let initial =
      view === web && expectsNavigation && action.navigationType == .other
      && ["about:blank", "https://snowfolio.invalid/"].contains(
        action.request.url?.absoluteString ?? "")
    decisionHandler(initial ? .allow : .cancel)
  }

  private static var skeleton: String {
    """
    <!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-eval' 'wasm-unsafe-eval'; style-src 'unsafe-inline'; font-src data:; img-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'"><style>body{font-family:-apple-system,BlinkMacSystemFont,Helvetica,sans-serif;}\(MathStyle.css)</style></head><body></body></html>
    """
  }

  private static let renderScript = """
    try {
      await Promise.all([...document.fonts].map(font=>font.load()));
      const text=dark?'#e5e5e0':'#303b45', line=dark?'#8eabc0':'#607d90';
      let output, warning=false;
      if (kind==='mermaid') {
        mermaid.initialize({startOnLoad:false,securityLevel:'strict',htmlLabels:false,
          maxTextSize:65536,maxEdges:1000,theme:'base',deterministicIds:true,deterministicIDSeed:'snowfolio',
          secure:['secure','securityLevel','startOnLoad','maxTextSize','maxEdges','htmlLabels','flowchart','theme','themeVariables','themeCSS','fontFamily','dompurifyConfig'],
          flowchart:{htmlLabels:false,useMaxWidth:true},
          themeVariables:{darkMode:dark,background:dark?'#191919':'#ffffff',fontFamily:'Helvetica,Arial,sans-serif',
            primaryColor:dark?'#253743':'#e4f2fb',primaryTextColor:text,primaryBorderColor:line,
            secondaryColor:dark?'#303a35':'#edf3ed',tertiaryColor:dark?'#3c3530':'#f8f1e7',
            lineColor:line,textColor:text,edgeLabelBackground:dark?'#242424':'#ffffff'}});
        output=(await mermaid.render('sfDiagram',source)).svg;
      } else {
        globalThis.__sfViz ??= await Viz.instance();
        const result=globalThis.__sfViz.render(source,{format:'svg',engine:kind,
          graphAttributes:{bgcolor:'transparent',fontname:'Helvetica',fontcolor:text,color:line},
          nodeAttributes:{fontname:'Helvetica',fontcolor:text,color:line},
          edgeAttributes:{fontname:'Helvetica',fontcolor:text,color:line}});
        if(result.status!=='success') return JSON.stringify({ok:false});
        output=result.output; warning=result.errors?.length>0;
      }
      if (typeof output!=='string' || output.length>2097152) return JSON.stringify({ok:false});
      // An inert template normalizes HTML labels to well-formed SVG/XHTML XML.
      const holder=document.createElement('template'); holder.innerHTML=output;
      const svg=holder.content.querySelector('svg');
      if (!svg) return JSON.stringify({ok:false});
      svg.id ||= 'sfGraph';
      const scope='#'+CSS.escape(svg.id);
      for (const style of svg.querySelectorAll('style')) {
        const sheet=new CSSStyleSheet(); sheet.replaceSync(style.textContent);
        function scoped(rules) {
          for (const rule of rules) {
            if (rule.type===CSSRule.STYLE_RULE) {
              const selector=rule.selectorText;
              rule.selectorText=`:where(${scope}):is(${selector}),:where(${scope}) :is(${selector})`;
              if (rule.style.animationName) rule.style.setProperty('animation-name',rule.style.animationName);
            } else if (rule.type===CSSRule.MEDIA_RULE || rule.type===CSSRule.SUPPORTS_RULE) scoped(rule.cssRules);
            else if (rule.type!==CSSRule.KEYFRAMES_RULE) throw new Error('Unsupported SVG stylesheet');
          }
        }
        scoped(sheet.cssRules); style.textContent=[...sheet.cssRules].map(rule=>rule.cssText).join('\\n');
      }
      for (const element of svg.querySelectorAll('[style]')) {
        if (element.style?.animationName) element.style.setProperty('animation-name',element.style.animationName);
      }
      return JSON.stringify({ok:true,svg:new XMLSerializer().serializeToString(svg),warning});
    } catch { return JSON.stringify({ok:false}); } finally { document.body.replaceChildren(); }
    """
}

private enum DiagramResources {
  @concurrent static func script(_ name: String) async throws -> String {
    try Task.checkCancellation()
    guard let url = Bundle.module.url(forResource: name, withExtension: "js") else {
      throw CocoaError(.fileNoSuchFile)
    }
    let script = try String(contentsOf: url, encoding: .utf8)
    try Task.checkCancellation()
    return script
  }
}
