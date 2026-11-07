import Foundation
import Testing

@testable import RenderingCore

@Suite("Exact syntax text identity")
struct UTF8TextTests {
  @Test("Empty, prefix, NUL and canonically equivalent text retain byte distinctions")
  func values() {
    for (first, second, expected) in [
      ("", "", true), ("", "a", false), ("a", "", false), ("a", "a", true),
      ("a", "A", false), ("abc", "abcd", false), ("abcd", "abce", false),
      ("\0x", "\0x", true), ("\0x", "\0y", false), ("café", "cafe\u{301}", false),
      ("中文 👩🏽‍💻", "中文 👩🏽‍💻", true), ("中文 👩🏽‍💻", "中文 👩‍💻", false),
    ] {
      #expect(UTF8Text.equal(first, second) == expected)
      #expect(UTF8Text.equal(second, first) == expected)
    }
  }

  @Test("Reused, independently allocated and bridged storage compare safely")
  func storage() {
    let value = String(repeating: "<p>中文 e\u{301} \0</p>", count: 4096)
    let shared = value
    let independent = String(decoding: Array(value.utf8), as: UTF8.self)
    let bridged = NSString(format: "%@", value) as String
    #expect(UTF8Text.equal(value, shared))
    #expect(UTF8Text.equal(value, independent))
    #expect(UTF8Text.equal(value, bridged))
    #expect(!UTF8Text.equal(value, independent + "x"))
    #expect(!UTF8Text.equal(value + "x", independent + "y"))
  }
}
