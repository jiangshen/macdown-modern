import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Document reading zoom")
@MainActor
struct DocumentZoomTests {
  @Test("Bounded zoom preserves user intent and stays independent per document")
  func intentAndBounds() {
    let first = DocumentZoomController()
    let second = DocumentZoomController()
    first.restore(percent: 125)
    first.zoomIn()
    first.restore(percent: 80)
    #expect(first.percent == 150)
    #expect(second.percent == 100)
    for _ in 0..<30 { first.zoomIn() }
    #expect(first.percent == 300 && !first.canZoomIn)
    for _ in 0..<30 { first.zoomOut() }
    #expect(first.percent == 50 && !first.canZoomOut)
    first.reset()
    #expect(first.percent == 100 && !first.canReset)
    second.restore(percent: -1)
    #expect(second.percent == 50)
    second.restore(percent: Int.max)
    #expect(second.percent == 300)
  }

  @Test("Presentation scales compose safely without changing configured typography")
  func scales() {
    #expect(DocumentZoomController.sourceFontSize(base: 14, scale: 1.5) == 21)
    #expect(DocumentZoomController.sourceFontSize(base: 8, scale: 0.5) == 4)
    #expect(DocumentZoomController.sourceFontSize(base: 72, scale: 3) == 216)
    #expect(DocumentZoomController.sourceFontSize(base: .nan, scale: .infinity) == 14)
    #expect(
      DocumentZoomController.previewScale(
        workspace: 1.5, baseFontSize: 28,
        followsEditor: false) == 1.5)
    #expect(
      DocumentZoomController.previewScale(
        workspace: 1.5, baseFontSize: 28,
        followsEditor: true) == 3)
  }

  @Test("Durable zoom merges with old viewport records and wins over stale scenes")
  func durableState() throws {
    let domain = "ZoomStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let store = DocumentReadingStore(defaults: defaults)
    let url = URL(filePath: "/private/tmp/zoom-first.md")
    store.save(source: Data([1]), preview: Data([2]), for: url)
    let old = try #require(store.entry(for: url))
    #expect(old.zoomPercent == nil)
    let zoom = DocumentZoomController()
    zoom.configure(fileURL: url, scenePercent: 125, store: store)
    #expect(zoom.percent == 125)
    zoom.zoomIn()
    zoom.persist(fileURL: url, store: store)
    store.save(source: Data([3]), for: url)
    let saved = try #require(store.entry(for: url))
    #expect(saved.source == Data([3]) && saved.preview == Data([2]))
    #expect(saved.zoomPercent == 150)
    store.save(zoomPercent: 150, for: url)
    #expect(store.entry(for: url) == saved)
    store.save(zoomPercent: 301, for: url)
    #expect(store.entry(for: url) == saved)
    let reopened = DocumentZoomController()
    reopened.configure(fileURL: url, scenePercent: 80, store: store)
    #expect(reopened.percent == 150)
    reopened.zoomOut()
    reopened.configure(fileURL: url, scenePercent: 80, store: store)
    #expect(reopened.percent == 125)
    let renamed = URL(filePath: "/private/tmp/zoom-saved-as.md")
    reopened.configure(fileURL: renamed, scenePercent: 80, store: store)
    #expect(store.entry(for: renamed)?.zoomPercent == 125)
    #expect(store.entry(for: url)?.zoomPercent == 125)
    // Older app versions did not encode the optional magnification field.
    let legacyJSON = Data("{\"source\":\"AQ==\",\"updated\":0}".utf8)
    let decoded = try JSONDecoder().decode(DocumentReadingStore.Entry.self, from: legacyJSON)
    #expect(decoded.source == Data([1]) && decoded.zoomPercent == nil)
  }

  @Test("Preview font scaling migrates legacy true and respects an explicit false")
  func preference() throws {
    let domain = "ZoomPreferenceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let initial = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(!initial.previewFollowsEditorFont)
    defaults.removePersistentDomain(forName: domain)
    let migrated = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["previewZoomRelativeToBaseFontSize": true])
    #expect(migrated.previewFollowsEditorFont)
    migrated.previewFollowsEditorFont = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["previewZoomRelativeToBaseFontSize": true])
    #expect(!reopened.previewFollowsEditorFont)
  }
}
