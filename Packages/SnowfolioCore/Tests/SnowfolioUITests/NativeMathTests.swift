import AppKit
import ExportCore
import MarkdownCore
import PDFKit
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native offline math", .serialized, NativeUIExclusive())
@MainActor
struct NativeMathTests {
  enum TestError: Error { case timeout }

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
      as? String ?? ""
  }

  private func waitFor(_ predicate: () async throws -> Bool) async throws {
    for _ in 0..<200 {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw TestError.timeout
  }

  @Test(
    "Preview loads embedded math fonts and patches equation nodes in both appearances",
    arguments: [false, true])
  func preview(dark: Bool) async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let source =
      "# Equation notebook\n\nInline $E=mc^2$ stays with the sentence.\n\n$$\n\\int_0^1 x^2\\,dx=\\frac{1}{3}\n$$\n\nOffline fonts and accessible MathML."
    let result = try await MarkdownProcessor().render(source, options: options)
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 600),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    web.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: web.frame, styleMask: .titled,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = web
    window.orderFront(nil)
    defer {
      web.stopLoading()
      web.navigationDelegate = nil
      window.close()
    }
    coordinator.update(web, html: result.html, directory: nil, remoteImages: false)
    try await waitFor {
      (try? await evaluate("return String(document.querySelectorAll('.katex').length);", in: web))
        == "2"
    }
    #expect(
      try await evaluate(
        "await document.fonts.ready; return String([...document.fonts].some(f=>f.status==='loaded'));",
        in: web) == "true")
    #expect(
      try await evaluate(
        "const e=document.querySelector('.katex-html'); return String(e.getBoundingClientRect().width>20 && e.getBoundingClientRect().height>5);",
        in: web) == "true")
    #expect(
      try await evaluate(
        "return String(document.querySelectorAll('math annotation[encoding=\"application/x-tex\"]').length);",
        in: web) == "2")
    #expect(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    #expect(try await evaluate("return typeof globalThis.katex;", in: web) == "undefined")
    _ = try await evaluate(
      "globalThis.equation=document.querySelector('.md-math'); return 'saved';", in: web)
    coordinator.update(
      web, html: result.html + "<p>New paragraph</p>", directory: nil, remoteImages: false)
    try await waitFor {
      try await evaluate(
        "return String(document.querySelector('p:last-child')?.textContent==='New paragraph');",
        in: web) == "true"
    }
    #expect(
      try await evaluate(
        "return String(globalThis.equation===document.querySelector('.md-math'));", in: web)
        == "true")
    let image = try await web.takeSnapshot(configuration: nil)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(filePath: "/private/tmp/snowfolio-math-\(dark ? "dark" : "light").png"))
  }

  @Test("Native print/PDF waits for local math fonts and retains the surrounding document")
  func pdf() async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.math = true
    let export = try await MarkdownExport.build(
      source: "# Equation checkpoint\n\n```math\n\\sum_{n=1}^3 n=6\n```\n\nEnd checkpoint.",
      options: options, title: "Equations", directory: nil)
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    #expect(
      try await evaluate(
        "return String([...document.fonts].some(f=>f.status==='loaded'));", in: surface.view)
        == "true")
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: path) }
    let info = NativeWebOutput.printInfo(allPages: true)
    info.paperSize = NSSize(width: 612, height: 792)
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
    let window = NSWindow(
      contentRect: surface.view.frame, styleMask: .titled,
      backing: .buffered, defer: false)
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    #expect(pdf.pageCount == 1)
    let text = try #require(pdf.string)
    #expect(text.contains("Equation checkpoint"))
    #expect(text.contains("End checkpoint."))
    #expect(text.contains("6"))
    try Data(contentsOf: path).write(to: URL(filePath: "/private/tmp/snowfolio-math-export.pdf"))
  }
}
