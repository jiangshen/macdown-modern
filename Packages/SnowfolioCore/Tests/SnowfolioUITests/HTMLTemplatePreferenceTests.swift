import AppKit
import DocumentCore
import ExportCore
import RenderingCore
import Testing

@testable import SnowfolioUI

@Suite("Saved HTML template migration", .serialized, NativeUIExclusive())
@MainActor
struct HTMLTemplatePreferenceTests {
  @Test("Saved names survive migration, reopen, export errors and explicit recovery")
  func recovery() async throws {
    let domain = "TemplatePreferences." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["htmlTemplateName": "Missing custom template"])
    #expect(preferences.htmlTemplateName == "Missing custom template")
    let reopened = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(reopened.htmlTemplateName == "Missing custom template")
    let document = MarkdownDocument(contents: TextFileContents(text: "# Preserved 中文"))
    let export = DocumentExportController()
    export.document = document
    export.preferences = preferences
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 600, height: 400),
      styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    defer { window.close() }
    export.window = window
    #expect(export.isAvailable)
    export.exportHTML()
    for _ in 0..<100 {
      if !export.isBusy { break }
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!export.isBusy && window.attachedSheet == nil)
    #expect(export.errorMessage?.contains("Use Default") == true)
    #expect(preferences.htmlTemplateName == "Missing custom template")
    #expect(defaults.string(forKey: "htmlTemplateName") == "Missing custom template")
    #expect(document.text == "# Preserved 中文" && document.revision == 0)
    preferences.htmlTemplateName = HTMLExportTemplate.defaultName
    let recovered = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(recovered.htmlTemplateName == "Default")
    #expect(SettingsCatalog.search("HTML template").map(\.id) == ["htmlTemplate"])
  }

  @Test("Manual preview exports capture fresh source, style and template immutably")
  func snapshot() async throws {
    let domain = "TemplateSnapshot." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(preferences.htmlTemplateName == "Default")
    preferences.manualRendering = true
    let document = MarkdownDocument(contents: TextFileContents(text: "Old preview"))
    document.replaceText(with: "# Fresh 中文", undoManager: nil)
    let export = DocumentExportController()
    export.document = document
    export.preferences = preferences
    let snapshot = try #require(export.snapshot())
    preferences.htmlTemplateName = "Later missing template"
    document.replaceText(with: "Later edit", undoManager: nil)
    let output = try await MarkdownExport.build(
      source: snapshot.source, options: snapshot.options,
      title: snapshot.title, directory: snapshot.directory, style: snapshot.style,
      templateName: snapshot.templateName)
    #expect(output.document.contains("Fresh 中文") && !output.document.contains("Old preview"))
    #expect(!output.document.contains("Later edit") && snapshot.templateName == "Default")
    #expect(document.text == "Later edit")
  }
}
