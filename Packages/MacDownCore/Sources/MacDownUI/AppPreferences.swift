import EditorCore
import Foundation
import MarkdownCore
import Observation
import PreferencesCore

@MainActor
@Observable
public final class AppPreferences {
  @ObservationIgnored private let defaults: UserDefaults

  public var tables: Bool { didSet { save(tables, "extensionTables") } }
  public var strikethrough: Bool { didSet { save(strikethrough, "extensionStrikethough") } }
  public var taskLists: Bool { didSet { save(taskLists, "htmlTaskList") } }
  public var autolinks: Bool { didSet { save(autolinks, "extensionAutolink") } }
  public var footnotes: Bool { didSet { save(footnotes, "extensionFootnotes") } }
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
  public var editorFontSize: Double { didSet { saveFont() } }
  public var editorFontName: String { didSet { saveFont() } }

  public init(
    defaults: UserDefaults = .standard, domainName: String? = nil,
    legacyValues: [String: Any]? = nil
  ) {
    self.defaults = defaults
    let domain = domainName ?? Bundle.main.bundleIdentifier ?? "local.macdown.modern"
    let legacy =
      legacyValues ?? defaults.persistentDomain(forName: "com.uranusjr.macdown")
      ?? defaults.persistentDomain(forName: "com.uranusjr.macdown-debug") ?? [:]
    LegacyPreferencesMigration.migrate(legacy, into: defaults, targetDomain: domain)
    func boolean(_ key: String, fallback: Bool) -> Bool {
      defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
    tables = boolean("extensionTables", fallback: true)
    strikethrough = boolean("extensionStrikethough", fallback: true)
    taskLists = boolean("htmlTaskList", fallback: true)
    autolinks = boolean("extensionAutolink", fallback: true)
    footnotes = boolean("extensionFootnotes", fallback: true)
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
    let font = defaults.dictionary(forKey: "editorBaseFontInfo")
    editorFontSize = min(72, max(8, (font?["size"] as? Double) ?? 14))
    editorFontName = (font?["name"] as? String) ?? "Menlo-Regular"
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
    options.tables = tables
    options.strikethrough = strikethrough
    options.taskLists = taskLists
    options.autolinks = autolinks
    options.footnotes = footnotes
    options.smartPunctuation = smartPunctuation
    options.hardLineBreaks = hardLineBreaks
    options.rawHTML = rawHTML
    return options
  }

  private func save(_ value: Bool, _ key: String) { defaults.set(value, forKey: key) }
  private func saveFont() {
    defaults.set(["name": editorFontName, "size": editorFontSize], forKey: "editorBaseFontInfo")
  }
}
