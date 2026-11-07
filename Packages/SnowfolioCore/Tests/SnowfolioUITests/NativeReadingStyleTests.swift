import AppKit
import DocumentCore
import Foundation
import RenderingCore
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native reading style compatibility", .serialized, NativeUIExclusive())
@MainActor
struct NativeReadingStyleTests {
  private func evaluate(_ script: String, in web: WKWebView, arguments: [String: Any] = [:])
    async throws -> String
  {
    try #require(
      try await web.callAsyncJavaScript(
        script, arguments: arguments, in: nil, contentWorld: .defaultClient) as? String)
  }

  private func waitFor(_ stage: String = "style state", _ predicate: () async throws -> Bool)
    async throws
  {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    Issue.record("Native reading style did not settle: \(stage)")
    throw CocoaError(.coderReadCorrupt)
  }

  @Test(
    "Reading style choices propagate through the hosted workspace without replacing native views")
  func workspaceStyles() async throws {
    _ = NSApplication.shared
    let domain = "WorkspaceReadingStyles." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = "# Reading style checkpoint\n\nPreserved source."
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let host = NSHostingController(
      rootView: DocumentWorkspace(document: document, preferences: preferences))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1100, height: 600))
    window.orderFront(nil)
    defer { window.close() }
    func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
      if let found = view as? T { return found }
      return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
    try await waitFor("workspace native surfaces") {
      descendant(WKWebView.self, in: host.view) != nil
        && descendant(MarkdownTextView.self, in: host.view) != nil
    }
    let web = try #require(descendant(WKWebView.self, in: host.view))
    let editor = try #require(descendant(MarkdownTextView.self, in: host.view))
    try await waitFor("workspace content") {
      try await evaluate("return document.body.innerText;", in: web)
        .contains("Reading style checkpoint")
    }
    let selection = NSRange(location: 2, length: 7)
    editor.setSelectedRange(selection)
    for entry in ReadingStyleEntry.all + [ReadingStyleEntry.notebook] {
      await preferences.readingStyles.select(entry.id)
      let style = preferences.documentStyle
      try await waitFor("workspace " + entry.title) {
        try await evaluate(
          "return String(document.querySelector('#document-style').textContent===css && (document.getElementById('preview-content')===document.body)===bodyRoot);",
          in: web, arguments: ["css": style.css, "bodyRoot": style.usesBodyRoot]) == "true"
      }
      if entry.id == "bundled:Clearness Dark" {
        #expect(
          try await evaluate("return getComputedStyle(document.body).backgroundColor;", in: web)
            == "rgb(40, 42, 54)")
      }
      #expect(descendant(WKWebView.self, in: host.view) === web)
      #expect(descendant(MarkdownTextView.self, in: host.view) === editor)
      #expect(editor.selectedRange() == selection)
      #expect(document.text.utf8.elementsEqual(source.utf8) && document.revision == 0)
    }
  }

  @Test(
    "Original CSS matches a direct-body baseline and switches retain selection, nodes and reading position",
    arguments: [false, true])
  func compatibility(dark: Bool) async throws {
    _ = NSApplication.shared
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 400),
      configuration: NativeMarkdownPreview.configuration(
        handler: coordinator.resources, scrollHandler: coordinator))
    let baseline = WKWebView(
      frame: web.frame,
      configuration: NativeMarkdownPreview.configuration(handler: LocalResourceHandler()))
    web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    baseline.appearance = web.appearance
    web.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: web.frame, styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = web
    window.orderFront(nil)
    defer {
      web.stopLoading()
      baseline.stopLoading()
      web.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.close()
    }
    var error: String?
    coordinator.onError = { error = $0 }
    let html =
      "<h1>Reading styles</h1>"
      + (0..<100).map {
        "<p data-sourcepos='\($0 + 1):1-\($0 + 1):12'>Paragraph \($0) preserved text</p>"
      }.joined()
      + "<table><tr><th>Column</th></tr><tr><td>Value</td></tr></table>"
    coordinator.update(web, html: html, directory: nil, remoteImages: false)
    try await waitFor {
      try await evaluate("return document.querySelector('p')?.textContent ?? '';", in: web)
        == "Paragraph 0 preserved text"
    }
    _ = try await evaluate(
      """
      window.firstText = document.querySelectorAll('p')[0].firstChild;
      window.secondText = document.querySelectorAll('p')[1].firstChild;
      window.savedHeading = document.querySelector('h1');
      window.scrollTo(0,500); return 'ready';
      """, in: web)
    let inspect = """
      const b=getComputedStyle(document.body), h=getComputedStyle(document.querySelector('h1')),
        p=getComputedStyle(document.querySelector('p')), t=getComputedStyle(document.querySelector('td'));
      return JSON.stringify([b.color,b.backgroundColor,b.fontSize,b.paddingTop,b.marginLeft,
        h.fontSize,h.marginTop,h.marginBottom,p.marginBottom,t.borderTopWidth,t.paddingLeft]);
      """
    let repository = ReadingStyleRepository()
    for entry in ReadingStyleEntry.all + [ReadingStyleEntry.notebook] {
      let presentation = try await repository.load(entry.id)
      let style = DocumentStyle(presentation: presentation)
      _ = try await evaluate(
        """
        const selection=window.getSelection(); selection.setBaseAndExtent(window.secondText,9,window.firstText,3);
        window.rawSelection=selection.getRangeAt(0).toString();
        window.readingAnchor=[...document.querySelectorAll('[data-sourcepos]')].find(e=>e.getBoundingClientRect().bottom>0);
        window.anchorTop=window.readingAnchor.getBoundingClientRect().top; return 'ready';
        """, in: web)
      coordinator.update(web, html: html, directory: nil, remoteImages: false, style: style)
      try await waitFor {
        try await evaluate(
          "return String(document.querySelector('#document-style').textContent===expected && (document.getElementById('preview-content')===document.body)===bodyRoot);",
          in: web, arguments: ["expected": style.css, "bodyRoot": style.usesBodyRoot]) == "true"
      }
      #expect(
        try await evaluate(
          """
          const s=window.getSelection();
          return String(window.savedHeading===document.querySelector('h1') &&
            s.anchorNode===window.secondText && s.anchorOffset===9 && s.focusNode===window.firstText && s.focusOffset===3 &&
            s.getRangeAt(0).toString()===window.rawSelection && Math.abs(window.readingAnchor.getBoundingClientRect().top-window.anchorTop)<2);
          """, in: web) == "true", "\(entry.title)")
      if style.usesBodyRoot {
        baseline.loadHTMLString(
          "<!doctype html><html><head><style>" + style.css
            + "</style></head><body data-style-check=\"" + entry.id + "\">" + html
            + "</body></html>", baseURL: nil)
        try await waitFor {
          try await evaluate("return document.body?.dataset.styleCheck ?? '';", in: baseline)
            == entry.id
        }
        #expect(
          try await evaluate(inspect, in: web) == evaluate(inspect, in: baseline), "\(entry.title)")
        #expect(
          try await evaluate(
            "return String(document.querySelector('body > h1')===window.savedHeading);", in: web)
            == "true")
      }
      #expect(error == nil)
    }
    // Whole-root selections may use element endpoints, rather than text nodes.
    for bodyRoot in [true, false, true, false] {
      _ = try await evaluate(
        "const root=document.getElementById('preview-content'); const s=window.getSelection(); s.selectAllChildren(root); window.rawSelection=s.getRangeAt(0).toString(); return 'ready';",
        in: web)
      let style = DocumentStyle(presentation: bodyRoot ? .unstyled : .notebook)
      coordinator.update(web, html: html, directory: nil, remoteImages: false, style: style)
      try await waitFor {
        try await evaluate(
          "return String((document.getElementById('preview-content')===document.body)===bodyRoot);",
          in: web, arguments: ["bodyRoot": bodyRoot]) == "true"
      }
      #expect(
        try await evaluate(
          "const s=window.getSelection(),root=document.getElementById('preview-content'); return String(s.anchorNode===root && s.anchorOffset===0 && s.focusNode===root && s.focusOffset===root.childNodes.length && s.getRangeAt(0).toString()===window.rawSelection);",
          in: web) == "true")
    }
    // A delayed image/font/layout change must invalidate the new root's geometry,
    // rather than leave the ResizeObserver attached to the removed main element.
    coordinator.update(
      web, html: html, directory: nil, remoteImages: false,
      style: DocumentStyle(presentation: .unstyled))
    try await waitFor {
      try await evaluate(
        "return String(document.getElementById('preview-content')===document.body);", in: web)
        == "true"
    }
    _ = try await evaluate(
      """
      window.getSelection().removeAllRanges();
      window.scrollTo(0,500);
      if (window.__snowfolioScroll.position().line<=2) throw new Error('Expected a cached later source line');
      document.querySelector('p').style.height='3000px';
      document.body.getBoundingClientRect(); window.scrollTo(0,500); return 'ready';
      """, in: web)
    try await waitFor("late source geometry") {
      try await evaluate(
        "const line=window.__snowfolioScroll.position().line; return String(line>=1 && line<2);",
        in: web) == "true"
    }

  }

  @Test("CSS markup-like string content stays CSS during initial load and live updates")
  func cssRawText() async throws {
    let css =
      "body > p { color: rgb(1, 2, 3) } p::after { content: '</style><img id=\"escaped\" src=x><script>bad()</script>'; }"
    let style = DocumentStyle(
      presentation: .stylesheet(try DocumentStylesheet(data: Data(css.utf8))))
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 600, height: 400),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    web.navigationDelegate = coordinator
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      coordinator.resources.cancelAll()
    }
    coordinator.update(
      web, html: "<p>Safe text</p>", directory: nil, remoteImages: false, style: style)
    try await waitFor {
      try await evaluate("return document.querySelector('p')?.textContent ?? '';", in: web)
        == "Safe text"
    }
    let inspect =
      "return JSON.stringify([document.querySelectorAll('#escaped,script,img').length,getComputedStyle(document.querySelector('p')).color,getComputedStyle(document.querySelector('p'),'::after').content]);"
    let initial = try await evaluate(inspect, in: web)
    #expect(
      initial.contains("</style><img") && initial.contains("rgb(1, 2, 3)")
        && initial.hasPrefix("[0,"))
    coordinator.update(web, html: "<p>Safe text</p>", directory: nil, remoteImages: false)
    try await waitFor {
      try await evaluate("return String(document.querySelector('main')!==null);", in: web) == "true"
    }
    coordinator.update(
      web, html: "<p>Safe text</p>", directory: nil, remoteImages: false, style: style)
    try await waitFor { try await evaluate(inspect, in: web) == initial }
    let firstCSS = "p { color: rgb(1,2,3) } .café { color: rgb(4,5,6) }"
    let secondCSS = "p { color: rgb(1,2,3) } .cafe\u{301} { color: rgb(4,5,6) }"
    #expect(firstCSS == secondCSS)
    let unicodeHTML = "<p class='café'>Unicode selector</p>"
    coordinator.update(
      web, html: unicodeHTML, directory: nil, remoteImages: false,
      style: DocumentStyle(
        presentation: .stylesheet(try DocumentStylesheet(data: Data(firstCSS.utf8)))))
    try await waitFor {
      try await evaluate("return getComputedStyle(document.querySelector('p')).color;", in: web)
        == "rgb(4, 5, 6)"
    }
    _ = try await evaluate(
      "window.unicodeNode=document.querySelector('p'); return 'ready';", in: web)
    coordinator.update(
      web, html: unicodeHTML, directory: nil, remoteImages: false,
      style: DocumentStyle(
        presentation: .stylesheet(try DocumentStylesheet(data: Data(secondCSS.utf8)))))
    try await waitFor {
      try await evaluate("return getComputedStyle(document.querySelector('p')).color;", in: web)
        == "rgb(1, 2, 3)"
    }
    #expect(
      try await evaluate(
        "return String(document.querySelector('p')===window.unicodeNode);", in: web) == "true")

    let decomposedHTML = "<p class='cafe\u{301}'>Unicode selector</p>"
    #expect(decomposedHTML == unicodeHTML)
    coordinator.update(
      web, html: decomposedHTML, directory: nil, remoteImages: false,
      style: DocumentStyle(
        presentation: .stylesheet(try DocumentStylesheet(data: Data(secondCSS.utf8)))))
    try await waitFor("Unicode HTML identity") {
      try await evaluate("return getComputedStyle(document.querySelector('p')).color;", in: web)
        == "rgb(4, 5, 6)"
    }
    #expect(
      try await evaluate(
        "return String(document.querySelector('p')===window.unicodeNode);", in: web) == "true")

  }
}
