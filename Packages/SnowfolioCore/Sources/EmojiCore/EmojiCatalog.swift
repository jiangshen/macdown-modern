import Foundation

public struct EmojiEntry: Decodable, Identifiable, Sendable {
  public let glyph: String
  public let name: String
  public let group: String
  public var id: String { glyph }
}

public enum EmojiCatalog {
  private static let entries: [EmojiEntry] = {
    guard let url = Bundle.module.url(forResource: "Emoji", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let entries = try? JSONDecoder().decode([EmojiEntry].self, from: data)
    else { return [] }
    return entries
  }()
  private static let normalizedGlyphs = Set(entries.map { normalize($0.glyph) })

  private static func normalize(_ value: String) -> String {
    value.replacingOccurrences(of: "\u{FE0F}", with: "")
  }

  public static func isEmoji(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 128, value.count == 1 else { return false }
    return normalizedGlyphs.contains(normalize(value))
  }

  @concurrent
  public static func load() async throws -> [EmojiEntry] {
    guard !entries.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    return entries
  }
}
