import CryptoKit
import Foundation

/// Bounded per-file positions that survive document-host scene recreation.
/// Keys are hashed file URLs; values contain UI coordinates, never document text.
@MainActor
final class DocumentReadingStore {
  static let shared = DocumentReadingStore()
  static let storageKey = "documentReadingPositions"
  private let defaults: UserDefaults
  private let capacity: Int

  struct Entry: Codable, Equatable {
    var source: Data?
    var preview: Data?
    var updated: Date
  }

  init(defaults: UserDefaults = .standard, capacity: Int = 128) {
    self.defaults = defaults
    self.capacity = max(1, capacity)
  }

  private func key(for url: URL) -> String? {
    guard url.isFileURL else { return nil }
    let bytes = Data(url.standardizedFileURL.absoluteString.utf8)
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }

  func entry(for url: URL) -> Entry? {
    guard let key = key(for: url),
      let data = defaults.dictionary(forKey: Self.storageKey)?[key] as? Data,
      data.count <= 4096
    else { return nil }
    return try? JSONDecoder().decode(Entry.self, from: data)
  }

  func save(source: Data?, preview: Data?, for url: URL) {
    guard let key = key(for: url), source != nil || preview != nil,
      (source?.count ?? 0) <= 1024, (preview?.count ?? 0) <= 1024
    else { return }
    let previous = entry(for: url)
    let source = source ?? previous?.source
    let preview = preview ?? previous?.preview
    guard source != previous?.source || preview != previous?.preview else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(Entry(source: source, preview: preview, updated: .now))
    else { return }
    var records = defaults.dictionary(forKey: Self.storageKey) ?? [:]
    records[key] = data
    if records.count > capacity {
      let newest = records.compactMap { key, value -> (String, Date)? in
        guard let data = value as? Data, data.count <= 4096,
          let value = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }
        return (key, value.updated)
      }.sorted { $0.1 > $1.1 }.prefix(capacity)
      records = Dictionary(
        uniqueKeysWithValues: newest.compactMap { key, _ in
          records[key].map { (key, $0) }
        })
    }
    defaults.set(records, forKey: Self.storageKey)
  }
}
