import AppKit
import MarkdownCore
import RenderingCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native list selection", .serialized, NativeUIExclusive())
@MainActor
struct NativeSelectionRenderingTests {
  @Test(
    "Numbered list selection and hanging indentation survive style updates",
    arguments: [false, true], [false, true])
  func listSelection(dark: Bool, loose: Bool) async throws {
    _ = NSApplication.shared
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 600, height: 400),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    web.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: web.frame, styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = web
    window.orderFront(nil)
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.close()
    }
    let source =
      "4. First " + String(repeating: "wrapping paragraph text ", count: 30)
      + (loose ? "\n\n" : "\n")
      + "5. Second\n\n# Next section\n\n1. [x] Completed task"
    let parsed = try await MarkdownProcessor().render(source)
    let html = parsed.html + "<ol type=\"i\"><li>Roman marker</li></ol>"
    coordinator.update(web, html: html, directory: nil, remoteImages: false)
    var ready = false
    for _ in 0..<200 {
      if try await evaluate(
        "return String(document.querySelector('ol')?.children.length===2);", in: web)
        == "true"
      {
        ready = true
        break
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    try #require(ready)
    let selected = try await evaluate(
      """
      const baselineStyle=document.createElement('style');
      baselineStyle.textContent='ol>li{list-style-type:decimal!important}ol>li::before{content:none!important}';
      document.head.append(baselineStyle);
      const items=document.querySelector('ol').children, range=document.createRange();
      const first=items[0].querySelector('p')?.firstChild ?? items[0].firstChild;
      const last=items[1].querySelector('p')?.firstChild ?? items[1].firstChild;
      range.setStart(first,0); range.setEnd(last,last.length);
      const selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      window.selectedFirst=items[0]; window.selectedLast=items[1];
      const baseline=selection.toString(); baselineStyle.remove(); return baseline;
      """, in: web)
    #expect(selected.contains("First") && selected.contains("Second"))
    try await expectListLayout(in: web)
    coordinator.update(
      web, html: html, directory: nil, remoteImages: false,
      style: .init(font: .serif, textSize: 20))
    ready = false
    for _ in 0..<200 {
      if try await evaluate("return getComputedStyle(document.body).fontSize;", in: web) == "20px" {
        ready = true
        break
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    try #require(ready)
    #expect(try await evaluate("return window.getSelection().toString();", in: web) == selected)
    #expect(
      try await evaluate(
        "return String(window.selectedFirst===document.querySelector('li') && window.selectedLast===document.querySelectorAll('li')[1]);",
        in: web) == "true")
    try await expectListLayout(in: web)
  }

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try #require(
      try await web.callAsyncJavaScript(
        "try {\n" + script
          + "\n} catch (error) { throw new Error(stage + ': ' + error.name + ': ' + error.message); }",
        arguments: ["stage": String(script.prefix(96))], in: nil, contentWorld: .defaultClient)
        as? String)
  }

  private func expectListLayout(in web: WKWebView) async throws {
    #expect(
      try await evaluate(
        """
        const list=document.querySelector('ol'), item=list.firstElementChild;
        const text=item.firstElementChild?.firstChild ?? item.firstChild;
        const range=document.createRange(); range.selectNodeContents(text);
        const lines=[...range.getClientRects()].filter(r=>r.width>1);
        const marker=getComputedStyle(item,'::before');
        const task=document.querySelector('input[type=checkbox]').closest('li');
        const typed=document.querySelector('ol[type] > li');
        const before=e=>getComputedStyle(e,'::before').content;
        return String(list.start===4 && list.children.length===2 &&
          getComputedStyle(item).display==='list-item' &&
          marker.content!=='none' && marker.content!=='normal' &&
          lines.length>2 && lines.every(r=>Math.abs(r.left-lines[0].left)<1) &&
          Math.abs(lines[0].left-item.getBoundingClientRect().left)<1 &&
          ['none','normal'].includes(before(task)) && ['none','normal'].includes(before(typed)) &&
          getComputedStyle(typed).listStyleType==='lower-roman');
        """, in: web) == "true")
  }
}
