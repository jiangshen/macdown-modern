import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Application preferences")
@MainActor
struct AppPreferencesTests {
  @Test("Scroll linking defaults on and preserves an explicit disabled choice")
  func scrollLinkPreference() throws {
    let domain = "ScrollPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(preferences.synchronizedScrolling)
    preferences.synchronizedScrolling = false
    #expect(
      !AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
        .synchronizedScrolling)
  }

  @Test("Legacy choices initialize the UI and changes persist across application models")
  func persistence() throws {
    let domain = "AppPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: [
        "editorConvertTabs": true, "editorInsertPrefixInBlock": false,
        "editorAutoIncrementNumberedLists": false, "editorCompleteMatchingCharacters": true,
        "editorUnorderedListMarkerType": 2, "editorSyncScrolling": false,
        "extensionTables": false, "extensionStrikethough": true,
        "htmlDetectFrontMatter": false, "htmlRendersTOC": false,
        "htmlSyntaxHighlighting": false, "htmlHighlightingThemeName": "tomorrow",
        "editorBaseFontInfo": ["name": "Menlo-Regular", "size": 18],
      ])
    #expect(!preferences.synchronizedScrolling)
    preferences.synchronizedScrolling = true
    #expect(defaults.bool(forKey: "editorSyncScrolling"))
    #expect(preferences.editorBehavior.convertTabs)
    #expect(!preferences.editorBehavior.continueBlocks)
    #expect(!preferences.editorBehavior.incrementLists)
    #expect(preferences.editorBehavior.pairDelimiters)
    #expect(preferences.editorBehavior.unorderedMarker == "-")
    #expect(!preferences.frontMatter)
    #expect(!preferences.tableOfContents)
    preferences.frontMatter = true
    preferences.tableOfContents = true
    #expect(!preferences.codeHighlighting)
    #expect(preferences.codeTheme == .tomorrow)
    preferences.codeHighlighting = true
    preferences.codeTheme = .okaidia
    #expect(!preferences.tables)
    #expect(preferences.strikethrough)
    #expect(preferences.editorFontSize == 18)
    #expect(!preferences.remoteImages)
    #expect(!preferences.rawHTML)
    #expect(preferences.restoreDocumentsOnLaunch)
    preferences.restoreDocumentsOnLaunch = false
    #expect(!defaults.bool(forKey: "NSQuitAlwaysKeepsWindows"))
    #expect(preferences.preferDocumentTabs)
    preferences.preferDocumentTabs = false
    preferences.continueBlocks = true
    preferences.unorderedMarkerType = 1
    preferences.syntaxHighlighting = false
    preferences.alerts = false
    preferences.tables = true
    preferences.manualRendering = true
    preferences.editorFontSize = 22
    preferences.documentFont = .serif
    preferences.documentTextSize = 20
    preferences.documentFullWidth = true
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["extensionTables": false])
    #expect(reopened.synchronizedScrolling)
    #expect(!reopened.restoreDocumentsOnLaunch)
    #expect(!reopened.preferDocumentTabs)
    #expect(reopened.editorBehavior.continueBlocks)
    #expect(reopened.editorBehavior.unorderedMarker == "+")
    #expect(reopened.editorBehavior.pairDelimiters)
    #expect(!reopened.syntaxHighlighting)
    #expect(!reopened.renderingOptions.alerts)
    #expect(reopened.renderingOptions.tables)
    #expect(reopened.renderingOptions.frontMatter)
    #expect(reopened.renderingOptions.tableOfContents)
    #expect(reopened.renderingOptions.codeHighlighting)
    #expect(reopened.documentStyle.codeTheme == .okaidia)
    #expect(reopened.manualRendering)
    #expect(reopened.editorFontSize == 22)
    #expect(reopened.documentStyle.font == .serif)
    #expect(reopened.documentStyle.textSize == 20)
    #expect(reopened.documentStyle.fullWidth)
    #expect(reopened.editorFontName == "Menlo-Regular")
    #expect(!reopened.remoteImages)
  }
}
