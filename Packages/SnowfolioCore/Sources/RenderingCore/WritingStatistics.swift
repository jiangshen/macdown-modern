import Foundation

/// The original counter's units are Foundation words and UTF16 code units.
/// Text-node boundaries matter: joining adjacent styled runs changes word counts.
public struct WritingStatistics: Equatable, Sendable {
  public let words: Int
  public let characters: Int
  public let charactersWithoutSpaces: Int

  public init(words: Int, characters: Int, charactersWithoutSpaces: Int) {
    self.words = words
    self.characters = characters
    self.charactersWithoutSpaces = charactersWithoutSpaces
  }

  public subscript(mode: WritingStatisticsMode) -> Int {
    switch mode {
    case .words: words
    case .characters: characters
    case .charactersWithoutSpaces: charactersWithoutSpaces
    }
  }

  @concurrent public static func countSnapshot(_ json: String) async throws -> Self {
    try Task.checkCancellation()
    let runs = try JSONDecoder().decode([PreviewTextRun].self, from: Data(json.utf8))
    return try await count(runs)
  }

  /// A snapshot is counted off the UI actor, once per committed preview update.
  @concurrent public static func count(_ runs: [PreviewTextRun]) async throws -> Self {
    var words = 0
    var characters = 0
    var charactersWithoutSpaces = 0
    var inlineCodeWithWords = Set<Int>()
    let newlines = CharacterSet.newlines
    let whitespace = CharacterSet.whitespacesAndNewlines
    for run in runs {
      try Task.checkCancellation()
      for (index, scalar) in run.text.unicodeScalars.enumerated() {
        if index.isMultiple(of: 4096) { try Task.checkCancellation() }
        let length = scalar.utf16.count
        if !newlines.contains(scalar) { characters += length }
        if !whitespace.contains(scalar) {
          charactersWithoutSpaces += length
        }
      }
      guard run.wordGroup >= 0 else { continue }
      // An inline code element contributes at most one word, including nested spans.
      if run.wordGroup > 0, inlineCodeWithWords.contains(run.wordGroup) { continue }
      let text = run.text as NSString
      var count = 0
      text.enumerateSubstrings(
        in: NSRange(location: 0, length: text.length), options: [.byWords, .substringNotRequired]
      ) { _, _, _, stop in
        if Task.isCancelled {
          stop.pointee = true
          return
        }
        count += 1
        if run.wordGroup > 0 { stop.pointee = true }
      }
      try Task.checkCancellation()
      if run.wordGroup == 0 {
        words += count
      } else if count > 0 {
        inlineCodeWithWords.insert(run.wordGroup)
      }
    }
    return Self(
      words: words + inlineCodeWithWords.count, characters: characters,
      charactersWithoutSpaces: charactersWithoutSpaces)
  }
}

public enum WritingStatisticsMode: Int, CaseIterable, Identifiable, Sendable {
  case words, characters, charactersWithoutSpaces
  public var id: Self { self }
  public var title: String {
    switch self {
    case .words: String(localized: "Words")
    case .characters: String(localized: "Characters")
    case .charactersWithoutSpaces: String(localized: "Characters without spaces")
    }
  }

  public func title(for statistics: WritingStatistics) -> String {
    let amount = statistics[self]
    if amount == 1 {
      switch self {
      case .words: return String(localized: "1 word")
      case .characters: return String(localized: "1 character")
      case .charactersWithoutSpaces: return String(localized: "1 character without spaces")
      }
    }
    let value = amount.formatted()
    switch self {
    case .words: return String(localized: "\(value) words")
    case .characters: return String(localized: "\(value) characters")
    case .charactersWithoutSpaces: return String(localized: "\(value) characters without spaces")
    }
  }
}

/// wordGroup: -1 excludes block-code words; 0 counts normal text nodes;
/// positive values collapse each inline-code subtree to one Foundation word.
public struct PreviewTextRun: Codable, Equatable, Sendable {
  public let text: String
  public let wordGroup: Int
  public init(text: String, wordGroup: Int = 0) {
    self.text = text
    self.wordGroup = wordGroup
  }
}
