import Foundation
import Testing

@testable import MacDownUI

@Suite("Application preferences")
@MainActor
struct AppPreferencesTests {
  @Test("Legacy choices initialize the UI and changes persist across application models")
  func persistence() throws {
    let domain = "AppPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: [
        "extensionTables": false, "extensionStrikethough": true,
        "editorBaseFontInfo": ["name": "Menlo-Regular", "size": 18],
      ])
    #expect(!preferences.tables)
    #expect(preferences.strikethrough)
    #expect(preferences.editorFontSize == 18)
    #expect(!preferences.remoteImages)
    #expect(!preferences.rawHTML)
    preferences.tables = true
    preferences.manualRendering = true
    preferences.editorFontSize = 22
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["extensionTables": false])
    #expect(reopened.renderingOptions.tables)
    #expect(reopened.manualRendering)
    #expect(reopened.editorFontSize == 22)
    #expect(!reopened.remoteImages)
  }
}
