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
    arguments: [false, true], [false, true])
  func preview(dark: Bool, brackets: Bool) async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let inlineOpen = brackets ? #"\("# : "$"
    let inlineClose = brackets ? #"\)"# : "$"
    let displayOpen = brackets ? #"\["# : "$$"
    let displayClose = brackets ? #"\]"# : "$$"
    let source =
      "# Equation notebook\n\nInline " + inlineOpen + "E=\nmc^2" + inlineClose
      + " stays with the sentence.\n\n" + displayOpen
      + "\\int_0^1 x^2\\,dx=\n\\frac{1}{3}" + displayClose
      + "\n\nOffline fonts and accessible MathML."
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
    window.animationBehavior = .none
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
    try png.write(
      to: URL(
        filePath:
          "/private/tmp/snowfolio-math-\(brackets ? "brackets" : "dollars")-\(dark ? "dark" : "light").png"
      ))
  }

  @Test("Document definitions appear in offline preview and fresh HTML/PDF export")
  func documentDefinitions() async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let source =
      "# Shared equations\n\n"
      + #"$$\newcommand{\snowfield}{\mathbb{R}}\newcommand{\squared}[1]{#1^2}$$"#
      + "\n\n" + #"For every $x\in\snowfield$, read the equation below."#
      + "\n\n```math\n\\squared{x}+1\n```\n\nLast checkpoint."
    let export = try await MarkdownExport.build(
      source: source, options: options, title: "Shared equations", directory: nil)
    #expect(!export.document.contains("class=\"math-error\""))
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    #expect(
      try await evaluate(
        "return String([...document.querySelectorAll('math mi')].some(e=>e.getAttribute('mathvariant')==='double-struck' && e.textContent==='R'));",
        in: surface.view) == "true")
    #expect(
      try await evaluate(
        "return String(document.querySelectorAll('math msup').length);", in: surface.view) == "1")
    #expect(
      try await evaluate(
        "return String([...document.querySelectorAll('.katex-html')].some(e=>e.getBoundingClientRect().height>15));",
        in: surface.view) == "true")
    #expect(!surface.view.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    #expect(
      try await evaluate(
        "return String(document.querySelector('.md-math')?.getBoundingClientRect().height);",
        in: surface.view) == "0")
    let snapshot = try await surface.view.takeSnapshot(configuration: nil)
    let tiff = try #require(snapshot.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    try #require(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(filePath: "/private/tmp/snowfolio-math-document-definitions.png"))
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: path) }
    let info = NativeWebOutput.printInfo(allPages: true)
    info.paperSize = NSSize(width: 612, height: 792)
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
    let window = NSWindow(
      contentRect: surface.view.frame, styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    defer { window.close() }
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    #expect(pdf.pageCount == 1)
    let text = try #require(pdf.string)
    #expect(text.contains("Shared equations") && text.contains("Last checkpoint."))
    #expect(text.contains("x") && text.contains("1"))
    let page = try #require(pdf.page(at: 0))
    let thumbnail = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
    let pdfTIFF = try #require(thumbnail.tiffRepresentation)
    let pdfBitmap = try #require(NSBitmapImageRep(data: pdfTIFF))
    try #require(pdfBitmap.representation(using: .png, properties: [:])).write(
      to: URL(filePath: "/private/tmp/snowfolio-math-document-definitions-pdf.png"))
    try Data(contentsOf: path).write(
      to: URL(filePath: "/private/tmp/snowfolio-math-document-definitions.pdf"))
  }

  @Test(
    "Compatibility equations render offline with portable references and PDF output",
    arguments: [false, true])
  func compatibility(dark: Bool) async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.math = true
    options.inlineDollarMath = true
    let source =
      "# Compatible equations\n\n" + #"See $\eqref{answer}$."#
      + "\n\n" + #"$$\newenvironment{snowcase}[1]{\left\{#1}{\right.}$$"#
      + "\n\n```math\n" + #"\begin{snowcase}{x}y\end{snowcase}\tag{A}\label{answer}"#
      + "\n```\n\nEnd checkpoint."
    let export = try await MarkdownExport.build(
      source: source, options: options, title: "Compatible equations", directory: nil)
    #expect(!export.document.contains("class=\"math-error\""))
    #expect(export.document.contains("Apache License"))
    let surface = NativeWebOutput()
    defer { surface.close() }
    surface.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    try await surface.prepare(html: export.document)
    #expect(!surface.view.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    #expect(
      try await evaluate(
        "return String(document.querySelectorAll('.md-mathjax-visual>svg').length);",
        in: surface.view) == "2")
    #expect(
      try await evaluate(
        "return String([...document.querySelectorAll('.md-mathjax-visual>svg')].every(e=>e.getBoundingClientRect().width>10 && e.getBoundingClientRect().height>10));",
        in: surface.view) == "true")
    let definitionHeight = try await evaluate(
      "return String(document.querySelector('.md-mathjax-empty').closest('.md-math').getBoundingClientRect().height);",
      in: surface.view)
    #expect(definitionHeight == "0")
    #expect(
      try await evaluate(
        "const a=document.querySelector('.md-mathjax-visual a');return String(!!a && !!document.getElementById(a.getAttribute('href').slice(1)));",
        in: surface.view) == "true")
    #expect(
      try await evaluate("return typeof globalThis.SnowfolioMathJax;", in: surface.view)
        == "undefined")
    #expect(
      try await evaluate(
        "return String(document.querySelectorAll('math annotation[encoding=\"application/x-tex\"]').length);",
        in: surface.view) == "3")
    let image = try await surface.view.takeSnapshot(configuration: nil)
    let imageTIFF = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: imageTIFF))
    try #require(bitmap.representation(using: .png, properties: [:])).write(
      to: URL(filePath: "/private/tmp/snowfolio-math-compatibility-\(dark ? "dark" : "light").png"))
    if dark { return }
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: path) }
    let info = NativeWebOutput.printInfo(allPages: true)
    info.paperSize = NSSize(width: 612, height: 792)
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
    let window = NSWindow(
      contentRect: surface.view.frame, styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    defer { window.close() }
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    #expect(pdf.pageCount == 1)
    let text = try #require(pdf.string)
    #expect(text.contains("Compatible equations") && text.contains("End checkpoint."))
    let page = try #require(pdf.page(at: 0))
    let thumbnail = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
    let thumbnailTIFF = try #require(thumbnail.tiffRepresentation)
    let pdfBitmap = try #require(NSBitmapImageRep(data: thumbnailTIFF))
    try #require(pdfBitmap.representation(using: .png, properties: [:])).write(
      to: URL(filePath: "/private/tmp/snowfolio-math-compatibility-pdf.png"))
    try Data(contentsOf: path).write(
      to: URL(filePath: "/private/tmp/snowfolio-math-compatibility.pdf"))
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
    window.animationBehavior = .none
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
