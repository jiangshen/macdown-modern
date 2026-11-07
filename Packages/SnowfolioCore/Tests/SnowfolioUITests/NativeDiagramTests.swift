import AppKit
import ExportCore
import MarkdownCore
import PDFKit
import Testing
import WebKit

@testable import DiagramCore
@testable import SnowfolioUI

@Suite("Native offline diagrams", .serialized, NativeUIExclusive())
@MainActor
struct NativeDiagramTests {
  @Test("Maintained engines produce both appearance variants", arguments: DiagramKind.allCases)
  func engines(kind: DiagramKind) async throws {
    let renderer = DiagramRenderer()
    defer { renderer.close() }
    let source =
      kind == .mermaid
      ? "graph LR; A[Snowfolio 中文]-->B[Markdown]"
      : "digraph {a [label=\"Snowfolio 中文\"]; a -> b [label=\"Markdown\"]}"
    let result = try await renderer.render(source, kind: kind)
    _ = try #require(result.lightSVG, "\(kind.rawValue): \(String(describing: result.issue))")
    #expect(
      result.lightSVG?.contains("Snowfolio") == true && result.lightSVG?.contains("中文") == true)
    #expect(result.darkSVG?.contains("Snowfolio") == true && result.darkSVG?.contains("中文") == true)
    #expect(result.lightSVG?.contains("id=\"light-") == true)
    #expect(result.darkSVG?.contains("id=\"dark-") == true)
    #expect(result.lightSVG != result.darkSVG)
    let cached = try await renderer.render(source, kind: kind)
    #expect(cached.lightSVG == result.lightSVG)
    #expect(!renderer.hasPendingWork)
  }

  @Test("Invalid source, oversized requests, cancellation and timeouts retain a usable worker")
  func lifecycle() async throws {
    let renderer = DiagramRenderer()
    defer { renderer.close() }
    #expect(
      try await renderer.render(String(repeating: "x", count: 65_537), kind: .dot).issue
        == .tooLarge)
    #expect(!renderer.hasWorker)
    #expect(try await renderer.render("digraph { invalid ->", kind: .dot).issue != nil)
    #expect(try await renderer.render("digraph {a->b}", kind: .dot).isRendered)
    let unsafe = try await renderer.render(
      #"digraph { a [URL="javascript:alert(1)"] }"#, kind: .dot)
    #expect(unsafe.isRendered)
    #expect(unsafe.lightSVG?.contains("javascript:") == false)
    #expect(unsafe.darkSVG?.contains("javascript:") == false)
    let separate = DiagramRenderer()
    defer { separate.close() }
    let pending = Task { try await separate.render("graph LR; A-->B", kind: .mermaid) }
    for _ in 0..<1000 {
      if separate.hasPendingWork { break }
      await Task.yield()
    }
    #expect(separate.hasPendingWork)
    let queued = Task { try await separate.render("digraph {queued->complete}", kind: .dot) }
    await Task.yield()
    pending.cancel()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(try await queued.value.isRendered)
    #expect(!separate.hasPendingWork)
    #expect(try await separate.render("graph LR; A-->C", kind: .mermaid).isRendered)
    let expires = DiagramRenderer(timeout: .milliseconds(1))
    defer { expires.close() }
    #expect(try await expires.render("digraph {a->b}", kind: .dot).issue == .timedOut)
    #expect(!expires.hasPendingWork)
  }
}

extension NativeDiagramTests {
  private static let notebook = """
    # Diagram notebook

    ```mermaid
    flowchart LR
      A[Draft] --> B[Publish]
    ```

    ```dot
    digraph { rankdir=LR; a[label="Source"]; b[label="Preview"]; a->b }
    ```

    End checkpoint.
    """

  private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
    try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
      as? String ?? ""
  }

  private func waitFor(_ predicate: () async throws -> Bool) async throws {
    for _ in 0..<200 {
      if try await predicate() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw CocoaError(.coderReadCorrupt)
  }

  @Test(
    "Mermaid sequence, timeline and math labels render offline",
    arguments: [
      "sequenceDiagram\nAlice->>Bob: Hello\nBob-->>Alice: Welcome",
      "gantt\n title Writing schedule\n dateFormat YYYY-MM-DD\n section Draft\n Write :a1, 2026-11-01, 3d",
      "flowchart LR\n A[\"$$x^2$$\"] --> B[\"$$\\frac{1}{2}$$\"]",
    ])
  func mermaidTypes(_ source: String) async throws {
    let renderer = DiagramRenderer()
    defer { renderer.close() }
    let result = try await renderer.render(source, kind: .mermaid)
    #expect(result.isRendered, "\(String(describing: result.issue))")
    if source.contains("$$") { #expect(result.usesMath) }
  }

  @Test("Optional diagrams retain source positions, syntax, fallback code and independent switches")
  func markdown() async throws {
    let source = "中文 😀\r\n\r\n" + Self.notebook.replacingOccurrences(of: "\n", with: "\r\n")
    let processor = MarkdownProcessor()
    let disabled = try await processor.render(source)
    #expect(disabled.diagrams == 0)
    #expect(disabled.html.contains("language-mermaid"))
    var options = MarkdownRenderingOptions()
    options.mermaid = true
    let mermaid = try await processor.render(source, options: options, includeSyntax: true)
    #expect(mermaid.diagrams == 1)
    #expect(mermaid.html.contains("language-dot"))
    #expect(mermaid.nodes.contains { $0.kind == .diagram(.mermaid) && $0.range?.start.line == 5 })
    #expect(mermaid.syntax?.runs.contains { $0.style.role == .code } == true)
    options.graphviz = true
    let both = try await processor.render(source, options: options)
    #expect(both.diagrams == 2 && both.notices.isEmpty)
    #expect(
      both.headings.first?.utf16Offset == (source as NSString).range(of: "# Diagram").location)
    let fallback = try await processor.render("```dot\ndigraph { broken ->\n```", options: options)
    #expect(fallback.diagrams == 0)
    #expect(fallback.notices == [.unsupportedDiagram])
    #expect(fallback.html.contains("broken"))
    #expect(fallback.highlightedCodeBlocks == 1)
  }

  @Test(
    "Preview hydrates repeated diagrams, preserves their identity and adapts appearance",
    arguments: [false, true])
  func preview(dark: Bool) async throws {
    var options = MarkdownRenderingOptions()
    options.mermaid = true
    options.graphviz = true
    let source = Self.notebook + "\n\n```mermaid\nflowchart LR\n  A[Draft] --> B[Publish]\n```"
    let result = try await MarkdownProcessor().render(
      source, options: options, diagramPresentation: .isolated)
    #expect(result.diagrams == 3)
    let coordinator = NativeMarkdownPreview.Coordinator()
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 900, height: 900),
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
    coordinator.update(web, html: result.html, directory: nil, remoteImages: false)
    try await waitFor {
      (try? await evaluate(
        "return String([...document.querySelectorAll('.md-diagram')].filter(e=>e.shadowRoot?.querySelector('svg')).length);",
        in: web)) == "3"
    }
    let expected = dark ? "diagram-dark" : "diagram-light"
    #expect(
      try await evaluate(
        """
        const roots=[...document.querySelectorAll('.md-diagram')].map(e=>e.shadowRoot);
        return String(roots.every(root=>{
          const shown=root.querySelector('.\(expected) svg');
          const ids=[...root.querySelectorAll('[id]')].map(e=>e.id);
          return shown.getBoundingClientRect().width>20 && shown.getBoundingClientRect().height>10 && new Set(ids).size===ids.length;
        }));
        """, in: web) == "true")
    #expect(!web.configuration.defaultWebpagePreferences.allowsContentJavaScript)
    #expect(try await evaluate("return typeof globalThis.mermaid;", in: web) == "undefined")
    _ = try await evaluate(
      "globalThis.keptDiagram=document.querySelector('.md-diagram').shadowRoot.querySelector('svg'); return 'saved';",
      in: web)
    coordinator.update(
      web, html: result.html + "<p>After patch</p>", directory: nil, remoteImages: false)
    try await waitFor {
      try await evaluate(
        "return String(document.querySelector('p:last-child')?.textContent==='After patch');",
        in: web) == "true"
    }
    #expect(
      try await evaluate(
        "return String(globalThis.keptDiagram===document.querySelector('.md-diagram').shadowRoot.querySelector('svg'));",
        in: web) == "true")
    let image = try await web.takeSnapshot(configuration: nil)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))
    try png.write(
      to: URL(filePath: "/private/tmp/snowfolio-diagrams-\(dark ? "dark" : "light").png"))
  }

  @Test("Portable HTML and pasted fragments isolate repeated SVGs without runtime engines")
  func portable() async throws {
    var options = MarkdownRenderingOptions()
    options.mermaid = true
    options.graphviz = true
    let source = Self.notebook + "\n\n" + Self.notebook
    let export = try await MarkdownExport.build(
      source: source, options: options, title: "Diagrams", directory: nil)
    #expect(!export.document.contains("<script"))
    #expect(!export.document.contains("<template"))
    #expect(!export.document.contains("shadowrootmode"))
    let surface = NativeWebOutput()
    surface.view.appearance = NSAppearance(named: .aqua)
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    #expect(
      try await evaluate(
        """
        const ids=[...document.querySelectorAll('[id]')].map(e=>e.id);
        return String(document.querySelectorAll('div.md-diagram').length===4 && new Set(ids).size===ids.length
          && [...document.querySelectorAll('.diagram-light svg')].every(e=>e.getBoundingClientRect().height>10));
        """, in: surface.view) == "true")
    let pasted = try await surface.view.callAsyncJavaScript(
      """
      document.body.innerHTML='<p id="sentinel">Other document</p><div id="paste"></div>';
      document.getElementById('paste').innerHTML=fragment;
      return String(document.querySelectorAll('#paste .diagram-light svg').length===4
        && [...document.querySelectorAll('#paste .diagram-light svg')].every(e=>e.getBoundingClientRect().width>20)
        && getComputedStyle(document.getElementById('sentinel')).fill==='rgb(0, 0, 0)');
      """, arguments: ["fragment": export.fragment], in: nil, contentWorld: .defaultClient)
    #expect(pasted as? String == "true")
    // A math fragment must carry fonts/CSS even when pasted without an HTML head.
    options.math = true
    let math = try await MarkdownExport.build(
      source: "```math\n\\frac{1}{2}\n```", options: options, title: "Math", directory: nil)
    let mathPasted = try await surface.view.callAsyncJavaScript(
      """
      document.body.innerHTML=fragment; await document.fonts.ready;
      const m=document.querySelector('.katex-mathml');
      return String(m && getComputedStyle(m).position==='absolute' && document.querySelector('.katex-html').getBoundingClientRect().height>5);
      """, arguments: ["fragment": math.fragment], in: nil, contentWorld: .defaultClient)
    #expect(mathPasted as? String == "true")
  }

  @Test("Native PDF preserves both diagram labels and the surrounding document")
  func pdf() async throws {
    var options = MarkdownRenderingOptions()
    options.mermaid = true
    options.graphviz = true
    let export = try await MarkdownExport.build(
      source: Self.notebook, options: options, title: "Diagrams", directory: nil)
    let surface = NativeWebOutput()
    surface.view.appearance = NSAppearance(named: .aqua)
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
    for label in ["Diagram notebook", "Draft", "Publish", "Source", "Preview", "End checkpoint."] {
      #expect(text.contains(label), "Missing PDF text: \(label)")
    }
    try Data(contentsOf: path).write(
      to: URL(filePath: "/private/tmp/snowfolio-diagrams-export.pdf"))
  }
}
