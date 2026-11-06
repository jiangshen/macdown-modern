// Characterization of MacDownTests/MPStringLookupTests.m and NSString+Lookup.m.
// Original behavior copyright Tzu-ping Chung; see LICENSE/macdown.txt.
import Foundation
import Testing
@testable import EditorCore

@Suite("Legacy UTF-16 line lookup parity")
struct LegacyLineLookupTests {
    @Test("Previous newline retains the legacy -1 sentinel")
    func previousNewline() {
        let text = LegacyLineLookup("123\n45")
        for offset in 0..<4 { #expect(text.newlineBefore(offset) == -1) }
        for offset in 4..<6 { #expect(text.newlineBefore(offset) == 3) }
        #expect(text.newlineBefore(10_000) == 3)
        #expect(LegacyLineLookup("\n1234").newlineBefore(0) == -1)
        #expect(LegacyLineLookup("\n1234").newlineBefore(1) == 0)
        #expect(LegacyLineLookup("1234\n").newlineBefore(5) == 4)
        for offset in 0..<6 { #expect(LegacyLineLookup("1234").newlineBefore(offset) == -1) }
    }

    @Test("Next newline skips the current newline, matching the old editor")
    func nextNewline() {
        let text = LegacyLineLookup("123\n45")
        for offset in 0..<3 { #expect(text.newlineAfter(offset) == 3) }
        for offset in 3..<6 { #expect(text.newlineAfter(offset) == 6) }
        #expect(text.newlineAfter(10_000) == 6)
        for offset in 0..<4 { #expect(LegacyLineLookup("1234\n").newlineAfter(offset) == 4) }
        #expect(LegacyLineLookup("1234\n").newlineAfter(4) == 5)
    }

    @Test("Whitespace lookup never goes past the requested cursor")
    func firstNonWhitespace() {
        let text = LegacyLineLookup("  12345")
        #expect(text.firstNonWhitespace(before: 0) == 0)
        #expect(text.firstNonWhitespace(before: 1) == 1)
        for offset in 2..<7 { #expect(text.firstNonWhitespace(before: offset) == 2) }
        #expect(LegacyLineLookup("\n\n 12").firstNonWhitespace(before: 9) == 3)
        #expect(LegacyLineLookup("\n\n1\n").firstNonWhitespace(before: 9) == 4)
        #expect(LegacyLineLookup("\t\u{00A0} x").firstNonWhitespace(before: 9) == 3)
    }

    @Test("AppKit offsets count UTF-16 code units, not grapheme clusters")
    func unicode() {
        let text = LegacyLineLookup("👩‍💻\n中文")
        #expect(text.newlineAfter(0) == 5)
        #expect(text.newlineBefore(6) == 5)
        #expect(text.newlineAfter(.max) == 8)
        #expect(text.newlineBefore(-20) == -1)
    }

    @Test("CRLF and empty text use Foundation line boundaries")
    func lineBoundaries() {
        #expect(LegacyLineLookup("").newlineBefore(0) == -1)
        #expect(LegacyLineLookup("").newlineAfter(0) == 0)
        #expect(LegacyLineLookup("a\r\nb").newlineBefore(3) == 2)
        #expect(LegacyLineLookup("a\r\nb").newlineAfter(0) == 1)
    }
}
