import Foundation
import RenderingCore
import Testing

@testable import SnowfolioUI

@Suite("Writing statistics preferences")
@MainActor
struct WritingStatisticsPreferenceTests {
  @Test("The original keys migrate, explicit choices win and all three modes persist")
  func migration() throws {
    let domain = "WritingStatisticsPreferences." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["editorShowWordCount": true, "editorWordCountType": 2])
    #expect(preferences.showWritingStatistics)
    #expect(preferences.writingStatisticsMode == .charactersWithoutSpaces)
    for mode in WritingStatisticsMode.allCases {
      preferences.writingStatisticsMode = mode
      let reopened = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
      #expect(reopened.writingStatisticsMode == mode)
      #expect(defaults.integer(forKey: "editorWordCountType") == mode.rawValue)
    }
    preferences.showWritingStatistics = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["editorShowWordCount": true])
    #expect(!reopened.showWritingStatistics)
    defaults.set(99, forKey: "editorWordCountType")
    let unknown = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(unknown.writingStatisticsMode == .words)
    #expect(defaults.integer(forKey: "editorWordCountType") == 99)
    #expect(
      SettingsCatalog.search("writing statistics").map(\.id) == [
        "showWritingStatistics", "writingStatisticsMode",
      ])
  }
}
