import AppKit
import Foundation
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

}
