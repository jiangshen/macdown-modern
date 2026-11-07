import AppKit
import DocumentCore
import ExportCore
import MarkdownCore
import PDFKit
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native optional inline formatting", .serialized, NativeUIExclusive())
@MainActor
struct NativeInlineFormattingTests {
  private static let source =
    "# Inline notebook\n\n==Review **important** text== and x^(2 + 1). _Underline checkpoint_. \"Quotation checkpoint\".\n\nEnd checkpoint."
  private var options: MarkdownRenderingOptions {
    var options = MarkdownRenderingOptions()
    options.highlight = true
    options.superscript = true
    options.underline = true
    options.quotedText = true
    return options
  }

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
      as? String ?? ""
  }

  @Test("Source highlight is temporary and the original command uses one native undo step")
  func editor() async throws {
    let source = "_Underlined_ ==中文 **important**== and x^2"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let commands = EditorCommandController()
    coordinator.commands = commands
    commands.coordinator = coordinator
    let undo = UndoManager()
    undo.groupsByEvent = false
    coordinator.undoManager = undo
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    editor.commandController = commands
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
      styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = scroll
    window.orderFront(nil)
    window.makeFirstResponder(editor)
    defer { window.close() }
    let selection = (source as NSString).range(of: "中文 **important**")
    editor.setSelectedRange(selection)
    let parsed = try await MarkdownProcessor().render(source, options: options, includeSyntax: true)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: document.revision, enabled: true,
      font: try #require(editor.font), document: document)
    let layout = try #require(editor.textLayoutManager)
    let content = try #require(layout.textContentManager)
    layout.ensureLayout(for: content.documentRange)
    editor.displayIfNeeded()
    let offset = (source as NSString).range(of: "important").location
    var background: NSColor?
    var underlineColor: NSColor?
    let underlineOffset = (source as NSString).range(of: "Underlined").location
    layout.enumerateRenderingAttributes(from: content.documentRange.location, reverse: false) {
      _, attributes, range in
      let start = content.offset(from: content.documentRange.location, to: range.location)
      let end = content.offset(from: content.documentRange.location, to: range.endLocation)
      if start <= underlineOffset, end > underlineOffset {
        underlineColor = attributes[.foregroundColor] as? NSColor
      }
      if start <= offset, end > offset {
        background = attributes[.backgroundColor] as? NSColor
      }
      return true
    }
    #expect(background == NSColor.systemYellow.withAlphaComponent(0.18))
    #expect(underlineColor == NSColor.systemTeal)
    #expect(editor.textStorage?.attribute(.backgroundColor, at: offset, effectiveRange: nil) == nil)
    #expect(document.text == source && document.revision == 0 && !undo.canUndo)
    #expect(commands.canPerform)
    commands.perform(.highlight)
    #expect(document.text == source)
    commands.setHighlightEnabled(true)
    commands.perform(.highlight)
    #expect(document.text == "_Underlined_ 中文 **important** and x^2")
    #expect(undo.undoActionName == "Highlight")
    undo.undo()
    #expect(document.text == source)
    #expect(editor.selectedRange() == selection)
    #expect(!undo.canUndo)
    undo.redo()
    #expect(document.text == "_Underlined_ 中文 **important** and x^2")
  }

  @Test(
    "Preview uses legible highlights, raised superscripts and underlines", arguments: [false, true])
  func preview(dark: Bool) async throws {
    let parsed = try await MarkdownProcessor().render(Self.source, options: options)
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 500),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    web.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
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
      window.close()
    }
    coordinator.update(web, html: parsed.html, directory: nil, remoteImages: false)
    var ready = false
    for _ in 0..<200 {
      if (try? await evaluate(
        "return String(document.querySelector('mark strong')?.textContent==='important');", in: web))
        == "true"
      {
        ready = true
        break
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    try #require(ready)
    let contrast = try await evaluate(
      """
      const e=document.querySelector('mark'), style=getComputedStyle(e);
      function luminance(rgb){const c=rgb.match(/[0-9.]+/g).slice(0,3).map(Number).map(n=>n/255).map(n=>n<=.04045?n/12.92:((n+.055)/1.055)**2.4);return .2126*c[0]+.7152*c[1]+.0722*c[2];}
      const a=luminance(style.color), b=luminance(style.backgroundColor);
      return String((Math.max(a,b)+.05)/(Math.min(a,b)+.05));
      """, in: web)
    #expect(try #require(Double(contrast)) >= 4.5)
    #expect(
      try await evaluate(
        """
        const e=document.querySelector('sup'), s=getComputedStyle(e);
        return String(e.textContent==='2 + 1' && parseFloat(s.fontSize)<parseFloat(getComputedStyle(e.parentElement).fontSize) && s.verticalAlign==='super');
        """, in: web) == "true")
    #expect(
      try await evaluate(
        """
        const e=document.querySelector('u');
        return String(e?.textContent==='Underline checkpoint' && getComputedStyle(e).textDecorationLine.includes('underline'));
        """, in: web) == "true")
    #expect(
      try await evaluate(
        "return String(document.querySelector('q')?.textContent==='Quotation checkpoint');",
        in: web) == "true")
    #expect(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    let image = try await web.takeSnapshot(configuration: nil)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(to: URL(filePath: "/private/tmp/snowfolio-inline-\(dark ? "dark" : "light").png"))
  }

  @Test("Fresh HTML and native PDF carry all optional inline formats")
  func exports() async throws {
    let export = try await MarkdownExport.build(
      source: Self.source, options: options,
      title: "Inline notebook", directory: nil)
    #expect(export.fragment.contains("<mark>Review <strong>important</strong> text</mark>"))
    #expect(export.fragment.contains("<sup>2 + 1</sup>"))
    #expect(export.fragment.contains("<u>Underline checkpoint</u>"))
    #expect(export.fragment.contains("<q>Quotation checkpoint</q>"))
    #expect(!export.document.contains("<script"))
    let plain = try await MarkdownExport.build(
      source: Self.source, options: options,
      title: "Inline notebook", directory: nil, includeStyles: false)
    #expect(
      plain.document.contains("<mark>") && plain.document.contains("<sup>")
        && plain.document.contains("<u>") && plain.document.contains("<q>"))
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
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
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    let text = try #require(pdf.string)
    #expect(pdf.pageCount == 1)
    for label in [
      "Inline notebook", "Review", "important", "2 + 1", "Underline checkpoint",
      "Quotation checkpoint", "End checkpoint.",
    ] {
      #expect(text.contains(label), "Missing PDF label: \(label)")
    }
    try Data(contentsOf: path).write(to: URL(filePath: "/private/tmp/snowfolio-inline-export.pdf"))
  }
}
