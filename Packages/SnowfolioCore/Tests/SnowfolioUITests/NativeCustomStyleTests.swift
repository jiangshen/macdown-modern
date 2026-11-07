import AppKit
import ExportCore
import Foundation
import MathCore
import PDFKit
import RenderingCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native frozen CSS assets", .serialized, NativeUIExclusive())
@MainActor
struct NativeCustomStyleTests {
  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try #require(
      try await web.callAsyncJavaScript(
        script, arguments: [:], in: nil, contentWorld: .defaultClient) as? String)
  }

  @Test(
    "Nested imports, images and real WOFF2 fonts render without the original folder and survive fresh export/print"
  )
  func portableAssets() async throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(
      at: root.appending(path: "Original/parts"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appending(path: "Original")
    let image = try #require(
      Data(
        base64Encoded:
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lCEAAAAASUVORK5CYII="
      ))
    try image.write(to: original.appending(path: "ice.png"))
    let fonts = MathStyle.css
    let fontStart = try #require(fonts.range(of: "data:font/woff2;base64,"))
    let fontEnd = try #require(fonts[fontStart.upperBound...].firstIndex(of: ")"))
    let font = try #require(Data(base64Encoded: String(fonts[fontStart.upperBound..<fontEnd])))
    try font.write(to: original.appending(path: "ice.woff2"))
    try Data(
      """
      @font-face{font-family:'Glacier Asset Check';src:url('../ice.woff2') format('woff2');}
      body > p {color:rgb(17,34,51);background-image:url('../ice.png');}
      @media print {h1{text-transform:uppercase;}}
      """.utf8
    ).write(to: original.appending(path: "parts/base.css"))
    try Data(
      "@import 'parts/base.css' layer(ice); body{background:rgb(240,248,255);font-family:Helvetica;}"
        .utf8
    ).write(to: original.appending(path: "Arctic.css"))
    let repository = ReadingStyleRepository(directory: root.appending(path: "Saved"))
    let grant = try await repository.prepareFolder(original)
    let candidate = try await repository.inspect(grant, main: "Arctic.css")
    let saved = try await repository.store(candidate)
    let style = DocumentStyle(presentation: try await repository.load(saved.id))
    let export = try await MarkdownExport.build(
      source: "# Frozen custom style\n\nPortable document text.", title: "Frozen custom style",
      directory: nil, style: style)
    #expect(export.document.contains("data:text/css;base64,"))
    try FileManager.default.removeItem(at: original)
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 700, height: 450),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    web.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: web.frame, styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = web
    window.orderFront(nil)
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.close()
    }
    coordinator.update(
      web, html: "<h1>Frozen custom style</h1><p>Portable document text.</p>", directory: nil,
      remoteImages: false, style: style)
    var ready = false
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
      if try await evaluate(
        "return document.querySelector('p') ? getComputedStyle(document.querySelector('p')).color : '';",
        in: web) == "rgb(17, 34, 51)"
      {
        ready = true
        break
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    try #require(ready)
    #expect(
      try await evaluate(
        """
        await document.fonts.load('16px "Glacier Asset Check"');
        const image=new Image();
        image.src=getComputedStyle(document.querySelector('p')).backgroundImage.slice(5,-2);
        await image.decode();
        return String(image.naturalWidth===1 && [...document.fonts].some(f=>f.family.includes('Glacier Asset Check') && f.status==='loaded'));
        """, in: web) == "true")
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    let path = root.appending(path: "Portable.pdf")
    let info = NativeWebOutput.printInfo(allPages: true)
    info.paperSize = NSSize(width: 612, height: 792)
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    let text = try #require(pdf.string)
    #expect(text.contains("FROZEN CUSTOM STYLE") && text.contains("Portable document text."))
    #expect(pdf.pageCount == 1)
    let plain = try await MarkdownExport.build(
      source: "# Plain", title: "Plain", directory: nil, includeStyles: false, style: style)
    #expect(!plain.document.contains("data:text/css;base64,"))
  }
}
