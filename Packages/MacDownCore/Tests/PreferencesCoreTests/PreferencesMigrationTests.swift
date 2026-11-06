import Foundation
import Testing

@testable import PreferencesCore

@Suite("Preferences upgrade")
@MainActor
struct PreferencesMigrationTests {
  @Test(
    "Migration preserves false values, fonts and custom choices without overwriting newer settings")
  func migration() throws {
    let domain = "MacDownMigrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set("New style", forKey: "htmlStyleName")
    let legacy: [String: Any] = [
      "extensionTables": false, "htmlStyleName": "Old style",
      "editorBaseFontInfo": ["name": "Menlo-Regular", "size": 18],
      "extensionStrikethough": true, "filesToOpenOnNextLaunch": ["/tmp/not-a-setting.md"],
    ]
    #expect(LegacyPreferencesMigration.migrate(legacy, into: defaults, targetDomain: domain) == 3)
    #expect(defaults.object(forKey: "extensionTables") as? Bool == false)
    #expect(defaults.string(forKey: "htmlStyleName") == "New style")
    #expect(defaults.dictionary(forKey: "editorBaseFontInfo")?["size"] as? Int == 18)
    #expect(defaults.bool(forKey: "extensionStrikethough"))
    #expect(defaults.object(forKey: "filesToOpenOnNextLaunch") == nil)
    #expect(
      LegacyPreferencesMigration.migrate(
        ["editorBaseFontInfo": ["size": 30]], into: defaults, targetDomain: domain) == 0)
    #expect(defaults.dictionary(forKey: "editorBaseFontInfo")?["size"] as? Int == 18)
  }
}
