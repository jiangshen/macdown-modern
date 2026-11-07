import CodeHighlightCore
import EditorCore
import Foundation
import MarkdownCore
import Observation
import PreferencesCore
import RenderingCore

@MainActor
@Observable
public final class AppPreferences {
  @ObservationIgnored private let defaults: UserDefaults
  public let editorThemes: EditorThemeLibrary

  public var restoreDocumentsOnLaunch: Bool {
    didSet { save(restoreDocumentsOnLaunch, "NSQuitAlwaysKeepsWindows") }
  }
  public var preferDocumentTabs: Bool { didSet { save(preferDocumentTabs, "preferDocumentTabs") } }
  public var previewFollowsEditorFont: Bool {
    didSet { save(previewFollowsEditorFont, "previewZoomRelativeToBaseFontSize") }
  }
  public var editorOnRight: Bool { didSet { save(editorOnRight, "editorOnRight") } }
  public var synchronizedScrolling: Bool {
    didSet { save(synchronizedScrolling, "editorSyncScrolling") }
  }
  public var syntaxHighlighting: Bool {
    didSet { save(syntaxHighlighting, "editorSyntaxHighlighting") }
  }
  public var frontMatter: Bool { didSet { save(frontMatter, "htmlDetectFrontMatter") } }
  public var tableOfContents: Bool { didSet { save(tableOfContents, "htmlRendersTOC") } }
  public var codeHighlighting: Bool { didSet { save(codeHighlighting, "htmlSyntaxHighlighting") } }
  public var codeTheme: CodeHighlightTheme {
    didSet { defaults.set(codeTheme.rawValue, forKey: "htmlHighlightingThemeName") }
  }
  public var mermaid: Bool { didSet { save(mermaid, "htmlMermaid") } }
  public var graphviz: Bool { didSet { save(graphviz, "htmlGraphviz") } }
  public var math: Bool { didSet { save(math, "htmlMathJax") } }
  public var inlineDollarMath: Bool { didSet { save(inlineDollarMath, "htmlMathJaxInlineDollar") } }
  public var alerts: Bool { didSet { save(alerts, "extensionAlerts") } }
  public var tables: Bool { didSet { save(tables, "extensionTables") } }
  public var strikethrough: Bool { didSet { save(strikethrough, "extensionStrikethough") } }
  public var taskLists: Bool { didSet { save(taskLists, "htmlTaskList") } }
  public var autolinks: Bool { didSet { save(autolinks, "extensionAutolink") } }
  public var footnotes: Bool { didSet { save(footnotes, "extensionFootnotes") } }
  public var fencedCode: Bool { didSet { save(fencedCode, "extensionFencedCode") } }
  public var highlight: Bool { didSet { save(highlight, "extensionHighlight") } }
  public var emphasisPolicy: MarkdownEmphasisPolicy { didSet { saveEmphasisPolicy() } }
  public var underline: Bool { didSet { save(underline, "extensionUnderline") } }
  public var quotedText: Bool { didSet { save(quotedText, "extensionQuote") } }
  public var superscript: Bool { didSet { save(superscript, "extensionSuperscript") } }
  public var smartPunctuation: Bool { didSet { save(smartPunctuation, "extensionSmartyPants") } }
  public var hardLineBreaks: Bool { didSet { save(hardLineBreaks, "htmlHardWrap") } }
  public var rawHTML: Bool { didSet { save(rawHTML, "previewRenderRawHTML") } }
  public var remoteImages: Bool { didSet { save(remoteImages, "previewLoadRemoteImages") } }
  public var manualRendering: Bool { didSet { save(manualRendering, "markdownManualRender") } }
  public var convertTabs: Bool { didSet { save(convertTabs, "editorConvertTabs") } }
  public var continueBlocks: Bool { didSet { save(continueBlocks, "editorInsertPrefixInBlock") } }
  public var incrementLists: Bool {
    didSet { save(incrementLists, "editorAutoIncrementNumberedLists") }
  }
  public var pairDelimiters: Bool {
    didSet { save(pairDelimiters, "editorCompleteMatchingCharacters") }
  }
  public var unorderedMarkerType: Int {
    didSet { defaults.set(unorderedMarkerType, forKey: "editorUnorderedListMarkerType") }
  }
  public var documentFont: DocumentStyle.Font {
    didSet { defaults.set(documentFont.rawValue, forKey: "documentFont") }
  }
  public var documentTextSize: Double {
    didSet { defaults.set(documentStyle.textSize, forKey: "documentTextSize") }
  }
  public var documentFullWidth: Bool { didSet { save(documentFullWidth, "documentFullWidth") } }
  public var editorFontSize: Double { didSet { saveFont() } }
  public var editorFontName: String { didSet { saveFont() } }

  public init(
    defaults: UserDefaults = .standard, domainName: String? = nil,
    legacyValues: [String: Any]? = nil, editorThemeRepository: EditorThemeRepository = .standard
  ) {
    self.defaults = defaults
    // App-scoped fallback only; explicit app, system and launch-argument choices win.
    defaults.register(defaults: ["NSQuitAlwaysKeepsWindows": true])
    let domain = domainName ?? Bundle.main.bundleIdentifier ?? "local.macdown.modern"
    let legacy =
      legacyValues ?? defaults.persistentDomain(forName: "com.uranusjr.macdown")
      ?? defaults.persistentDomain(forName: "com.uranusjr.macdown-debug") ?? [:]
    LegacyPreferencesMigration.migrate(legacy, into: defaults, targetDomain: domain)
    func boolean(_ key: String, fallback: Bool) -> Bool {
      defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
    restoreDocumentsOnLaunch = boolean("NSQuitAlwaysKeepsWindows", fallback: true)
    preferDocumentTabs = boolean("preferDocumentTabs", fallback: true)
    frontMatter = boolean("htmlDetectFrontMatter", fallback: true)
    tableOfContents = boolean("htmlRendersTOC", fallback: true)
    codeHighlighting = boolean("htmlSyntaxHighlighting", fallback: true)
    codeTheme = .legacyName(defaults.string(forKey: "htmlHighlightingThemeName"))
    previewFollowsEditorFont = boolean("previewZoomRelativeToBaseFontSize", fallback: false)
    editorOnRight = boolean("editorOnRight", fallback: false)
    synchronizedScrolling = boolean("editorSyncScrolling", fallback: true)
    syntaxHighlighting = boolean("editorSyntaxHighlighting", fallback: true)
    mermaid = boolean("htmlMermaid", fallback: false)
    graphviz = boolean("htmlGraphviz", fallback: false)
    math = boolean("htmlMathJax", fallback: false)
    inlineDollarMath = boolean("htmlMathJaxInlineDollar", fallback: false)
    alerts = boolean("extensionAlerts", fallback: true)
    tables = boolean("extensionTables", fallback: true)
    strikethrough = boolean("extensionStrikethough", fallback: true)
    taskLists = boolean("htmlTaskList", fallback: true)
    autolinks = boolean("extensionAutolink", fallback: true)
    footnotes = boolean("extensionFootnotes", fallback: true)
    fencedCode = boolean("extensionFencedCode", fallback: true)
    highlight = boolean("extensionHighlight", fallback: false)
    superscript = boolean("extensionSuperscript", fallback: false)
    if let raw = defaults.string(forKey: "markdownEmphasisPolicy"),
      let saved = MarkdownEmphasisPolicy(rawValue: raw)
    {
      emphasisPolicy = saved
    } else if defaults.object(forKey: "extensionIntraEmphasis") != nil {
      emphasisPolicy =
        defaults.bool(forKey: "extensionIntraEmphasis")
        ? .allowWithinWords : .avoidWithinWords
    } else {
      emphasisPolicy = .standard
    }
    underline = boolean("extensionUnderline", fallback: false)
    quotedText = boolean("extensionQuote", fallback: false)
    smartPunctuation = boolean("extensionSmartyPants", fallback: false)
    hardLineBreaks = boolean("htmlHardWrap", fallback: false)
    rawHTML = boolean("previewRenderRawHTML", fallback: false)
    remoteImages = boolean("previewLoadRemoteImages", fallback: false)
    manualRendering = boolean("markdownManualRender", fallback: false)
    convertTabs = boolean("editorConvertTabs", fallback: false)
    continueBlocks = boolean("editorInsertPrefixInBlock", fallback: true)
    incrementLists = boolean("editorAutoIncrementNumberedLists", fallback: true)
    pairDelimiters = boolean("editorCompleteMatchingCharacters", fallback: false)
    unorderedMarkerType = defaults.integer(forKey: "editorUnorderedListMarkerType")
    documentFont =
      DocumentStyle.Font(rawValue: defaults.string(forKey: "documentFont") ?? "") ?? .standard
    documentTextSize =
      DocumentStyle(
        textSize: (defaults.object(forKey: "documentTextSize") as? Double) ?? 16
      ).textSize
    documentFullWidth = boolean("documentFullWidth", fallback: false)
    let font = defaults.dictionary(forKey: "editorBaseFontInfo")
    editorFontSize = min(72, max(8, (font?["size"] as? Double) ?? 14))
    editorFontName = (font?["name"] as? String) ?? "Menlo-Regular"
    editorThemes = EditorThemeLibrary(defaults: defaults, repository: editorThemeRepository)
  }

  public var documentStyle: DocumentStyle {
    DocumentStyle(
      font: documentFont, textSize: documentTextSize, fullWidth: documentFullWidth,
      codeTheme: codeTheme)
  }

  public var editorBehavior: EditorBehavior {
    var behavior = EditorBehavior()
    behavior.convertTabs = convertTabs
    behavior.continueBlocks = continueBlocks
    behavior.incrementLists = incrementLists
    behavior.pairDelimiters = pairDelimiters
    behavior.unorderedMarker = unorderedMarkerType == 1 ? "+" : unorderedMarkerType == 2 ? "-" : "*"
    return behavior
  }

  public var renderingOptions: MarkdownRenderingOptions {
    var options = MarkdownRenderingOptions()
    options.frontMatter = frontMatter
    options.tableOfContents = tableOfContents
    options.codeHighlighting = codeHighlighting
    options.mermaid = mermaid
    options.graphviz = graphviz
    options.math = math
    options.inlineDollarMath = inlineDollarMath
    options.alerts = alerts
    options.tables = tables
    options.strikethrough = strikethrough
    options.taskLists = taskLists
    options.autolinks = autolinks
    options.footnotes = footnotes
    options.fencedCode = fencedCode
    options.highlight = highlight
    options.superscript = superscript
    options.emphasisPolicy = emphasisPolicy
    options.underline = underline
    options.quotedText = quotedText
    options.smartPunctuation = smartPunctuation
    options.hardLineBreaks = hardLineBreaks
    options.rawHTML = rawHTML
    return options
  }

  private func saveEmphasisPolicy() {
    defaults.set(emphasisPolicy.rawValue, forKey: "markdownEmphasisPolicy")
    if emphasisPolicy != .standard {
      defaults.set(emphasisPolicy == .allowWithinWords, forKey: "extensionIntraEmphasis")
    }
  }

  private func save(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
  private func saveFont() {
    defaults.set(["name": editorFontName, "size": editorFontSize], forKey: "editorBaseFontInfo")
  }
}
