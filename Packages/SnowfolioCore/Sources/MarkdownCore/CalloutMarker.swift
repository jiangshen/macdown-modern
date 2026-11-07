import EmojiCore
import Foundation

/// A portable, explicit Notebook extension: `> [!NOTE] 💡` changes only its icon.
/// Arbitrary titles/HTML after a marker are not interpreted as icon metadata.
public struct CalloutMarker: Equatable, Sendable {
  public let kind: MarkdownCallout
  public let emoji: String?

  public static func isEmoji(_ value: String) -> Bool {
    EmojiCatalog.isEmoji(value)
  }

  public static func parse(_ rawLine: String) -> Self? {
    let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
    guard line.first == ">" else { return nil }
    let marker = line.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard marker.hasPrefix("[!"), let end = marker.firstIndex(of: "]"),
      let kind = MarkdownCallout.allCases.first(where: {
        marker[...end] == "[!\($0.rawValue.uppercased())]"
      })
    else { return nil }
    let suffix = marker[marker.index(after: end)...]
    if suffix.isEmpty { return Self(kind: kind, emoji: nil) }
    guard suffix.first == " " || suffix.first == "\t" else { return nil }
    let emoji = suffix.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard isEmoji(emoji) else { return nil }
    return Self(kind: kind, emoji: emoji)
  }

  /// A minimal UTF-16 replacement preserving the marker, indentation and line ending.
  /// Only CR/LF/CRLF count as lines, matching cmark rather than Unicode paragraph separators.
  public static func iconReplacement(in source: String, line: Int, emoji: String?)
    -> (range: NSRange, replacement: String)?
  {
    guard line > 0, emoji == nil || isEmoji(emoji ?? "") else { return nil }
    let units = source.utf16
    var index = units.startIndex
    var currentLine = 1
    var offset = 0
    while index != units.endIndex, currentLine < line {
      let value = units[index]
      index = units.index(after: index)
      offset += 1
      if value == 13 {
        if index != units.endIndex, units[index] == 10 {
          index = units.index(after: index)
          offset += 1
        }
        currentLine += 1
      } else if value == 10 {
        currentLine += 1
      }
    }
    guard currentLine == line else { return nil }
    let start = offset
    while index != units.endIndex, units[index] != 10, units[index] != 13 {
      index = units.index(after: index)
      offset += 1
    }
    let text = source as NSString
    let rawLine = text.substring(with: NSRange(location: start, length: offset - start))
    guard parse(rawLine) != nil, let bracket = rawLine.firstIndex(of: "]") else { return nil }
    let tail = rawLine[rawLine.index(after: bracket)...]
    let trimmed = tail.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    let suffixStart = start + rawLine[..<rawLine.index(after: bracket)].utf16.count
    let suffixLength: Int
    if trimmed.isEmpty {
      suffixLength = 0
    } else {
      let trailing = tail.reversed().prefix { $0 == " " || $0 == "\t" }.count
      suffixLength = tail.utf16.count - trailing
    }
    return (NSRange(location: suffixStart, length: suffixLength), emoji.map { " " + $0 } ?? "")
  }
}
