import Foundation
import Testing
@testable import DocumentCore

@Suite("Document bytes and encoding")
struct TextFileContentsTests {
    @Test("Unedited UTF-8 is byte-for-byte identical", arguments: [
        "", "# MacDown\n", "hello\r\nworld\r\n", "a\rb\nc\r\nd", "  \t\n",
        "日本語と中文 👩🏽‍💻\n", "cafe\u{301}\n", "no final newline",
    ])
    func roundTrip(_ text: String) throws {
        let bytes = Data(text.utf8)
        let contents = try TextFileContents(decoding: bytes)
        #expect(contents.text.utf8.elementsEqual(text.utf8))
        #expect(try contents.encoded() == bytes)
        #expect(contents.encoding == .utf8)
        #expect(!contents.hasByteOrderMark)
    }

    @Test("BOM and explicit encoding survive editing", arguments: TextFileEncoding.allCases)
    func encodings(_ encoding: TextFileEncoding) throws {
        let text = "# 你好 👩‍💻\r\n"
        let bytes: Data
        switch encoding {
        case .utf8:
            bytes = Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        case .utf16LittleEndian:
            bytes = Data([0xFF, 0xFE]) + (try #require(text.data(using: .utf16LittleEndian)))
        case .utf16BigEndian:
            bytes = Data([0xFE, 0xFF]) + (try #require(text.data(using: .utf16BigEndian)))
        }
        let decoded = try TextFileContents(decoding: bytes)
        #expect(decoded.encoding == encoding)
        #expect(decoded.hasByteOrderMark)
        #expect(try decoded.encoded() == bytes)
        let edited = decoded.replacingText(with: "# Changed\r\n")
        let reopened = try TextFileContents(decoding: edited.encoded())
        #expect(reopened.text == "# Changed\r\n")
        #expect(reopened.encoding == encoding)
        #expect(reopened.hasByteOrderMark)
    }

    @Test("Canonically equivalent edits are still real byte changes")
    func canonicalEquivalence() throws {
        let contents = try TextFileContents(decoding: Data("cafe\u{301}".utf8))
        let edited = contents.replacingText(with: "café")
        #expect(try edited.encoded() == Data("café".utf8))
        #expect(try edited.encoded() != contents.encoded())
    }

    @Test("Invalid bytes never become replacement characters", arguments: [
        Data([0xFF]), Data([0xC0, 0xAF]), Data([0xEF, 0xBB, 0xBF, 0xFF]),
        Data([0xFF, 0xFE, 0x00]), Data([0xFE, 0xFF, 0xD8, 0x00]),
        Data([0xFF, 0xFE, 0x00, 0x00]), Data([0x00, 0x00, 0xFE, 0xFF]),
    ])
    func invalidEncoding(_ bytes: Data) {
        #expect(throws: TextFileError.self) { try TextFileContents(decoding: bytes) }
    }

    @Test("No BOM means strict UTF-8, not heuristic legacy encoding")
    func noGuessing() {
        #expect(throws: TextFileError.self) {
            try TextFileContents(decoding: Data([0xE9, 0x20]))
        }
    }

    @Test("Mixed newlines are described without normalization")
    func mixedNewlines() throws {
        let text = "one\r\ntwo\nthree\rfour\r\n"
        let contents = TextFileContents(text: text)
        #expect(contents.lineEndings.lineFeedCount == 1)
        #expect(contents.lineEndings.carriageReturnCount == 1)
        #expect(contents.lineEndings.crlfCount == 2)
        #expect(contents.lineEndings.isMixed)
        #expect(contents.lineEndings.preferred == .crlf)
        #expect(try contents.encoded() == Data(text.utf8))
    }

    @Test("Newline ties use the first observed convention")
    func newlineTies() {
        #expect(LineEndingProfile(text: "a\rb\n").preferred == .carriageReturn)
        #expect(LineEndingProfile(text: "none").preferred == .lineFeed)
    }

    @Test("A 10 MB Unicode document round-trips without a parser or UI")
    func largeDocument() throws {
        let unit = "# 中文 👩‍💻\r\n| a | b |\n|---|---|\n```swift\nlet n = 42\n```\n"
        let text = String(repeating: unit, count: (10 * 1_024 * 1_024 / unit.utf8.count) + 1)
        let bytes = Data(text.utf8)
        let contents = try TextFileContents(decoding: bytes)
        #expect(try contents.encoded() == bytes)
    }
}
