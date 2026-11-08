import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Settings navigation and search")
@MainActor
struct SettingsTests {
  @Test("Back/forward preserves destinations and a new visit replaces the forward branch")
  func history() {
    let navigation = SettingsNavigation()
    let appearance = SettingsLocation(pane: .appearance)
    let equations = SettingsLocation(pane: .markdown, itemID: "markdownInlineMath")
    #expect(!navigation.canGoBack && !navigation.canGoForward)
    navigation.visit(appearance)
    navigation.visit(equations)
    let revealRequest = navigation.revealRequest
    navigation.visit(equations)
    #expect(navigation.revealRequest == revealRequest + 1)
    navigation.goBack()
    #expect(navigation.location == appearance && navigation.canGoForward)
    navigation.goForward()
    #expect(navigation.location == equations)
    navigation.goBack()
    navigation.visit(.init(pane: .editor))
    #expect(!navigation.canGoForward)
    navigation.goBack()
    #expect(navigation.location == appearance)
    navigation.goBack()
    navigation.goBack()
    #expect(navigation.location.pane == .general && !navigation.canGoBack)
  }

  @Test("Search requires every word and finds descriptions, categories and synonyms")
  func search() throws {
    #expect(SettingsCatalog.search(" \n ").isEmpty)
    #expect(SettingsCatalog.search("no such preference xyz").isEmpty)
    #expect(SettingsCatalog.search("MARKDOWN fence").map(\.id) == ["markdownFencedCode"])
    #expect(SettingsCatalog.search("inline equations").map(\.id) == ["markdownInlineMath"])
    #expect(SettingsCatalog.search("intraword").map(\.id) == ["markdownIntraword"])
    #expect(SettingsCatalog.search("source theme").map(\.id) == ["editorFontName", "editorTheme"])
    #expect(
      SettingsCatalog.search("import style").map(\.id) == [
        "importReadingStyle", "importEditorTheme",
      ])
    #expect(SettingsCatalog.search("checkbox").map(\.id) == ["markdownTaskLists"])
    #expect(SettingsCatalog.search("code label").map(\.id) == ["previewCodeLabel"])
    #expect(SettingsCatalog.search("code line numbers").map(\.id) == ["previewCodeLineNumbers"])
    #expect(SettingsCatalog.search("privacy network").map(\.id) == ["previewRemoteImages"])
    let result = try #require(SettingsCatalog.search("sync").first)
    #expect(result.location == .init(pane: .editor, itemID: "synchronizedScrolling"))
    let entries = SettingsCatalog.sections.flatMap(\.entries)
    #expect(Set(entries.map(\.id)).count == entries.count)
    #expect(entries.count == 53)
  }

  @Test("Settings switches persist through the existing preference model")
  func persistence() throws {
    let domain = "SettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    var expected: [(ReferenceWritableKeyPath<AppPreferences, Bool>, Bool)] = []
    for entry in SettingsCatalog.sections.flatMap(\.entries) {
      if case .toggle(let keyPath) = entry.control {
        let value = !preferences[keyPath: keyPath]
        preferences[keyPath: keyPath] = value
        expected.append((keyPath, value))
      }
    }
    let reopened = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    for (keyPath, value) in expected { #expect(reopened[keyPath: keyPath] == value) }
  }
}
