import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Application preferences")
@MainActor
struct AppPreferencesTests {
  @Test("Underline defaults off, migrates enabled values and preserves explicit false")
  func underlinePreference() throws {
    let domain = "UnderlinePreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    #expect(!AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:]).underline)
    defaults.removePersistentDomain(forName: domain)
    let migrated = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["extensionUnderline": true])
    #expect(migrated.underline && migrated.renderingOptions.underline)
    migrated.underline = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["extensionUnderline": true])
    #expect(!reopened.underline && !reopened.renderingOptions.underline)
  }

  @Test("Quoted text defaults off and preserves migrated true and explicit disabled values")
  func quotedTextPreference() throws {
    let domain = "QuotePreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    #expect(!AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:]).quotedText)
    defaults.removePersistentDomain(forName: domain)
    let migrated = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["extensionQuote": true])
    #expect(migrated.quotedText && migrated.renderingOptions.quotedText)
    migrated.quotedText = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["extensionQuote": true])
    #expect(!reopened.quotedText && !reopened.renderingOptions.quotedText)
  }

  @Test("Fenced-code preference defaults on and preserves migrated false across launches")
  func fencedCodePreference() throws {
    let domain = "FencePreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(fresh.fencedCode && fresh.renderingOptions.fencedCode)
    defaults.removePersistentDomain(forName: domain)
    let migrated = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["extensionFencedCode": false])
    #expect(!migrated.fencedCode && !migrated.renderingOptions.fencedCode)
    migrated.fencedCode = true
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain, legacyValues: ["extensionFencedCode": false])
    #expect(reopened.fencedCode && reopened.renderingOptions.fencedCode)
    reopened.fencedCode = false
    #expect(!AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:]).fencedCode)
  }

  @Test("Inline dialect choices migrate independently and retain explicit disabled values")
  func inlinePreferences() throws {
    let domain = "InlinePreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["extensionHighlight": true, "extensionSuperscript": false])
    #expect(preferences.renderingOptions.highlight && !preferences.renderingOptions.superscript)
    preferences.highlight = false
    preferences.superscript = true
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["extensionHighlight": true, "extensionSuperscript": false])
    #expect(!reopened.renderingOptions.highlight && reopened.renderingOptions.superscript)
  }

  @Test("Diagram choices migrate independently and retain explicit disabled values")
  func diagramPreferences() throws {
    let domain = "DiagramPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["htmlMermaid": true, "htmlGraphviz": false])
    #expect(preferences.renderingOptions.mermaid && !preferences.renderingOptions.graphviz)
    preferences.mermaid = false
    preferences.graphviz = true
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["htmlMermaid": true, "htmlGraphviz": false])
    #expect(!reopened.renderingOptions.mermaid && reopened.renderingOptions.graphviz)
    defaults.removePersistentDomain(forName: domain)
    let fresh = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(!fresh.mermaid && !fresh.graphviz)
  }

  @Test("Math choices migrate independently and preserve explicit disabled values")
  func mathPreferences() throws {
    let domain = "MathPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["htmlMathJax": true, "htmlMathJaxInlineDollar": true])
    #expect(preferences.renderingOptions.math && preferences.renderingOptions.inlineDollarMath)
    preferences.math = false
    preferences.inlineDollarMath = false
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["htmlMathJax": true, "htmlMathJaxInlineDollar": true])
    #expect(!reopened.renderingOptions.math && !reopened.renderingOptions.inlineDollarMath)
  }

  @Test("Scroll linking defaults on and preserves an explicit disabled choice")
  func scrollLinkPreference() throws {
    let domain = "ScrollPreferencesTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    #expect(preferences.synchronizedScrolling)
    #expect(!preferences.editorOnRight)
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
        "editorUnorderedListMarkerType": 2, "editorSyncScrolling": false, "editorOnRight": true,
        "extensionTables": false, "extensionStrikethough": true,
        "htmlDetectFrontMatter": false, "htmlRendersTOC": false,
        "htmlSyntaxHighlighting": false, "htmlHighlightingThemeName": "tomorrow",
        "editorBaseFontInfo": ["name": "Menlo-Regular", "size": 18],
      ])
    #expect(preferences.editorOnRight)
    preferences.editorOnRight = false
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
    #expect(!reopened.editorOnRight)
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
