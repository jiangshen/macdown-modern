import CoreText
import EmojiCore
import Foundation

/// The portable source accepts Unicode's full catalog; the native picker offers
/// only choices this Mac's emoji font can display as one composed glyph.
enum EmojiDisplayCatalog {
  private static let cache = Cache()

  @concurrent
  static func load() async throws -> [EmojiEntry] { try await cache.load() }

  private actor Cache {
    private var entries: [EmojiEntry]?
    func load() async throws -> [EmojiEntry] {
      if let entries { return entries }
      let all = try await EmojiCatalog.load()
      if let entries { return entries }
      let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 25, nil)
      let supported = all.filter { EmojiDisplayCatalog.isRenderable($0.glyph, font: font) }
      entries = supported
      return supported
    }
  }

  static func isRenderable(_ emoji: String, font: CTFont) -> Bool {
    guard let first = emoji.unicodeScalars.first else { return false }
    var units = Array(String(first).utf16)
    var glyphs = Array(repeating: CGGlyph(), count: units.count)
    guard CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) else { return false }
    let text = NSAttributedString(
      string: emoji, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    return CTLineGetGlyphCount(CTLineCreateWithAttributedString(text)) == 1
  }
}
