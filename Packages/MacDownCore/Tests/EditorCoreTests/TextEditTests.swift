import Foundation
import Testing
@testable import EditorCore

@Suite("Native editor edit transactions")
struct TextEditTests {
    @Test("Formatting preserves selection and produces an undo transaction")
    func wrapping() throws {
        let text = "hello 中文 👩‍💻"
        let selection = NSRange(location: 6, length: 2)
        let result = try TextEdit.wrapping(selection, in: text, prefix: "**", suffix: "**")
        #expect(result.text == "hello **中文** 👩‍💻")
        #expect(result.selection == NSRange(location: 8, length: 2))
        #expect(try result.inverse.applying(to: result.text).text == text)
    }

    @Test("Empty formatting places the cursor between delimiters")
    func emptySelection() throws {
        let result = try TextEdit.wrapping(NSRange(location: 0, length: 0), in: "",
                                          prefix: "[", suffix: "](url)")
        #expect(result.text == "[](url)")
        #expect(result.selection == NSRange(location: 1, length: 0))
    }

    @Test("Replacement and inverse preserve exact bytes, including decomposed Unicode")
    func replacement() throws {
        let text = "cafe\u{301}\r\n👩‍💻"
        let edit = TextEdit(range: NSRange(location: 7, length: 5), replacement: "你好")
        let result = try edit.applying(to: text)
        #expect(result.selection == NSRange(location: 9, length: 0))
        let restored = try result.inverse.applying(to: result.text).text
        #expect(restored.utf8.elementsEqual(text.utf8))
    }

    @Test("Invalid and overflowing ranges are errors, never crashes", arguments: [
        NSRange(location: -1, length: 0), NSRange(location: .max, length: 1),
        NSRange(location: 0, length: .max), NSRange(location: 99, length: 0),
        NSRange(location: 1, length: 0), // splits the emoji's surrogate pair
    ])
    func invalidRange(_ range: NSRange) {
        #expect(throws: TextEditError.self) {
            try TextEdit(range: range, replacement: "x").applying(to: "😀")
        }
    }

    @Test("Combining scalars are preserved at valid UTF-16 boundaries")
    func combiningScalars() throws {
        let text = "e\u{301}"
        let result = try TextEdit(range: NSRange(location: 1, length: 0), replacement: "x").applying(to: text)
        #expect(result.text.utf8.elementsEqual("ex\u{301}".utf8))
        #expect(try result.inverse.applying(to: result.text).text.utf8.elementsEqual(text.utf8))
    }

    @Test("Inverse transactions work across varied native selections", arguments: [
        "", "ordinary text", "中文", "👩🏽‍💻", "cafe\u{301}", "a\r\nb\rc\n",
    ])
    func inverse(_ text: String) throws {
        let result = try TextEdit(range: NSRange(location: 0, length: text.utf16.count),
                                  replacement: "replacement\n").applying(to: text)
        #expect(try result.inverse.applying(to: result.text).text.utf8.elementsEqual(text.utf8))
    }
}
