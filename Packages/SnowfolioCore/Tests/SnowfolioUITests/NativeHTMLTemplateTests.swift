import AppKit
import ExportCore
import MarkdownCore
import RenderingCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native exported template", .serialized, NativeUIExclusive())
@MainActor
struct NativeHTMLTemplateTests {
  @Test(
    "The exported template preserves authored body selectors and HTML boundaries",
    arguments: [false, true])
  func authored(remote: Bool) async throws {
    _ = NSApplication.shared
    let css = "body > p {color:rgb(17,34,51)} p::after {content:'</style><img id=escaped src=x>'}"
    let sheet = try DocumentStylesheet(data: Data(css.utf8))
    let style = DocumentStyle(presentation: .stylesheet(sheet))
    let title = "</title><script>bad()</script> 中文"
    let export = try await MarkdownExport.build(
      source: "Portable 中文", title: title,
      directory: nil, remoteImages: remote, style: style)
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document, remoteImages: remote)
    let result = try await surface.view.callAsyncJavaScript(
      """
      const policy=document.querySelector('meta[http-equiv="Content-Security-Policy"]');
      return {title:document.title, color:getComputedStyle(document.querySelector('body > p')).color,
        root:document.body.id, main:document.querySelector('main')!==null,
        injected:document.getElementById('escaped')!==null, scripts:document.scripts.length,
        remote:policy.content.includes('img-src mdasset: data: https:')};
      """, arguments: [:], in: nil, contentWorld: .defaultClient)
    let values = try #require(result as? [String: Any])
    #expect(values["title"] as? String == title)
    #expect(values["color"] as? String == "rgb(17, 34, 51)")
    #expect(values["root"] as? String == "preview-content")
    #expect(values["main"] as? Bool == false && values["injected"] as? Bool == false)
    #expect(values["scripts"] as? Int == 0 && values["remote"] as? Bool == remote)
  }
}
