import SwiftUI
import UniformTypeIdentifiers

struct DocumentAssetFolderControl: View {
  let folder: DocumentAssetFolder
  @State private var choosing = false
  @State private var selectionMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LabeledContent {
        HStack {
          if folder.message != nil {
            Button("Retry") { Task { await folder.reload() } }
              .accessibilityIdentifier("retryUnsavedAssetFolder")
          }
          Button("Choose Folder…") {
            selectionMessage = nil
            choosing = true
          }
          .accessibilityIdentifier("chooseUnsavedAssetFolder")
          if folder.canClear {
            Button("Clear") {
              selectionMessage = nil
              folder.clear()
            }
            .accessibilityIdentifier("clearUnsavedAssetFolder")
          }
        }
        .disabled(folder.isLoading)
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text("Unsaved document assets")
          Text(
            "Resolve relative images and files here until a document is saved. Applies to previews and exports."
          )
          .font(.callout).foregroundStyle(.secondary)
        }
      }
      Text(folder.displayPath ?? String(localized: "No folder selected"))
        .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
        .accessibilityIdentifier("unsavedAssetFolderStatus")
      if let suggestion = folder.suggestedDirectory {
        Text("Previously used by MacDown: \(suggestion.path). Choose Folder to allow access.")
          .font(.callout).foregroundStyle(.secondary)
          .accessibilityIdentifier("unsavedAssetFolderMigration")
      }
      if let message = selectionMessage ?? folder.message {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .accessibilityIdentifier("unsavedAssetFolderMessage")
      }
    }
    .padding(.vertical, 3)
    .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
      Task { @MainActor in
        // A canceled chooser leaves both access and the saved choice untouched.
        let url: URL
        switch result {
        case .success(let selected): url = selected
        case .failure(let error):
          let cocoa = error as NSError
          if cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSUserCancelledError {
            selectionMessage = String(localized: "The folder couldn’t be selected. Try again.")
          }
          return
        }
        do { try await folder.choose(url) } catch is CancellationError {} catch {
          // The folder model supplies the recoverable inline explanation.
        }
      }
    }
    .fileDialogDefaultDirectory(folder.access?.directory ?? folder.suggestedDirectory)
    .task { await folder.loadIfNeeded() }
  }
}
