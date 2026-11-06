import MacDownUI
import SwiftUI

@main
struct MacDownModernApp: App {
  @State private var preferences = AppPreferences()

  var body: some Scene {
    DocumentGroup { (document: MarkdownDocument) in
      DocumentWorkspace(document: document, preferences: preferences)
        .frame(minWidth: 720, idealWidth: 1120, minHeight: 360, idealHeight: 640)
    } makeDocument: { configuration, _ in
      MarkdownDocument(configuration: configuration)
    }
    .commands {
      TextEditingCommands()
      DocumentExportCommands()
    }
    Settings { MarkdownSettingsView(preferences: preferences) }
  }
}
