import DocumentCore
import Foundation
import PreferencesCore
import RenderingCore
import Testing

@testable import SnowfolioUI

@Suite("Reading appearance persistence", .serialized)
@MainActor
struct ReadingStyleLibraryTests {
  private func defaults() throws -> (UserDefaults, String) {
    let domain = "ReadingStyleTests." + UUID().uuidString
    return (try #require(UserDefaults(suiteName: domain)), domain)
  }

  @Test(
    "Fresh and existing Snowfolio profiles keep notebook; first MacDown migration preserves its style"
  )
  func migration() async throws {
    let (defaults, domain) = try defaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(fresh.readingStyles.selection == "snowfolio")
    #expect(fresh.documentStyle.presentation == .notebook && fresh.readingStyles.isReady)
    defaults.removePersistentDomain(forName: domain)
    defaults.set(1, forKey: LegacyPreferencesMigration.markerKey)
    defaults.set("GitHub2", forKey: "htmlStyleName")
    let existing = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(existing.readingStyles.selection == "snowfolio")
    defaults.removePersistentDomain(forName: domain)
    let migrated = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["htmlStyleName": "Clearness Dark.css"],
      readingStyleRepository: ReadingStyleRepository())
    #expect(migrated.readingStyles.selection == "legacy:Clearness Dark")
    #expect(!migrated.readingStyles.isReady)
    await migrated.readingStyles.loadIfNeeded()
    #expect(migrated.readingStyles.isReady && migrated.documentStyle.usesBodyRoot)
    #expect(migrated.documentStyle.css.contains("#282a36"))
    defaults.removePersistentDomain(forName: domain)
    let noStyle = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["extensionTables": true])
    #expect(noStyle.readingStyles.selection == "none" && noStyle.documentStyle.css.isEmpty)
    defaults.removePersistentDomain(forName: domain)
    let emptyStyle = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["htmlStyleName": ""])
    #expect(emptyStyle.readingStyles.selection == "none" && emptyStyle.documentStyle.css.isEmpty)
    defaults.removePersistentDomain(forName: domain)
    defaults.set("GitHub2", forKey: "htmlStyleName")
    let existingStyle = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: [:],
      readingStyleRepository: ReadingStyleRepository())
    #expect(existingStyle.readingStyles.selection == "legacy:GitHub2")
  }

  @Test(
    "Saved sheets reach immutable manual-preview export snapshots and unavailable choices retain the last style"
  )
  func snapshots() async throws {
    let (defaults, domain) = try defaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    preferences.manualRendering = true
    let document = MarkdownDocument(contents: TextFileContents(text: "# Title"))
    let export = DocumentExportController()
    export.document = document
    export.preferences = preferences
    for entry in ReadingStyleEntry.all {
      await preferences.readingStyles.select(entry.id)
      let snapshot = try #require(export.snapshot())
      #expect(snapshot.style == preferences.documentStyle)
      let saved = snapshot.style
      await preferences.readingStyles.select("snowfolio")
      #expect(snapshot.style == saved)
      await preferences.readingStyles.select(entry.id)
      let reopened = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
      await reopened.readingStyles.loadIfNeeded()
      #expect(reopened.documentStyle == preferences.documentStyle)
    }
    let last = preferences.documentStyle
    await preferences.readingStyles.select("legacy:Custom missing")
    #expect(preferences.readingStyles.message != nil)
    #expect(preferences.readingStyles.selection == "legacy:Custom missing")
    #expect(preferences.documentStyle == last)
    #expect(document.text == "# Title" && document.revision == 0)
  }
}
