// Adapted from MacDown's NSString+Lookup.m (MIT, copyright Tzu-ping Chung).
import Foundation

/// Compatibility boundary for existing AppKit UTF-16 selection behavior.
/// These methods are line navigation utilities, not a Markdown parser.
public struct LegacyLineLookup: Sendable {
    public let text: String

    public init(_ text: String) { self.text = text }

    public func newlineBefore(_ offset: Int) -> Int {
        let string = text as NSString
        let location = min(max(0, offset), string.length)
        var start = 0
        string.getLineStart(&start, end: nil, contentsEnd: nil,
                            for: NSRange(location: location, length: 0))
        return start - 1
    }

    public func newlineAfter(_ offset: Int) -> Int {
        let string = text as NSString
        // Clamp before adding one to avoid overflowing a caller-supplied Int.max.
        let clamped = min(max(0, offset), string.length)
        let location = clamped < string.length ? clamped + 1 : clamped
        var end = 0
        string.getLineStart(nil, end: nil, contentsEnd: &end,
                            for: NSRange(location: location, length: 0))
        return end
    }

    public func firstNonWhitespace(before offset: Int) -> Int {
        let string = text as NSString
        let location = min(max(0, offset), string.length)
        var index = newlineBefore(location) + 1
        while index < location && (CharacterSet.whitespaces as NSCharacterSet).characterIsMember(string.character(at: index)) {
            index += 1
        }
        return index
    }
}
