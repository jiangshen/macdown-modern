import AppKit
import RenderingCore
import SwiftUI
import UniformTypeIdentifiers

struct ReadingStyleImportControl: View {
  let library: ReadingStyleLibrary
  @State private var choosingFile = false
  @State private var choosingFolder = false
  @State private var importing = false
  @State private var failure: String?
  @State private var folderChoice: FolderChoice?

  private struct FolderChoice: Identifiable {
    let id = UUID()
    let folder: ReadingStyleFolder
  }

  var body: some View {
    LabeledContent {
      HStack {
        Button("Show in Finder") {
          Task { @MainActor in
            do { NSWorkspace.shared.open(try await library.stylesDirectory()) } catch {
              failure = ReadingStyleLibrary.description(error)
            }
          }
        }.accessibilityIdentifier("revealReadingStyles")
        Menu("Import…") {
          Button("CSS File…") {
            choosingFolder = false
            choosingFile = true
          }
          Button("Style Folder…") {
            choosingFolder = true
            choosingFile = true
          }
        }.disabled(importing).accessibilityIdentifier("importReadingStyle")
      }
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text("Custom styles")
        Text("Import a CSS file, or its folder to include images, fonts and other stylesheets.")
          .font(.callout).foregroundStyle(.secondary)
      }
    }
    .fileImporter(
      isPresented: $choosingFile,
      allowedContentTypes: choosingFolder ? [.folder] : [.css], allowsMultipleSelection: false
    ) { result in
      Task { @MainActor in
        do {
          guard let url = try result.get().first else { return }
          importing = true
          defer { importing = false }
          if choosingFolder {
            folderChoice = FolderChoice(folder: try await library.prepareFolder(url))
          } else {
            let candidate = try await library.inspect(url)
            try await library.importStyle(candidate)
          }
        } catch {
          let cocoa = error as NSError
          if cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSUserCancelledError {
            failure = ReadingStyleLibrary.description(error)
          }
        }
      }
    }
    .sheet(item: $folderChoice) { choice in
      ReadingStyleFolderSheet(folder: choice.folder, library: library)
    }
    .alert(
      "Couldn’t Import Style",
      isPresented: Binding(
        get: { failure != nil }, set: { if !$0 { failure = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(failure ?? "")
    }
  }
}

private struct ReadingStyleFolderSheet: View {
  let folder: ReadingStyleFolder
  let library: ReadingStyleLibrary
  @State private var main: String
  @State private var importing = false
  @State private var failure: String?
  @Environment(\.dismiss) private var dismiss

  init(folder: ReadingStyleFolder, library: ReadingStyleLibrary) {
    self.folder = folder
    self.library = library
    _main = State(initialValue: folder.filenames.first ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Import Style Folder").font(.title2)
      Text(
        "Choose the main stylesheet in “\(folder.title)”. Its local supporting files will be included."
      )
      .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      Picker("Main stylesheet", selection: $main) {
        ForEach(folder.filenames, id: \.self) { Text($0).tag($0) }
      }.accessibilityIdentifier("readingStyleMainFile")
      if let failure {
        Text(failure).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if importing { ProgressView().controlSize(.small).accessibilityLabel("Importing style") }
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
          .disabled(importing).accessibilityIdentifier("cancelReadingStyleFolder")
        Button("Import") {
          Task { @MainActor in
            importing = true
            defer { importing = false }
            do {
              let candidate = try await library.inspect(folder, main: main)
              try await library.importStyle(candidate)
              dismiss()
            } catch { failure = ReadingStyleLibrary.description(error) }
          }
        }.keyboardShortcut(.defaultAction).disabled(importing || main.isEmpty)
          .accessibilityIdentifier("confirmReadingStyleFolder")
      }
    }.padding(20).frame(minWidth: 420).fixedSize(horizontal: false, vertical: true)
  }
}
