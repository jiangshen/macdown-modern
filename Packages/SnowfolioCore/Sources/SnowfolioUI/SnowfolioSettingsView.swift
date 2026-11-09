import AppKit
import CodeHighlightCore
import MarkdownCore
import RenderingCore
import SwiftUI

struct SnowfolioSettingsView: View {
  let preferences: AppPreferences
  @Bindable var navigation: SettingsNavigation

  private var searching: Bool {
    !navigation.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  private var selection: Binding<SettingsLocation?> {
    Binding {
      searching ? navigation.location : SettingsLocation(pane: navigation.location.pane)
    } set: { destination in
      if let destination { navigation.visit(destination) }
    }
  }

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      sidebar
        .frame(width: SettingsWindowLayout.sidebarWidth)
        .navigationSplitViewColumnWidth(SettingsWindowLayout.sidebarWidth)
        .toolbar(removing: .sidebarToggle)
    } detail: {
      SettingsDetailPane(preferences: preferences, navigation: navigation)
        .navigationTitle(navigation.location.pane.title)
        .toolbar {
          ToolbarItemGroup(placement: .navigation) {
            Button("Go Back", systemImage: "chevron.backward", action: navigation.goBack)
              .labelStyle(.iconOnly)
              .disabled(!navigation.canGoBack)
              .help("Go Back")
              .accessibilityIdentifier("settingsGoBack")
              .keyboardShortcut("[", modifiers: .command)
            Button("Go Forward", systemImage: "chevron.forward", action: navigation.goForward)
              .labelStyle(.iconOnly)
              .disabled(!navigation.canGoForward)
              .help("Go Forward")
              .accessibilityIdentifier("settingsGoForward")
              .keyboardShortcut("]", modifiers: .command)
          }
        }
    }
    .navigationSplitViewStyle(.balanced)
    .frame(
      minWidth: SettingsWindowLayout.minimumContentSize.width,
      idealWidth: SettingsWindowLayout.minimumContentSize.width,
      minHeight: SettingsWindowLayout.minimumContentSize.height,
      idealHeight: SettingsWindowLayout.minimumContentSize.height)
  }

  private var sidebar: some View {
    VStack(spacing: 0) {
      SettingsSearchField(query: $navigation.query)
        .frame(height: 28)
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 8)
      List(selection: selection) {
        if searching {
          ForEach(SettingsCatalog.search(navigation.query)) { result in
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(result.entry.title)
                  .lineLimit(nil)
                  .fixedSize(horizontal: false, vertical: true)
                Text(result.pane.title).foregroundStyle(.secondary)
              }
            } icon: {
              SettingsPaneIcon(pane: result.pane)
            }
            .tag(result.location)
            .accessibilityIdentifier("settingsResult." + result.id)
          }
        } else {
          Section {
            HStack(spacing: 10) {
              Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 36, height: 36)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 2) {
                Text("Snowfolio").font(.headline)
                Text("Settings").foregroundStyle(.secondary)
              }
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .selectionDisabled()
          }
          Section {
            ForEach(SettingsPane.allCases) { pane in
              Label {
                Text(pane.title)
              } icon: {
                SettingsPaneIcon(pane: pane)
              }
              .foregroundStyle(.primary)
              .tag(SettingsLocation(pane: pane))
              .accessibilityIdentifier("settingsPane." + pane.rawValue)
            }
          }
        }
      }
      .listStyle(.sidebar)
      .scrollEdgeEffectStyle(.soft, for: .all)
      .overlay {
        if searching && SettingsCatalog.search(navigation.query).isEmpty {
          ContentUnavailableView.search(text: navigation.query)
        }
      }
      .accessibilityIdentifier("settingsSidebar")
    }
    .navigationTitle("Settings")
  }
}

private struct SettingsPaneIcon: View {
  let pane: SettingsPane
  var body: some View {
    Image(systemName: pane.symbol)
      .symbolRenderingMode(.hierarchical)
      .frame(width: 24, height: 24)
      .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
      .accessibilityHidden(true)
  }
}

private struct SettingsDetailPane: View {
  let preferences: AppPreferences
  @Bindable var navigation: SettingsNavigation

  var body: some View {
    Form {
      if navigation.location.pane == .general {
        Section {
          VStack(spacing: 10) {
            SettingsPaneIcon(pane: .general).scaleEffect(1.8).padding(14)
            Text("General").font(.title.bold())
            Text(
              "Choose how Snowfolio opens documents, arranges your windows and supports your writing experience."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity).padding(.vertical, 10)
        }
      }
      ForEach(SettingsCatalog.sections(in: navigation.location.pane)) { section in
        Section(section.title) {
          ForEach(section.entries) { entry in
            SettingsPreferenceRow(entry: entry, preferences: preferences)
              .background(
                SettingsRowReveal(
                  request: navigation.location.itemID == entry.id ? navigation.revealRequest : nil))
          }
        }
      }
      if navigation.location.pane == .general {
        Section {
          ForEach(SettingsPane.allCases.filter { $0 != .general }) { pane in
            Button {
              navigation.visit(.init(pane: pane))
            } label: {
              HStack {
                SettingsPaneIcon(pane: pane)
                Text(pane.title)
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsLink." + pane.rawValue)
          }
        }
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    // Grouped Form contributes 20 pt here; match System Settings’ 12 pt toolbar inset.
    .contentMargins(.top, -8, for: .scrollContent)
    .scrollEdgeEffectStyle(.soft, for: .all)
    .id(navigation.location.pane)
    .background(.background)
    .accessibilityIdentifier("settingsDetail." + navigation.location.pane.rawValue)
  }
}

private struct SettingsPreferenceRow: View {
  let entry: SettingsEntry
  @Bindable var preferences: AppPreferences

  var body: some View {
    switch entry.control {
    case .editorMetric, .editorTheme, .importEditorTheme, .readingStyle, .importReadingStyle,
      .htmlTemplate,
      .assetFolder, .commandLineTool:
      // Compound rows own distinct identifiers and labels on their controls.
      // A row-wide modifier would cascade to Import and Reload alike.
      control
    default:
      control
        .accessibilityIdentifier(entry.id)
        .accessibilityLabel(entry.title)
        .accessibilityHint(entry.detail)
        .disabled(entry.id == "markdownInlineMath" && !preferences.math)
        .disabled(entry.id == "writingStatisticsMode" && !preferences.showWritingStatistics)
        .disabled(entry.id == "editorMaximumWidth" && !preferences.editorLayout.widthLimited)
        .disabled(
          ["documentFont", "documentTextSize", "documentFullWidth"].contains(entry.id)
            && preferences.readingStyles.presentation != .notebook)
    }
  }

  @ViewBuilder private var control: some View {
    switch entry.control {
    case .editorMetric(let keyPath, let limits, let step):
      let value = Binding(
        get: { preferences[keyPath: keyPath] },
        set: { preferences[keyPath: keyPath] = $0 })
      LabeledContent {
        HStack(spacing: 6) {
          TextField("", value: value, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing).frame(width: 70)
            .accessibilityIdentifier(entry.id).accessibilityLabel(entry.title)
            .accessibilityHint("Value in points")
          Text("pt").foregroundStyle(.secondary).accessibilityHidden(true)
          Stepper("", value: value, in: limits, step: step)
            .labelsHidden().fixedSize().accessibilityLabel(entry.title)
            .accessibilityIdentifier(entry.id + "Stepper")
        }
      } label: {
        caption
      }
      .disabled(entry.id == "editorMaximumWidth" && !preferences.editorLayout.widthLimited)
    case .toggle(let keyPath):
      Toggle(
        isOn: Binding(
          get: { preferences[keyPath: keyPath] },
          set: { preferences[keyPath: keyPath] = $0 }
        )
      ) { caption }
      .toggleStyle(.switch)
    case .writingStatisticsMode:
      Picker(selection: $preferences.writingStatisticsMode) {
        ForEach(WritingStatisticsMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      } label: {
        caption
      }
      .pickerStyle(.menu)
    case .emphasisPolicy:
      Picker(selection: $preferences.emphasisPolicy) {
        Text("Standard Markdown").tag(MarkdownEmphasisPolicy.standard)
        Text("Allow").tag(MarkdownEmphasisPolicy.allowWithinWords)
        Text("Avoid").tag(MarkdownEmphasisPolicy.avoidWithinWords)
      } label: {
        caption
      }
      .pickerStyle(.menu)
    case .htmlTemplate:
      LabeledContent {
        if preferences.htmlTemplateName == HTMLExportTemplate.defaultName {
          Text("Default").foregroundStyle(.secondary).accessibilityIdentifier("htmlTemplateStatus")
        } else {
          VStack(alignment: .trailing, spacing: 6) {
            Text("Unavailable: \(preferences.htmlTemplateName)")
              .foregroundStyle(.secondary).lineLimit(2)
              .accessibilityIdentifier("htmlTemplateStatus")
            Button("Use Default") { preferences.htmlTemplateName = HTMLExportTemplate.defaultName }
              .accessibilityIdentifier("resetHTMLTemplate")
              .accessibilityHint("Use the bundled HTML template for exports.")
          }
        }
      } label: {
        caption
      }
    case .commandLineTool:
      CommandLineToolSettingsControl(model: preferences.commandLineTool)
    case .assetFolder:
      DocumentAssetFolderControl(folder: preferences.assetFolder)
    case .readingStyle:
      ReadingStylePicker(library: preferences.readingStyles)
    case .importReadingStyle:
      ReadingStyleImportControl(library: preferences.readingStyles)
    case .documentFont:
      Picker(selection: $preferences.documentFont) {
        Text("Default").tag(DocumentStyle.Font.standard)
        Text("Serif").tag(DocumentStyle.Font.serif)
        Text("Mono").tag(DocumentStyle.Font.monospaced)
      } label: {
        caption
      }
      .pickerStyle(.menu)
    case .documentSize:
      Stepper(value: $preferences.documentTextSize, in: 12...28) {
        valueCaption(Int(preferences.documentStyle.textSize))
      }
    case .codeBlockAccessory:
      Picker(selection: $preferences.codeBlockAccessory) {
        Text("None").tag(CodeBlockAccessory.none)
        Text("Language name").tag(CodeBlockAccessory.language)
        Text("Custom").tag(CodeBlockAccessory.custom)
      } label: {
        caption
      }
      .pickerStyle(.menu)
    case .codeTheme:
      Picker(selection: $preferences.codeTheme) {
        ForEach(CodeHighlightTheme.allCases, id: \.self) { theme in
          Text(theme.title).tag(theme)
        }
      } label: {
        caption
      }
      .pickerStyle(.menu)
    case .editorTheme:
      EditorThemePicker(library: preferences.editorThemes)
    case .importEditorTheme:
      EditorThemeImportControl(library: preferences.editorThemes)
    case .editorFont:
      LabeledContent {
        TextField("", text: $preferences.editorFontName)
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 200)
          .accessibilityLabel("Editor font name")
          .accessibilityIdentifier(entry.id)
      } label: {
        caption
      }
    case .editorSize:
      Stepper(value: $preferences.editorFontSize, in: 8...72) {
        valueCaption(Int(preferences.editorFontSize))
      }
    case .listMarker:
      Picker(selection: $preferences.unorderedMarkerType) {
        Text("* (Asterisk)").tag(0)
        Text("+ (Plus)").tag(1)
        Text("− (Dash)").tag(2)
      } label: {
        caption
      }
      .pickerStyle(.menu)
    }
  }

  private var caption: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.title)
      if !entry.detail.isEmpty {
        Text(entry.detail).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 3)
  }

  private func valueCaption(_ size: Int) -> some View {
    HStack {
      caption
      Spacer()
      Text("\(size) pt").monospacedDigit().foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

/// NSSearchField supplies the same search/cancel affordances and keyboard behavior as System Settings.
private struct SettingsSearchField: NSViewRepresentable {
  @Binding var query: String
  func makeCoordinator() -> Coordinator { Coordinator(query: $query) }
  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Search"
    field.setAccessibilityLabel("Search settings")
    field.setAccessibilityIdentifier("settingsSearch")
    field.sendsSearchStringImmediately = true
    field.sendsWholeSearchString = false
    field.target = context.coordinator
    field.action = #selector(Coordinator.changed(_:))
    return field
  }
  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.query = $query
    if field.stringValue != query { field.stringValue = query }
  }
  @MainActor final class Coordinator: NSObject {
    var query: Binding<String>
    init(query: Binding<String>) { self.query = query }
    @objc func changed(_ sender: NSSearchField) { query.wrappedValue = sender.stringValue }
  }
}

/// A grouped macOS Form owns its native scroll view. Reveal a row using AppKit's
/// standard scrolling operation after its final layout, including cross-pane searches.
private struct SettingsRowReveal: NSViewRepresentable {
  let request: Int?
  func makeNSView(context: Context) -> Anchor { Anchor() }
  func updateNSView(_ view: Anchor, context: Context) {
    view.pendingRequest = request
    view.needsLayout = true
  }
  @MainActor final class Anchor: NSView {
    var pendingRequest: Int?
    private var completedRequest: Int?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      needsLayout = true
    }
    override func layout() {
      super.layout()
      guard window != nil, bounds.height > 0, let pendingRequest,
        completedRequest != pendingRequest
      else { return }
      completedRequest = pendingRequest
      scrollToVisible(bounds.insetBy(dx: 0, dy: -12))
    }
  }
}
