#if !NATIVE_DOCUMENT_HOST
  import SnowfolioUI
  import SwiftUI

  @main
  struct SnowfolioApp: App {
    @NSApplicationDelegateAdaptor(DocumentURLAppDelegate.self) private var appDelegate
    @State private var preferences = AppPreferences()

    var body: some Scene {
      DocumentGroup { (document: MarkdownDocument) in
        DocumentWorkspace(document: document, preferences: preferences)
          .frame(minWidth: 720, idealWidth: 1120, minHeight: 360, idealHeight: 640)
      } makeDocument: { configuration, _ in
        MarkdownDocument(configuration: configuration)
      }
      .commands {
        SnowfolioSettingsCommands(preferences: preferences)
        TextEditingCommands()
        DocumentTabCommands()
        DocumentScrollCommands(preferences: preferences)
        DocumentZoomCommands()
        DocumentExportCommands()
        MarkdownFormatCommands()
      }
    }
  }
#endif
