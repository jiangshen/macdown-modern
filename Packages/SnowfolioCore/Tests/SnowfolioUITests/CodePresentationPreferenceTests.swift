import Foundation
import MarkdownCore
import Testing

@testable import SnowfolioUI

@Suite("Code presentation preference migration")
@MainActor
struct CodePresentationPreferenceTests {
  @Test("Code options migrate, persist and reach immutable export snapshots")
  func migration() throws {
    let domain = "CodePresentationPreferences." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["htmlLineNumbers": true, "htmlCodeBlockAccessory": 2])
    #expect(preferences.codeLineNumbers && preferences.codeBlockAccessory == .custom)
    preferences.codeHighlighting = false
    #expect(
      preferences.renderingOptions.codeLineNumbers
        && preferences.renderingOptions.codeBlockAccessory == .custom)
    let snapshot = preferences.renderingOptions
    preferences.codeLineNumbers = false
    preferences.codeBlockAccessory = .language
    let reopened = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(!reopened.codeLineNumbers && reopened.codeBlockAccessory == .language)
    #expect(!reopened.codeHighlighting)
    #expect(defaults.integer(forKey: "htmlCodeBlockAccessory") == 1)
    #expect(snapshot.codeLineNumbers && snapshot.codeBlockAccessory == .custom)
    defaults.set(99, forKey: "htmlCodeBlockAccessory")
    let unknown = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(
      unknown.codeBlockAccessory == .none
        && defaults.integer(forKey: "htmlCodeBlockAccessory") == 99)
  }
}
