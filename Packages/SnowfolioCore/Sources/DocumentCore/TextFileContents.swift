import Foundation

/// Encodings that can be identified without guessing a user's legacy code page.
public enum TextFileEncoding: String, CaseIterable, Sendable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian

    fileprivate var foundationEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        }
    }

    fileprivate var byteOrderMark: Data {
        switch self {
        case .utf8: Data([0xEF, 0xBB, 0xBF])
        case .utf16LittleEndian: Data([0xFF, 0xFE])
        case .utf16BigEndian: Data([0xFE, 0xFF])
        }
    }
}

public enum TextFileError: Error, Equatable, Sendable {
    case unsupportedEncoding
    case invalidTextEncoding(TextFileEncoding)
}

/// Immutable document snapshot shared between the document host and background work.
/// File coordination, autosave and undo belong to the native document host, not this codec.
public struct TextFileContents: Sendable {
    public let text: String
    public let encoding: TextFileEncoding
    public let hasByteOrderMark: Bool

    private let originalText: String?
    private let originalBytes: Data?

    /// New documents use UTF-8. Other encodings are retained when opening BOM-tagged files.
    public init(text: String = "", hasByteOrderMark: Bool = false) {
        self.text = text
        self.encoding = .utf8
        self.hasByteOrderMark = hasByteOrderMark
        originalText = nil
        originalBytes = nil
    }

    public init(decoding data: Data) throws {
        // Test UTF-32 before UTF-16 because their little-endian BOMs overlap.
        guard !data.starts(with: [0xFF, 0xFE, 0x00, 0x00]),
              !data.starts(with: [0x00, 0x00, 0xFE, 0xFF]) else {
            throw TextFileError.unsupportedEncoding
        }
        let detected = TextFileEncoding.allCases.first { data.starts(with: $0.byteOrderMark) }
        let encoding = detected ?? .utf8
        let payload = detected == nil ? data : Data(data.dropFirst(encoding.byteOrderMark.count))
        guard let text = String(data: payload, encoding: encoding.foundationEncoding),
              text.data(using: encoding.foundationEncoding, allowLossyConversion: false) == payload else {
            throw TextFileError.invalidTextEncoding(encoding)
        }
        self.text = text
        self.encoding = encoding
        hasByteOrderMark = detected != nil
        originalText = text
        originalBytes = data
    }

    private init(text: String, preserving snapshot: Self) {
        self.text = text
        encoding = snapshot.encoding
        hasByteOrderMark = snapshot.hasByteOrderMark
        originalText = snapshot.originalText
        originalBytes = snapshot.originalBytes
    }

    public func replacingText(with text: String) -> Self {
        Self(text: text, preserving: self)
    }

    /// Describes source newlines; never rewrites them or adds a final newline.
    public var lineEndings: LineEndingProfile { LineEndingProfile(text: text) }

    public func encoded() throws -> Data {
        // Swift String == treats canonically equivalent Unicode as equal. Compare bytes
        // so an intentional normalization edit is not mistaken for unchanged text.
        if let originalText, let originalBytes,
           text.utf8.elementsEqual(originalText.utf8) {
            return originalBytes
        }
        guard let payload = text.data(using: encoding.foundationEncoding, allowLossyConversion: false) else {
            throw TextFileError.invalidTextEncoding(encoding)
        }
        guard hasByteOrderMark else { return payload }
        var data = encoding.byteOrderMark
        data.append(payload)
        return data
    }
}
