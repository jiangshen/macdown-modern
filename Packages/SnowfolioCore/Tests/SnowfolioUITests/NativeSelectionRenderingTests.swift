import AppKit
import MarkdownCore
import RenderingCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native list selection", .serialized, NativeUIExclusive())
@MainActor
struct NativeSelectionRenderingTests {
  @Test("List selection paints evenly and survives style updates", arguments: [false, true])
  func listSelection(dark: Bool) async throws {
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
    let source = "1. First\n2. Second\n\n# Next section"
    let parsed = try await MarkdownProcessor().render(source)
    coordinator.update(web, html: parsed.html, directory: nil, remoteImages: false)
    var ready = false
    for _ in 0..<200 {
      if try await evaluate(
        "return String(document.querySelectorAll('ol > li').length===2);", in: web)
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
      const items=document.querySelectorAll('ol > li'), range=document.createRange();
      range.setStart(items[0].firstChild,0);
      range.setEnd(items[1].firstChild,items[1].firstChild.length);
      const selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      window.selectedFirst=items[0]; window.selectedLast=items[1];
      return selection.toString();
      """, in: web)
    #expect(selected.contains("First") && selected.contains("Second"))
    try await expectEvenPainting(in: web)
    coordinator.update(
      web, html: parsed.html, directory: nil, remoteImages: false,
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
    try await expectEvenPainting(in: web)
  }

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try #require(
      try await web.callAsyncJavaScript(
        "try {\n" + script
          + "\n} catch (error) { throw new Error(stage + ': ' + error.name + ': ' + error.message); }",
        arguments: ["stage": String(script.prefix(96))], in: nil, contentWorld: .defaultClient)
        as? String)
  }

  private func expectEvenPainting(in web: WKWebView) async throws {
    // A transparent system Highlight painted by both marker and text produces
    // different overlap pixels. Test the resolved WebKit color, not CSS spelling.
    #expect(
      try await evaluate(
        """
        const style=getComputedStyle(document.querySelector('li'),'::selection');
        const context=document.createElement('canvas').getContext('2d',{willReadFrequently:true});
        context.canvas.width=2; context.canvas.height=1;
        context.fillStyle=getComputedStyle(document.body).backgroundColor; context.fillRect(0,0,2,1);
        context.fillStyle=style.backgroundColor; context.fillRect(0,0,2,1); context.fillRect(1,0,1,1);
        const single=[...context.getImageData(0,0,1,1).data], overlap=[...context.getImageData(1,0,1,1).data];
        context.clearRect(0,0,2,1); context.fillRect(0,0,1,1);
        const background=[...context.getImageData(0,0,1,1).data];
        context.fillStyle=style.color; context.fillRect(0,0,1,1);
        const text=[...context.getImageData(0,0,1,1).data];
        function luminance(rgb) {const c=rgb.slice(0,3).map(n=>n/255).map(n=>n<=.04045?n/12.92:((n+.055)/1.055)**2.4);return .2126*c[0]+.7152*c[1]+.0722*c[2];}
        const a=luminance(background),b=luminance(text),contrast=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);
        return String(JSON.stringify(single)===JSON.stringify(overlap) && background[3]===255 && contrast>=4.5);
        """, in: web) == "true")
  }
}
