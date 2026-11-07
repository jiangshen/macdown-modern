import AppKit
import Foundation
import MarkdownCore
import RenderingCore
import Testing
import WebKit

@testable import MacDownUI

@Suite("Live WebKit preview", .serialized)
@MainActor
struct NativeMarkdownPreviewTests {
  enum TestError: Error { case timeout, invalidResult }

  private func evaluate(_ script: String, in view: WKWebView) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      view.callAsyncJavaScript(script, arguments: [:], in: nil, in: .defaultClient) { result in
        switch result {
        case .success(let value):
          if let string = value as? String {
            continuation.resume(returning: string)
          } else {
            continuation.resume(throwing: TestError.invalidResult)
          }
        case .failure(let error): continuation.resume(throwing: error)
        }
      }
    }
  }

  private func waitFor(_ predicate: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    throw TestError.timeout
  }

  @Test(
    "A stable WebKit document patches content, preserves nodes and scroll, and blocks page scripts")
  func liveUpdates() async throws {
    _ = NSApplication.shared
    let coordinator = NativeMarkdownPreview.Coordinator()
    let view = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 500),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    view.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.orderFront(nil)
    defer {
      view.stopLoading()
      view.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.orderOut(nil)
    }
    var previewError: String?
    coordinator.onError = { previewError = $0 }
    let paragraphs = (0..<100).map {
      "<p data-sourcepos='\($0 + 1):1-\($0 + 1):9'>Paragraph \($0)</p>"
    }.joined()
    let html = "<h1>Document</h1>" + paragraphs
    coordinator.update(view, html: html, directory: nil, remoteImages: false)
    try await waitFor {
      (try? await evaluate("return document.querySelector('h1')?.textContent ?? '';", in: view))
        == "Document"
    }
    #expect(previewError == nil)
    _ = try await evaluate(
      "window.savedNode = document.querySelector('p'); window.scrollTo(0, 500); return 'ready';",
      in: view)
    coordinator.update(
      view,
      html: html
        + "<p id='added'>Added</p><script>document.body.dataset.executed='yes'</script><img src='data:x' onerror=\"document.body.dataset.executed='yes'\">",
      directory: nil, remoteImages: false)
    try await waitFor {
      (try? await evaluate("return document.getElementById('added')?.textContent ?? '';", in: view))
        == "Added"
    }
    #expect(
      try await evaluate(
        "return String(window.savedNode === document.querySelector('p'));", in: view) == "true")
    #expect(try await evaluate("return String(window.scrollY > 400);", in: view) == "true")
    #expect(
      try await evaluate("return document.body.dataset.executed ?? 'blocked';", in: view)
        == "blocked")
    #expect(previewError == nil)
    // A style change must keep the same page, content nodes and reading anchor.
    let updatedHTML = try await evaluate(
      "return document.getElementById('preview-content').innerHTML;", in: view)
    _ = try await evaluate(
      "window.readingAnchor = [...document.querySelectorAll('[data-sourcepos]')].find(e => e.getBoundingClientRect().bottom > 0); window.anchorTop = window.readingAnchor.getBoundingClientRect().top; return 'ready';",
      in: view)
    coordinator.update(
      view, html: updatedHTML, directory: nil, remoteImages: false,
      style: DocumentStyle(font: .serif, textSize: 20, fullWidth: true))
    try await waitFor {
      (try? await evaluate("return getComputedStyle(document.body).fontSize;", in: view)) == "20px"
    }
    #expect(
      try await evaluate(
        "return String(window.savedNode === document.querySelector('p'));", in: view) == "true")
    #expect(
      try await evaluate(
        "return String(Math.abs(window.readingAnchor.getBoundingClientRect().top - window.anchorTop) < 2);",
        in: view) == "true")
    #expect(
      try await evaluate(
        "return getComputedStyle(document.querySelector('main')).maxWidth;", in: view) == "none")
    #expect(previewError == nil)
  }
  @Test("WebKit loads relative local images and enforces CSP for remote images and frames")
  func resourcePolicy() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let png = try #require(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII="
      ))
    try png.write(to: root.appendingPathComponent("local image.png"))
    let coordinator = NativeMarkdownPreview.Coordinator()
    let view = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 500),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    view.navigationDelegate = coordinator
    defer {
      view.stopLoading()
      view.navigationDelegate = nil
      coordinator.resources.cancelAll()
    }
    coordinator.update(view, html: "<p id='ready'>Ready</p>", directory: root, remoteImages: false)
    try await waitFor {
      (try? await evaluate("return document.getElementById('ready')?.textContent ?? '';", in: view))
        == "Ready"
    }
    _ = try await evaluate(
      "window.violations = []; document.addEventListener('securitypolicyviolation', e => window.violations.push(e.violatedDirective)); return 'ready';",
      in: view)
    coordinator.update(
      view,
      html:
        "<img id='local' src='local%20image.png'><img src='https://example.invalid/blocked.png'><iframe src='https://example.invalid/blocked'></iframe>",
      directory: root, remoteImages: false)
    try await waitFor {
      (try? await evaluate(
        "return String(document.getElementById('local')?.naturalWidth ?? 0);", in: view)) == "1"
    }
    try await waitFor {
      (try? await evaluate(
        "return String(window.violations.includes('img-src') && window.violations.includes('frame-src'));",
        in: view)) == "true"
    }
  }

  @Test("Notebook typography, contrast and narrow layouts work in both appearances")
  func notebookPresentation() async throws {
    _ = NSApplication.shared
    let coordinator = NativeMarkdownPreview.Coordinator()
    let view = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 1000, height: 800),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    view.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    window.orderFront(nil)
    defer {
      view.stopLoading()
      view.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.orderOut(nil)
    }
    let callouts = try await MarkdownProcessor().render(
      "> [!NOTE]\n> A note for **clear thinking**.\n\n> [!WARNING]\n> Take care with `important details`."
    )
    coordinator.update(
      view,
      html:
        callouts.html
        + "<h1>Notebook</h1><p>日本語 中文 👩‍💻 <a href='https://example.com'>A readable link</a> and <code>inline code</code>.</p><h2>Details</h2><ul><li>First item</li><li><input type='checkbox' disabled checked>Completed</li></ul><blockquote><p>A quieter page for clear thinking.</p></blockquote><pre><code>let message = \"Hello, world\"</code></pre><table><tr><th>Feature</th><th>Status</th></tr><tr><td>Tables</td><td>Ready</td></tr></table>",
      directory: nil, remoteImages: false)
    try await waitFor {
      (try? await evaluate("return document.querySelector('h1')?.textContent ?? '';", in: view))
        == "Notebook"
    }
    #expect(
      try await evaluate(
        "return String(document.querySelectorAll('aside.md-callout').length);", in: view) == "2")
    #expect(
      try await evaluate(
        "return document.querySelector('.md-callout-title')?.textContent.trim() ?? '';", in: view)
        == "Note")
    for dark in [false, true] {
      window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      try await waitFor {
        (try? await evaluate(
          "return String(matchMedia('(prefers-color-scheme: dark)').matches);", in: view))
          == String(dark)
      }
      // Compute contrast from WebKit's resolved colors, including inherited links.
      #expect(
        try await evaluate(
          """
          const rgb = value => value.match(/[\\d.]+/g).slice(0,3).map(Number);
          const luminance = value => rgb(value).map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, v, i) => sum + v * [.2126,.7152,.0722][i], 0);
          const bg = luminance(getComputedStyle(document.body).backgroundColor);
          return String(['p','a','code','blockquote','th','td','.md-callout-title','.md-callout-body > p'].every(selector => {
            const node = document.querySelector(selector), style = getComputedStyle(node);
            const fg = luminance(style.color);
            let ancestor = node, surface = bg;
            while (ancestor) {
              const color = getComputedStyle(ancestor).backgroundColor;
              if (color !== 'rgba(0, 0, 0, 0)' && color !== 'transparent') { surface = luminance(color); break; }
              ancestor = ancestor.parentElement;
            }
            return (Math.max(fg,surface)+.05)/(Math.min(fg,surface)+.05) >= 4.5;
          }));
          """, in: view) == "true")
      #expect(
        try await evaluate(
          "return String(parseFloat(getComputedStyle(document.querySelector('h1')).fontSize) > parseFloat(getComputedStyle(document.querySelector('h2')).fontSize));",
          in: view) == "true")
      #expect(
        try await evaluate(
          "return String(document.querySelector('main').getBoundingClientRect().width <= 804);",
          in: view) == "true")
    }
    view.setFrameSize(NSSize(width: 320, height: 800))
    #expect(
      try await evaluate(
        "return String(document.documentElement.scrollWidth <= innerWidth);", in: view) == "true")
  }

}
