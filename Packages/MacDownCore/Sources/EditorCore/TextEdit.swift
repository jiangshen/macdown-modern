import Foundation

public enum TextEditError: Error, Equatable, Sendable {
    case invalidUTF16Range
}

/// A single replacement applied through the native editor's undo manager by its UI adapter.
public struct TextEdit: Sendable {
    public let range: NSRange
    public let replacement: String

    public init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    public func applying(to text: String) throws -> TextEditResult {
        try Self.validate(range, in: text)
        let string = text as NSString
        let removed = string.substring(with: range)
        let result = string.replacingCharacters(in: range, with: replacement)
        let replacementLength = replacement.utf16.count
        return TextEditResult(
            text: result,
            selection: NSRange(location: range.location + replacementLength, length: 0),
            inverse: TextEdit(range: NSRange(location: range.location, length: replacementLength),
                              replacement: removed)
        )
    }

    /// Wraps source selection while retaining it; an empty selection becomes an insertion point.
    public static func wrapping(_ selection: NSRange, in text: String,
                                prefix: String, suffix: String) throws -> TextEditResult {
        try validate(selection, in: text)
        let content = (text as NSString).substring(with: selection)
        let edit = TextEdit(range: selection, replacement: prefix + content + suffix)
        let result = try edit.applying(to: text)
        return TextEditResult(text: result.text,
                              selection: NSRange(location: selection.location + prefix.utf16.count,
                                                 length: selection.length),
                              inverse: result.inverse)
    }

    static func validate(_ range: NSRange, in text: String) throws {
        let string = text as NSString
        let length = string.length
        guard range.location >= 0, range.length >= 0, range.location <= length,
              range.length <= length - range.location else {
            throw TextEditError.invalidUTF16Range
        }
        // Foundation range conversion alone can admit a split surrogate. Reject those
        // boundaries explicitly before calling NSString replacement APIs.
        for offset in [range.location, range.location + range.length] where offset < length {
            if (0xDC00...0xDFFF).contains(string.character(at: offset)) {
                throw TextEditError.invalidUTF16Range
            }
        }
    }
}

public struct TextEditResult: Sendable {
    public let text: String
    public let selection: NSRange
    public let inverse: TextEdit
}
