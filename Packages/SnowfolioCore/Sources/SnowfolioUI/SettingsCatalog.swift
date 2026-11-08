import Foundation
import Observation

/// The same catalog supplies labels, search results and the actual preference controls.
/// Persisted values remain owned by AppPreferences, including its migration keys.
enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
  case general, appearance, editor, markdown, privacy
  var id: Self { self }
  var title: String {
    switch self {
    case .general: "General"
    case .appearance: "Appearance"
    case .editor: "Editor"
    case .markdown: "Markdown"
    case .privacy: "Privacy & Security"
    }
  }
  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .appearance: "circle.lefthalf.filled"
    case .editor: "keyboard"
    case .markdown: "text.document"
    case .privacy: "hand.raised.fill"
    }
  }
}

struct SettingsLocation: Hashable {
  var pane: SettingsPane
  var itemID: String? = nil
}

@MainActor
@Observable
final class SettingsNavigation {
  private(set) var location = SettingsLocation(pane: .general)
  private var history = [SettingsLocation(pane: .general)]
  private var index = 0
  var query = ""
  private(set) var revealRequest = 0
  var canGoBack: Bool { index > 0 }
  var canGoForward: Bool { index + 1 < history.count }

  func visit(_ destination: SettingsLocation) {
    revealRequest += 1
    guard destination != location else { return }
    history = Array(history.prefix(index + 1))
    history.append(destination)
    // Keep a long-lived Settings window's history bounded.
    if history.count > 100 { history.removeFirst() }
    index = history.count - 1
    location = destination
  }

  func goBack() {
    guard canGoBack else { return }
    index -= 1
    revealRequest += 1
    location = history[index]
  }

  func goForward() {
    guard canGoForward else { return }
    index += 1
    revealRequest += 1
    location = history[index]
  }
}

struct SettingsEntry: Identifiable {
  enum Control {
    case toggle(ReferenceWritableKeyPath<AppPreferences, Bool>)
    case documentFont, documentSize, codeTheme, editorFont, editorSize, listMarker, emphasisPolicy,
      codeBlockAccessory
    case editorTheme, importEditorTheme, readingStyle, importReadingStyle, htmlTemplate
  }
  let id: String
  let title: String
  var detail = ""
  var keywords = ""
  let control: Control
}

struct SettingsSection: Identifiable {
  let pane: SettingsPane
  let title: String
  let entries: [SettingsEntry]
  var id: String { pane.rawValue + "." + title }
}

struct SettingsSearchResult: Identifiable {
  let pane: SettingsPane
  let entry: SettingsEntry
  var id: String { entry.id }
  var location: SettingsLocation { .init(pane: pane, itemID: entry.id) }
}

@MainActor
enum SettingsCatalog {
  static let sections: [SettingsSection] = [
    .init(
      pane: .general, title: "Windows",
      entries: [
        .init(
          id: "restoreDocumentsOnLaunch", title: "Restore open documents when reopening",
          detail: "Pick up where you left off when you open Snowfolio again.",
          keywords: "startup launch session", control: .toggle(\.restoreDocumentsOnLaunch)),
        .init(
          id: "preferDocumentTabs", title: "Prefer tabs for new documents",
          detail:
            "Turn off to follow your Mac’s window setting. You can move tabs into separate windows.",
          keywords: "multiple files windows", control: .toggle(\.preferDocumentTabs)),
      ]),
    .init(
      pane: .appearance, title: "Reading",
      entries: [
        .init(
          id: "readingStyle", title: "Document style",
          detail: "Appearance for the preview and styled exports.",
          keywords: "css stylesheet reading legacy", control: .readingStyle),
        .init(
          id: "importReadingStyle", title: "Custom styles",
          detail: "Import CSS and supporting files, or open the styles folder.",
          keywords: "css import folder stylesheet fonts images reload", control: .importReadingStyle
        ),
        .init(
          id: "documentFont", title: "Font",
          detail: "Typography for the Snowfolio document style and its styled exports.",
          control: .documentFont),
        .init(id: "documentTextSize", title: "Text size", control: .documentSize),
        .init(
          id: "documentFullWidth", title: "Full width",
          detail: "Let the Snowfolio style fill the available reading width.",
          control: .toggle(\.documentFullWidth)),
      ]),
    .init(
      pane: .appearance, title: "Export",
      entries: [
        .init(
          id: "htmlTemplate", title: "HTML template",
          detail: "Document structure for HTML exports.", keywords: "default recovery",
          control: .htmlTemplate)
      ]),
    .init(
      pane: .appearance, title: "Code Blocks",
      entries: [
        .init(
          id: "previewCodeHighlighting", title: "Highlight code",
          detail: "Use syntax colors in code blocks.", control: .toggle(\.codeHighlighting)),
        .init(
          id: "previewCodeTheme", title: "Code theme", keywords: "color scheme prism",
          control: .codeTheme),
        .init(
          id: "previewCodeLineNumbers", title: "Show code line numbers",
          detail: "Number code lines in reading previews and exports.", keywords: "gutter fence",
          control: .toggle(\.codeLineNumbers)),
        .init(
          id: "previewCodeLabel", title: "Code label",
          detail: "Custom labels use a colon in the opening fence, such as swift:File.swift.",
          keywords: "language information accessory filename", control: .codeBlockAccessory),
      ]),
    .init(
      pane: .editor, title: "Typography",
      entries: [
        .init(
          id: "editorSyntaxHighlighting", title: "Highlight Markdown syntax",
          control: .toggle(\.syntaxHighlighting)),
        .init(
          id: "editorFontName", title: "Font name",
          detail: "Themes can override the source editor’s font.",
          control: .editorFont),
        .init(id: "editorFontSize", title: "Font size", control: .editorSize),
        .init(
          id: "editorTheme", title: "Theme", detail: "Colors and typography for Markdown source.",
          keywords: "style color palette theme", control: .editorTheme),
        .init(
          id: "importEditorTheme", title: "Custom themes", detail: "Import a .style file.",
          keywords: "style import theme", control: .importEditorTheme),
      ]),
    .init(
      pane: .editor, title: "Typing",
      entries: [
        .init(
          id: "editorConvertTabs", title: "Use spaces for tabs", keywords: "indent indentation",
          control: .toggle(\.convertTabs)),
        .init(
          id: "editorContinueBlocks", title: "Continue lists and quotes",
          detail: "Keep the current block when you press Return.",
          control: .toggle(\.continueBlocks)),
        .init(
          id: "editorIncrementLists", title: "Increment numbered lists",
          control: .toggle(\.incrementLists)),
        .init(
          id: "editorPairDelimiters", title: "Complete paired delimiters",
          keywords: "brackets parentheses matching characters", control: .toggle(\.pairDelimiters)),
        .init(
          id: "editorListMarker", title: "Unordered list marker", keywords: "bullet asterisk dash",
          control: .listMarker),
      ]),
    .init(
      pane: .editor, title: "Preview",
      entries: [
        .init(
          id: "previewFollowsEditorFont", title: "Scale preview with editor font",
          control: .toggle(\.previewFollowsEditorFont)),
        .init(
          id: "editorOnRight", title: "Place editor on the right", control: .toggle(\.editorOnRight)
        ),
        .init(
          id: "synchronizedScrolling", title: "Link editor and preview scrolling",
          keywords: "sync synchronized", control: .toggle(\.synchronizedScrolling)),
        .init(
          id: "manualRendering", title: "Render manually",
          detail: "Update the preview only when you choose Render.", keywords: "automatic refresh",
          control: .toggle(\.manualRendering)),
      ]),
    .init(
      pane: .markdown, title: "Document Structure",
      entries: [
        .init(
          id: "markdownFrontMatter", title: "Show YAML front matter as properties",
          control: .toggle(\.frontMatter)),
        .init(
          id: "markdownTableOfContents", title: "Table of contents",
          detail: "Expand [TOC] into a list of document headings.",
          control: .toggle(\.tableOfContents)),
        .init(
          id: "markdownAlerts", title: "Notes, tips and warnings", keywords: "callout alerts emoji",
          control: .toggle(\.alerts)),
      ]),
    .init(
      pane: .markdown, title: "Code & Tables",
      entries: [
        .init(
          id: "markdownFencedCode", title: "Fenced code blocks",
          detail:
            "Recognize backtick and tilde fences as code. Indented code blocks work with this off.",
          control: .toggle(\.fencedCode)),
        .init(id: "markdownTables", title: "Tables", control: .toggle(\.tables)),
        .init(
          id: "markdownTaskLists", title: "Task lists", keywords: "checkbox todo",
          control: .toggle(\.taskLists)),
      ]),
    .init(
      pane: .markdown, title: "Text",
      entries: [
        .init(
          id: "markdownStrikethrough", title: "Strikethrough", keywords: "delete strike",
          control: .toggle(\.strikethrough)),
        .init(
          id: "markdownAutolinks", title: "Automatic links", keywords: "url autolink",
          control: .toggle(\.autolinks)),
        .init(id: "markdownFootnotes", title: "Footnotes", control: .toggle(\.footnotes)),
        .init(
          id: "markdownIntraword", title: "Formatting inside words",
          detail: "Choose whether markers can start within a word, as in word*emphasis*.",
          keywords: "intra word intraword emphasis underscore bold highlight strikethrough",
          control: .emphasisPolicy),
        .init(
          id: "markdownUnderline", title: "Underlines",
          detail: "Use _single underscores_ for underlined text.", control: .toggle(\.underline)),
        .init(
          id: "markdownHighlight", title: "Highlights", detail: "Mark text with ==double equals==.",
          control: .toggle(\.highlight)),
        .init(
          id: "markdownSuperscript", title: "Superscripts",
          detail: "Raise text with ^text or ^(text).", control: .toggle(\.superscript)),
        .init(
          id: "markdownQuote", title: "Quoted text",
          detail: "Render \"quoted text\" as a quotation.", control: .toggle(\.quotedText)),
        .init(
          id: "markdownSmartPunctuation", title: "Smart punctuation",
          keywords: "quotes dashes ellipses typography", control: .toggle(\.smartPunctuation)),
        .init(
          id: "markdownHardLineBreaks", title: "Break lines at source newlines",
          keywords: "hard wrap", control: .toggle(\.hardLineBreaks)),
      ]),
    .init(
      pane: .markdown, title: "Diagrams & Equations",
      entries: [
        .init(id: "markdownMermaid", title: "Render Mermaid diagrams", control: .toggle(\.mermaid)),
        .init(
          id: "markdownGraphviz", title: "Render Graphviz diagrams", keywords: "dot",
          control: .toggle(\.graphviz)),
        .init(
          id: "markdownMath", title: "Render equations",
          detail:
            "Use math code blocks or $$…$$ for display equations. Unsupported equations stay visible.",
          keywords: "math latex katex", control: .toggle(\.math)),
        .init(
          id: "markdownInlineMath", title: "Single dollar signs for inline equations",
          detail: "Recognize $…$ inside a paragraph. Requires Render equations.",
          keywords: "math latex katex", control: .toggle(\.inlineDollarMath)),
      ]),
    .init(
      pane: .privacy, title: "Document Content",
      entries: [
        .init(
          id: "previewRawHTML", title: "Show HTML in Markdown",
          detail: "Scripts and embedded frames stay disabled in the preview.",
          control: .toggle(\.rawHTML)),
        .init(
          id: "previewRemoteImages", title: "Load remote images",
          detail:
            "Remote images contact the sites hosting them. Local images in the document’s folder work with this off.",
          keywords: "network internet privacy", control: .toggle(\.remoteImages)),
      ]),
  ]

  static func sections(in pane: SettingsPane) -> [SettingsSection] {
    sections.filter { $0.pane == pane }
  }

  static func search(_ query: String) -> [SettingsSearchResult] {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return [] }
    return sections.flatMap { section in
      section.entries.compactMap { entry in
        let text = [section.pane.title, section.title, entry.title, entry.detail, entry.keywords]
          .joined(separator: " ")
        guard words.allSatisfy({ text.localizedStandardContains($0) }) else { return nil }
        return SettingsSearchResult(pane: section.pane, entry: entry)
      }
    }
  }
}
