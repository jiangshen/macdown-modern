import RenderingCore
import SwiftUI

public struct MarkdownSettingsView: View {
  @Bindable public var preferences: AppPreferences

  public init(preferences: AppPreferences) { self.preferences = preferences }

  public var body: some View {
    TabView {
      Tab("Editor", systemImage: "textformat") {
        Form {
          Section("Typography") {
            TextField("Font name", text: $preferences.editorFontName)
            Stepper(
              "Font size: \(Int(preferences.editorFontSize)) pt",
              value: $preferences.editorFontSize, in: 8...72)
          }
          Section("Typing") {
            Toggle("Use spaces for tabs", isOn: $preferences.convertTabs)
            Toggle("Continue lists and quotes", isOn: $preferences.continueBlocks)
            Toggle("Increment numbered lists", isOn: $preferences.incrementLists)
            Toggle("Complete paired delimiters", isOn: $preferences.pairDelimiters)
            Picker("Unordered list marker", selection: $preferences.unorderedMarkerType) {
              Text("*").tag(0)
              Text("+").tag(1)
              Text("−").tag(2)
            }
          }
          Section("Preview") {
            Toggle("Render manually", isOn: $preferences.manualRendering)
          }
        }.formStyle(.grouped)
      }
      Tab("Documents", systemImage: "doc.richtext") {
        Form {
          Section("Notebook style") {
            Text("Quiet typography and generous spacing for your preview and styled exports.")
              .font(.caption).foregroundStyle(.secondary)
            Picker("Font", selection: $preferences.documentFont) {
              Text("Default").tag(DocumentStyle.Font.standard)
              Text("Serif").tag(DocumentStyle.Font.serif)
              Text("Mono").tag(DocumentStyle.Font.monospaced)
            }.accessibilityIdentifier("documentFont")
            Stepper(
              "Text size: \(Int(preferences.documentStyle.textSize)) pt",
              value: $preferences.documentTextSize, in: 12...28
            ).accessibilityIdentifier("documentTextSize")
            Toggle("Full width", isOn: $preferences.documentFullWidth)
              .accessibilityIdentifier("documentFullWidth")
          }
          Text("The source editor keeps the font you choose in Editor settings.")
            .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
      }
      Tab("Markdown", systemImage: "text.document") {
        Form {
          Toggle("Tables", isOn: $preferences.tables)
          Toggle("Task lists", isOn: $preferences.taskLists)
          Toggle("Strikethrough", isOn: $preferences.strikethrough)
          Toggle("Automatic links", isOn: $preferences.autolinks)
          Toggle("Footnotes", isOn: $preferences.footnotes)
          Toggle("Smart punctuation", isOn: $preferences.smartPunctuation)
          Toggle("Break lines at source newlines", isOn: $preferences.hardLineBreaks)
        }.formStyle(.grouped)
      }
      Tab("Privacy", systemImage: "hand.raised") {
        Form {
          Section {
            Toggle("Show HTML in Markdown", isOn: $preferences.rawHTML)
            Text("Scripts and embedded frames stay disabled in the preview.")
              .font(.caption).foregroundStyle(.secondary)
          }
          Section {
            Toggle("Load remote images", isOn: $preferences.remoteImages)
            Text(
              "Remote images contact the sites hosting them. Local images within the document’s folder work without this option."
            )
            .font(.caption).foregroundStyle(.secondary)
          }
        }.formStyle(.grouped)
      }
    }
    .frame(width: 520, height: 420)
  }
}
