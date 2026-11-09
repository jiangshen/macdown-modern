import Foundation
import Testing

@testable import RenderingCore

@Suite("Rendered writing statistics")
struct WritingStatisticsTests {
  @Test("Text node boundaries, inline code and block code preserve original word semantics")
  func words() async throws {
    let result = try await WritingStatistics.count([
      .init(text: "hel"), .init(text: "lo"),
      .init(text: "two words", wordGroup: 1), .init(text: " another", wordGroup: 1),
      .init(text: "!!!", wordGroup: 2), .init(text: "other code", wordGroup: 3),
      .init(text: "block code words\n", wordGroup: -1),
    ])
    #expect(result.words == 4)
    #expect(result.characters == 51)
    #expect(result.charactersWithoutSpaces == 46)
    #expect(result[.words] == 4)
    #expect(result[.characters] == result.characters)
    #expect(result[.charactersWithoutSpaces] == result.charactersWithoutSpaces)
  }

  @Test("Characters are UTF16 units, retaining emoji sequences and combining marks")
  func utf16() async throws {
    let result = try await WritingStatistics.count([.init(text: "🧊e\u{301}\n A\tB")])
    #expect(result == .init(words: 3, characters: 8, charactersWithoutSpaces: 6))
  }

  @Test("Every Foundation newline and whitespace class uses the original NSString policy")
  func whitespace() async throws {
    let text = "A\r\nB\u{85}C\u{2028}D\u{2029} E\t\u{a0}F\u{2003}G"
    let result = try await WritingStatistics.count([.init(text: text)])
    #expect(result.characters == 11)
    #expect(result.charactersWithoutSpaces == 7)
    #expect(result.characters == text.components(separatedBy: .newlines).joined().utf16.count)
    #expect(
      result.charactersWithoutSpaces
        == text.components(separatedBy: .whitespacesAndNewlines).joined().utf16.count)
  }

  @Test("Snapshots decode without normalizing exact Unicode and cancellation stops stale work")
  func snapshotAndCancellation() async throws {
    let json = #"[{"text":"🧊e\u0301\n A\tB","wordGroup":0}]"#
    #expect(try await WritingStatistics.countSnapshot(json).characters == 8)
    await #expect(throws: (any Error).self) {
      try await WritingStatistics.countSnapshot("null")
    }
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await WritingStatistics.count([.init(text: "unused")])
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(
      try await WritingStatistics.count([])
        == .init(words: 0, characters: 0, charactersWithoutSpaces: 0))
  }
}
