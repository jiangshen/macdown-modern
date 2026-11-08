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

/// Apply native document policy after SwiftUI installs its document controller.
@MainActor
final class SnowfolioApplicationDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Model snapshots checkpoint native typing before serialization, so edits
    // after an autosave register as a fresh native Undo/dirty-state operation.
    NSDocumentController.shared.autosavingDelay = 2
  }
}
