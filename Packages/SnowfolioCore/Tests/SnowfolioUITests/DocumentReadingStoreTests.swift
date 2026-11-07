import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Durable document reading positions")
@MainActor
struct DocumentReadingStoreTests {
  @Test("Positions survive a new store, stay separate per file, and preserve the other pane")
  func persistence() throws {
    let domain = "ReadingStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let first = URL(filePath: "/private/tmp/first.md")
    let second = URL(filePath: "/private/tmp/second.md")
    let store = DocumentReadingStore(defaults: defaults)
    store.save(source: Data("source A".utf8), preview: Data("preview A".utf8), for: first)
    store.save(source: Data("source B".utf8), preview: nil, for: second)
    store.save(source: nil, preview: Data("preview updated".utf8), for: first)
    let reopened = DocumentReadingStore(defaults: defaults)
    #expect(reopened.entry(for: first)?.source == Data("source A".utf8))
    #expect(reopened.entry(for: first)?.preview == Data("preview updated".utf8))
    #expect(reopened.entry(for: second)?.source == Data("source B".utf8))
    #expect(reopened.entry(for: second)?.preview == nil)
    let before = reopened.entry(for: first)
    reopened.save(source: before?.source, preview: before?.preview, for: first)
    #expect(reopened.entry(for: first) == before)
    let records = try #require(defaults.dictionary(forKey: DocumentReadingStore.storageKey))
    #expect(records.keys.allSatisfy { $0.count == 64 && !$0.contains("first") })
  }

  @Test("The cache is bounded and ignores corrupt, oversized and non-file input")
  func boundaries() throws {
    let domain = "ReadingStoreBoundsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let store = DocumentReadingStore(defaults: defaults, capacity: 2)
    defaults.set(["corrupt": Data("bad".utf8)], forKey: DocumentReadingStore.storageKey)
    for index in 1...3 {
      store.save(source: Data([UInt8(index)]), preview: nil, for: URL(filePath: "/tmp/\(index).md"))
    }
    #expect(defaults.dictionary(forKey: DocumentReadingStore.storageKey)?.count == 2)
    #expect(store.entry(for: URL(filePath: "/tmp/1.md")) == nil)
    #expect(store.entry(for: URL(filePath: "/tmp/3.md"))?.source == Data([3]))
    let oversized = URL(filePath: "/tmp/oversized.md")
    store.save(source: Data(repeating: 1, count: 1025), preview: nil, for: oversized)
    #expect(store.entry(for: oversized) == nil)
    let remote = try #require(URL(string: "https://example.com/remote.md"))
    store.save(source: Data([1]), preview: nil, for: remote)
    #expect(store.entry(for: remote) == nil)
  }
}
