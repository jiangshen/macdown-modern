import AppKit
import SnowfolioUI
import SwiftUI

@main
struct SnowfolioApp: App {
  @NSApplicationDelegateAdaptor(SnowfolioApplicationDelegate.self) private var applicationDelegate
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

/// Configure the native document controller after SwiftUI has installed its host.
@MainActor
final class SnowfolioApplicationDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Keep active-window edits and Undo on disk without a custom save timer or writer.
    NSDocumentController.shared.autosavingDelay = 2
  }
}
