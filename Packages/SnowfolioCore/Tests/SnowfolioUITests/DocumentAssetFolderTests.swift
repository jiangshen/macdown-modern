import AppKit
import DocumentCore
import ExportCore
import Foundation
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Unsaved document asset folders", .serialized, NativeUIExclusive())
@MainActor
struct DocumentAssetFolderTests {
  private let image = Data(
    base64Encoded:
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII="
  )!

  private func isolatedDefaults() throws -> (UserDefaults, String) {
    let domain = "DocumentAssetFolderTests." + UUID().uuidString
    return (try #require(UserDefaults(suiteName: domain)), domain)
  }

  private func directory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @Test("Original URLForKey choice migrates as a suggestion, never an automatic Home grant")
  func migration() async throws {
    let (defaults, domain) = try isolatedDefaults()
    let (legacy, legacyDomain) = try isolatedDefaults()
    defer {
      defaults.removePersistentDomain(forName: domain)
      legacy.removePersistentDomain(forName: legacyDomain)
    }
    let old = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    legacy.set(old, forKey: "htmlDefaultDirectoryUrl")
    let values = try #require(legacy.persistentDomain(forName: legacyDomain))
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: values)
    await preferences.assetFolder.loadIfNeeded()
    #expect(preferences.assetFolder.suggestedDirectory == old)
    #expect(
      preferences.assetFolder.access == nil
        && preferences.assetFolder.location(for: nil).directory == nil)
    #expect(legacy.url(forKey: "htmlDefaultDirectoryUrl") == old)
    preferences.assetFolder.clear()
    let reopened = AppPreferences(defaults: defaults, domainName: domain, legacyValues: values)
    #expect(reopened.assetFolder.suggestedDirectory == nil && reopened.assetFolder.access == nil)
    #expect(defaults.url(forKey: "htmlDefaultDirectoryUrl") == old)
    #expect(SettingsCatalog.search("unsaved assets").map(\.id) == ["unsavedAssetFolder"])
    #expect(SettingsCatalog.search("default directory").map(\.id) == ["unsavedAssetFolder"])
  }

  @Test(
    "Read-only bookmark restores; rejected selections and damaged grants never fall back to Home")
  func persistenceAndRecovery() async throws {
    let (defaults, domain) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "ice.png")
    try image.write(to: file)
    let folder = DocumentAssetFolder(defaults: defaults)
    try await folder.choose(root)
    let bookmark = try #require(defaults.data(forKey: DocumentAssetFolder.bookmarkKey))
    for invalid in [
      URL(string: "https://example.invalid/")!, file, root.appending(path: "missing"),
    ] {
      do {
        try await folder.choose(invalid)
        Issue.record("Invalid folder accepted")
      } catch {}
      #expect(folder.access?.directory.standardizedFileURL == root.standardizedFileURL)
      #expect(defaults.data(forKey: DocumentAssetFolder.bookmarkKey) == bookmark)
      #expect(folder.message != nil && !folder.isLoading)
    }
    let restored = DocumentAssetFolder(defaults: defaults)
    #expect(!restored.isReady && restored.access == nil)
    await restored.loadIfNeeded()
    #expect(restored.isReady && restored.message == nil)
    #expect(restored.access?.directory.standardizedFileURL == root.standardizedFileURL)
    #expect(try Data(contentsOf: restored.access!.directory.appending(path: "ice.png")) == image)
    restored.clear()
    let cleared = DocumentAssetFolder(defaults: defaults)
    await cleared.loadIfNeeded()
    #expect(cleared.access == nil && cleared.displayPath == nil)
    defaults.set(Data([0, 1, 2]), forKey: DocumentAssetFolder.bookmarkKey)
    let damaged = DocumentAssetFolder(defaults: defaults)
    await damaged.loadIfNeeded()
    #expect(damaged.access == nil && damaged.isReady && damaged.message != nil)
    #expect(defaults.data(forKey: DocumentAssetFolder.bookmarkKey) == Data([0, 1, 2]))
    damaged.clear()
    #expect(damaged.message == nil && damaged.access == nil)
  }

  @Test("Unavailable remembered folders fail only exports that need their relative images")
  func unavailableExport() async throws {
    let (defaults, domain) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(Data([0, 1, 2]), forKey: DocumentAssetFolder.bookmarkKey)
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let document = MarkdownDocument(contents: TextFileContents(text: "![Ice](ice.png)"))
    let controller = DocumentExportController()
    controller.document = document
    controller.preferences = preferences
    #expect(controller.snapshot() == nil)
    await preferences.assetFolder.loadIfNeeded()
    let snapshot = try #require(controller.snapshot())
    #expect(snapshot.localImagesUnavailable && snapshot.directory == nil)
    await #expect(throws: MarkdownExport.Failure.assetFolderUnavailable) {
      try await MarkdownExport.build(
        source: snapshot.source, title: "Image", directory: snapshot.directory,
        localImagesUnavailable: snapshot.localImagesUnavailable)
    }
    let fragment = try await MarkdownExport.build(
      source: snapshot.source, title: "Copy", directory: nil, embedLocalImages: false,
      localImagesUnavailable: true)
    #expect(fragment.fragment.contains("ice.png"))
    let text = try await MarkdownExport.build(
      source: "Plain text and ![Remote](https://example.invalid/ice.png)", title: "Remote",
      directory: nil, localImagesUnavailable: true)
    #expect(text.document.contains("https://example.invalid/ice.png"))
    preferences.assetFolder.clear()
    #expect(controller.snapshot()?.localImagesUnavailable == false)
    #expect(document.revision == 0 && document.text == snapshot.source)
  }

  @Test(
    "Fresh manual exports retain their folder grant while Settings changes; saved files use their own folder"
  )
  func exportLifetime() async throws {
    let (defaults, domain) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    let root = try directory()
    let other = try directory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: other)
    }
    try image.write(to: root.appending(path: "ice.png"))
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.manualRendering = true
    try await preferences.assetFolder.choose(root)
    let document = MarkdownDocument(contents: TextFileContents(text: "![Ice](ice.png)"))
    let output = DocumentExportController()
    output.document = document
    output.preferences = preferences
    var frozen = output.snapshot()
    weak let access = preferences.assetFolder.access
    preferences.assetFolder.clear()
    #expect(access != nil && output.snapshot()?.directory == nil)
    try await preferences.assetFolder.choose(other)
    #expect(output.snapshot()?.directory?.standardizedFileURL == other.standardizedFileURL)
    let result = try await MarkdownExport.build(
      source: try #require(frozen?.source), options: try #require(frozen?.options),
      title: "Frozen", directory: frozen?.directory, embedLocalImages: true)
    #expect(result.document.contains("data:image/png;base64," + image.base64EncodedString()))
    frozen = nil
    #expect(access == nil)
    let saved = preferences.assetFolder.location(for: root.appending(path: "saved.md"))
    #expect(saved.directory?.path == root.path && saved.access == nil)
    #expect(document.text == "![Ice](ice.png)" && document.revision == 0)
    preferences.assetFolder.clear()
  }

  @Test(
    "Choosing, switching and clearing folders updates an existing native preview without touching source or undo"
  )
  func workspace() async throws {
    _ = NSApplication.shared
    let (defaults, domain) = try isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    let root = try directory()
    let other = try directory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: other)
    }
    try image.write(to: root.appending(path: "ice.png"))
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = "![Ice](ice.png)"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let host = NSHostingController(
      rootView: DocumentWorkspace(document: document, preferences: preferences))
    let window = AssetTestWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .resizable],
      backing: .buffered, defer: false)
    let undo = window.history
    undo.groupsByEvent = false
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.orderFront(nil)
    defer { window.close() }
    func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
      if let found = view as? T { return found }
      return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
    try await waitFor("native views") {
      descendant(WKWebView.self, in: host.view) != nil
        && descendant(MarkdownTextView.self, in: host.view) != nil
    }
    let web = try #require(descendant(WKWebView.self, in: host.view))
    let editor = try #require(descendant(MarkdownTextView.self, in: host.view))
    editor.setSelectedRange(NSRange(location: 2, length: 3))
    #expect(editor.undoManager === undo)
    undo.beginUndoGrouping()
    document.replaceText(with: source + "\n\nKept", undoManager: undo)
    undo.endUndoGrouping()
    let revision = document.revision
    try await waitFor("image transition 0 missing", web: web) {
      try await self.imageState(web) == "missing"
    }
    try await preferences.assetFolder.choose(root)
    try await waitFor("image transition 1 loaded", web: web) {
      try await self.imageState(web) == "loaded"
    }
    try await preferences.assetFolder.choose(other)
    try await waitFor("image transition 2 missing", web: web) {
      try await self.imageState(web) == "missing"
    }
    try await preferences.assetFolder.choose(root)
    try await waitFor("image transition 3 loaded", web: web) {
      try await self.imageState(web) == "loaded"
    }
    preferences.assetFolder.clear()
    try await waitFor("image transition 4 missing", web: web) {
      try await self.imageState(web) == "missing"
    }
    #expect(descendant(WKWebView.self, in: host.view) === web)
    #expect(descendant(MarkdownTextView.self, in: host.view) === editor)
    #expect(document.revision == revision && document.text == source + "\n\nKept")
    #expect(editor.selectedRange() == NSRange(location: 2, length: 3))
    undo.undo()
    #expect(document.text == source)
    try await waitFor("model undo reaches native source") { editor.string == source }
    undo.redo()
    #expect(document.text == source + "\n\nKept")
    try await waitFor("model redo reaches native source") { editor.string == source + "\n\nKept" }
  }

  private final class AssetTestWindow: NSWindow {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
  }

  private func imageState(_ web: WKWebView) async throws -> String {
    try #require(
      try await web.callAsyncJavaScript(
        "const image=document.querySelector('img'); return !image || !image.complete ? 'pending' : image.naturalWidth===1 ? 'loaded' : 'missing';",
        arguments: [:], in: nil, contentWorld: .defaultClient) as? String)
  }

  private func waitFor(_ stage: String, web: WKWebView? = nil, _ condition: () async throws -> Bool)
    async throws
  {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
      if try await condition() { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    let detail =
      if let web {
        try? await web.callAsyncJavaScript(
          "return JSON.stringify({html:document.body.innerHTML,image:[...document.images].map(i=>({complete:i.complete,width:i.naturalWidth,src:i.src}))});",
          arguments: [:], in: nil, contentWorld: .defaultClient) as? String
      } else { nil as String? }
    Issue.record("Asset folder workspace did not settle: \(stage); \(detail ?? "no DOM")")
    throw CocoaError(.coderReadCorrupt)
  }
}
