import AppKit
import DocumentCore
import ExportCore
import Foundation
import MarkdownCore
import PDFKit
import RenderingCore
import Testing

@testable import SnowfolioUI

@Suite("Native paginated output", .serialized, NativeUIExclusive())
@MainActor
struct NativeWebOutputTests {
  @Test("Selected reading styles flow through native PDF and print preparation")
  func readingStylesPDF() async throws {
    _ = NSApplication.shared
    let repository = ReadingStyleRepository()
    for entry in ReadingStyleEntry.all {
      let style = DocumentStyle(presentation: try await repository.load(entry.id))
      let export = try await MarkdownExport.build(
        source: "# Reading style checkpoint\n\nPreserved document text.", title: entry.title,
        directory: nil, style: style)
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
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 900), styleMask: .titled,
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      #expect(await surface.printDocument(info: info, for: window, showPanel: false))
      let pdf = try #require(PDFDocument(url: path))
      let text = try #require(pdf.string)
      let heading =
        entry.title.hasPrefix("Solarized") ? "READING STYLE CHECKPOINT" : "Reading style checkpoint"
      #expect(
        text.contains(heading) && text.contains("Preserved document text."),
        "\(entry.title): \(text.debugDescription)")
      #expect(pdf.pageCount == 1)
    }
  }

  @Test("Native PDF and print use the current fence parsing choice", arguments: [false, true])
  func fencePreferencePDF(enabled: Bool) async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.fencedCode = enabled
    options.codeHighlighting = false
    let export = try await MarkdownExport.build(
      source: "~~~text\n**PDF fence checkpoint**\n~~~\n\n    indented checkpoint",
      options: options, title: "Fence preference", directory: nil)
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
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    let text = try #require(pdf.string)
    #expect(text.contains("~~~text") == !enabled)
    #expect(text.contains("**PDF fence checkpoint**") == enabled)
    #expect(text.contains("PDF fence checkpoint") && text.contains("indented checkpoint"))
    #expect(pdf.pageCount == 1)
  }

  @Test(
    "Native PDF and print use the selected word-formatting policy",
    arguments: MarkdownEmphasisPolicy.allCases)
  func intrawordPreferencePDF(policy: MarkdownEmphasisPolicy) async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.emphasisPolicy = policy
    let export = try await MarkdownExport.build(
      source: "a_b_c and a*b*c", options: options, title: "Word formatting", directory: nil)
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
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
      styleMask: .titled, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    let text = try #require(pdf.string)
    switch policy {
    case .standard:
      #expect(text.contains("and abc"))
      #expect(text.filter { $0 == "_" }.count == 2)
    case .allowWithinWords: #expect(text.contains("abc and abc"))
    case .avoidWithinWords:
      #expect(text.contains("and a*b*c"))
      #expect(text.filter { $0 == "_" }.count == 2)
    }
    // PDFKit can extract baseline underscores after the surrounding text.
    #expect(text.filter { $0.isLetter } == "abcandabc")
    #expect(pdf.pageCount == 1)
  }

  @Test("Native PDF output paginates the full document, including text past the screen bounds")
  func paginatedPDF() async throws {
    _ = NSApplication.shared
    let markdown =
      "---\ntitle: Metadata checkpoint\nstatus: Ready\n---\n\n[TOC]\n\n# First page\n\n"
      + (0..<150).map { "Paragraph \($0): portable Markdown export.\n\n" }.joined()
      + "## Final checkpoint\n\n日本語 中文 👩‍💻\n\n> [!WARNING]\n> Notebook callout checkpoint.\n\n```swift\nlet lastCodeValue = 42\n```\n"
    let export = try await MarkdownExport.build(
      source: markdown, title: "Pagination fixture", directory: nil)
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: path) }
    let info = NativeWebOutput.printInfo(allPages: true)
    #expect(info.dictionary()[NSPrintInfo.AttributeKey.allPages] as? Bool == true)
    info.paperSize = NSSize(width: 612, height: 792)
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 720, height: 900),
      styleMask: .titled, backing: .buffered, defer: false)
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    #expect(pdf.pageCount >= 3)
    #expect(pdf.pageCount < 20)
    let contents = try #require(pdf.string)
    #expect(contents.contains("Metadata checkpoint"))
    #expect(contents.contains("First page"))
    #expect(contents.contains("Paragraph 149"))
    #expect(contents.contains("Final checkpoint"))
    #expect(contents.contains("Warning"))
    #expect(contents.contains("Notebook callout checkpoint."))
    #expect(contents.contains("lastCodeValue"))
    // PDFKit may extract CJK glyphs as their compatible Kangxi radical forms.
    let normalized = contents.precomposedStringWithCompatibilityMapping
    #expect(normalized.contains("日本語"))
    #expect(normalized.contains("中文"))
  }

  @Test("Print preparation decodes embedded vector images and rejects broken raster images")
  func imageReadiness() async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let svg =
      "<svg xmlns='http://www.w3.org/2000/svg' width='20' height='20'><rect width='20' height='20' fill='blue'/></svg>"
    try Data(svg.utf8).write(to: directory.appendingPathComponent("ice.svg"))
    let export = try await MarkdownExport.build(
      source: "![Ice](ice.svg)", title: "Image", directory: directory)
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    let broken = NativeWebOutput()
    defer { broken.close() }
    let invalid = try await MarkdownExport.build(
      source: "![Bad](data:image/png;base64,aW52YWxpZA==)", title: "Bad image", directory: nil)
    await #expect(throws: DocumentOutputError.self) {
      try await broken.prepare(html: invalid.document)
    }
  }

  @Test("Export snapshots use current text and settings even when preview rendering is manual")
  func freshSnapshot() async throws {
    let domain = "ExportSnapshotTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.manualRendering = true
    preferences.tables = false
    preferences.fencedCode = false
    preferences.underline = true
    preferences.quotedText = true
    preferences.emphasisPolicy = .allowWithinWords
    preferences.documentFont = .serif
    preferences.documentTextSize = 20
    let document = MarkdownDocument(contents: TextFileContents(text: "Old text"))
    let output = DocumentExportController()
    output.document = document
    output.preferences = preferences
    document.acceptNativeEdit("Newest _text 中文_ and \"quotation\"")
    let snapshot = try #require(output.snapshot())
    #expect(snapshot.source == "Newest _text 中文_ and \"quotation\"")
    #expect(!snapshot.options.tables)
    #expect(!snapshot.options.fencedCode)
    #expect(snapshot.options.underline && snapshot.options.quotedText)
    #expect(snapshot.style.font == .serif)
    #expect(snapshot.style.textSize == 20)
    #expect(snapshot.options.emphasisPolicy == .allowWithinWords)
    preferences.documentTextSize = 12
    preferences.underline = false
    preferences.quotedText = false
    preferences.emphasisPolicy = .avoidWithinWords
    #expect(snapshot.options.underline && snapshot.options.quotedText)
    #expect(snapshot.style.textSize == 20)
    #expect(snapshot.options.emphasisPolicy == .allowWithinWords)
    document.acceptNativeEdit("Later text")
    #expect(snapshot.source == "Newest _text 中文_ and \"quotation\"")
    let export = try await MarkdownExport.build(
      source: snapshot.source, options: snapshot.options, title: snapshot.title,
      directory: snapshot.directory, style: snapshot.style)
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    #expect(export.fragment.contains("<u>text 中文</u>"))
    #expect(export.fragment.contains("<q>quotation</q>"))
    let typography: String = try await withCheckedThrowingContinuation { continuation in
      surface.view.callAsyncJavaScript(
        "const style = getComputedStyle(document.body); return style.fontSize + ':' + style.fontFamily;",
        arguments: [:], in: nil, in: .defaultClient
      ) { result in
        switch result {
        case .success(let value): continuation.resume(returning: value as? String ?? "")
        case .failure(let error): continuation.resume(throwing: error)
        }
      }
    }
    #expect(typography.hasPrefix("20px:"))
    #expect(typography.contains("ui-serif"))
  }
}
