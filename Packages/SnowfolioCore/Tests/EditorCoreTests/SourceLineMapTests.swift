import Foundation
import Testing

@testable import EditorCore

@Suite("Source scroll coordinates")
struct SourceLineMapTests {
  @Test(
    "Unicode offsets and CR/LF/CRLF keep their native source lines",
    arguments: ["\n", "\r", "\r\n"])
  func sourceLines(newline: String) {
    let first = "A😀B" + newline
    let second = "中文" + newline
    let map = SourceLineMap(first + second + "last")
    #expect(map.lineStarts == [0, first.utf16.count, (first + second).utf16.count])
    #expect(map.linePosition(atUTF16Offset: first.utf16.count) == 2)
    #expect(map.utf16Offset(atLinePosition: 3) == (first + second).utf16.count)
    #expect(map.utf16Offset(atLinePosition: .infinity) == 0)
    #expect(map.utf16Offset(atLinePosition: 1e200) == map.utf16Length)
  }

  @Test("Fractional lines round-trip bounded UTF-16 coordinates")
  func fractionalLines() {
    let map = SourceLineMap("abcdef\n\nlong paragraph\r\nlast")
    for offset in 0...map.utf16Length {
      let position = map.linePosition(atUTF16Offset: offset)
      #expect(abs(map.utf16Offset(atLinePosition: position) - offset) <= 1)
    }
    let empty = SourceLineMap("")
    #expect(empty.linePosition(atUTF16Offset: Int.max) == 1)
    #expect(empty.utf16Offset(atLinePosition: -100) == 0)
    #expect(!MarkdownScrollPosition(line: .nan).isValid)
    #expect(!MarkdownScrollPosition(line: 0).isValid)
  }
}
