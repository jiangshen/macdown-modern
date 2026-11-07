import AppKit
import EditorCore
import SwiftUI
import UniformTypeIdentifiers

struct EditorThemePicker: View {
  let library: EditorThemeLibrary

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker(
        selection: Binding(
          get: { library.selection }, set: { id in Task { await library.select(id) } })
      ) {
        Text("Automatic").tag(EditorThemeEntry.automatic.id)
        ForEach([EditorThemeEntry.Origin.bundled, .legacy, .imported], id: \.self) { origin in
          let choices = library.entries.filter { $0.origin == origin }
          if !choices.isEmpty {
            Section(title(origin)) {
              ForEach(choices) { entry in Text(entry.title).tag(entry.id) }
            }
          }
        }
      } label: {
        VStack(alignment: .leading, spacing: 3) {
          Text("Theme")
          Text("Colors and typography for Markdown source.")
            .font(.callout).foregroundStyle(.secondary)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("editorTheme")
      if let message = library.message {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("editorThemeStatus")
      }
      if !library.notices.isEmpty {
        Text(library.notices.prefix(3).joined(separator: "\n"))
          .font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("editorThemeNotices")
      }
    }
    .padding(.vertical, 3)
    .task { await library.loadIfNeeded() }
  }

  private func title(_ origin: EditorThemeEntry.Origin) -> LocalizedStringKey {
    switch origin {
    case .automatic: "Automatic"
    case .bundled: "Bundled Themes"
    case .legacy: "From MacDown"
    case .imported: "Imported Themes"
    }
  }
}

struct EditorThemeImportControl: View {
  let library: EditorThemeLibrary
  @State private var choosingFile = false
  @State private var importing = false
  @State private var prompt: Prompt?

  private enum Prompt {
    case review(EditorThemeImport, [String])
    case failure(String)
    var title: LocalizedStringKey {
      switch self {
      case .review: "Review Theme"
      case .failure: "Couldn’t Import Theme"
      }
    }
    var message: String {
      switch self {
      case .review(let candidate, let notices):
        return candidate.title + "\n\n" + notices.prefix(5).joined(separator: "\n")
      case .failure(let message): return message
      }
    }
  }

  var body: some View {
    LabeledContent {
      HStack(spacing: 8) {
        Button("Reload", systemImage: "arrow.clockwise") {
          Task { await library.refresh() }
        }
        .labelStyle(.iconOnly)
        .help("Reload themes")
        .disabled(library.isLoading)
        .accessibilityIdentifier("reloadEditorThemes")
        Button("Import…") { choosingFile = true }
          .disabled(importing)
          .accessibilityIdentifier("importEditorTheme")
      }
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text("Custom themes")
        Text("Import a .style file. The original file stays in place.")
          .font(.callout).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 3)
    .fileImporter(
      isPresented: $choosingFile,
      allowedContentTypes: [UTType(filenameExtension: "style") ?? .data],
      allowsMultipleSelection: false
    ) { result in
      Task { @MainActor in
        do {
          guard let url = try result.get().first else { return }
          importing = true
          defer { importing = false }
          let candidate = try await library.inspect(url)
          let notices = candidate.notices + missingFontNotices(candidate.theme)
          if notices.isEmpty {
            try await library.importTheme(candidate)
          } else {
            prompt = .review(candidate, notices)
          }
        } catch {
          let cocoa = error as NSError
          guard cocoa.domain != NSCocoaErrorDomain || cocoa.code != NSUserCancelledError else {
            return
          }
          prompt = .failure(Self.message(error))
        }
      }
    }
    .alert(
      prompt?.title ?? "Review Theme",
      isPresented: Binding(
        get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt
    ) { value in
      switch value {
      case .review(let candidate, _):
        Button("Import") {
          prompt = nil
          Task { @MainActor in
            importing = true
            defer { importing = false }
            do { try await library.importTheme(candidate) } catch {
              prompt = .failure(Self.message(error))
            }
          }
        }
        Button("Cancel", role: .cancel) { prompt = nil }
      case .failure:
        Button("OK", role: .cancel) { prompt = nil }
      }
    } message: { value in
      Text(value.message)
    }
  }

  private func missingFontNotices(_ theme: EditorTheme) -> [String] {
    let base = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let missing = Set(
      theme.rules.flatMap(\.attributes).compactMap { attribute -> String? in
        guard case .fontFamily(let name) = attribute.value,
          NSFontManager.shared.convert(base, toFace: name) == nil
        else { return nil }
        return name
      })
    guard !missing.isEmpty else { return [] }
    return [
      String(
        localized:
          "Unavailable fonts will use the editor’s font: \(missing.sorted().joined(separator: ", "))"
      )
    ]
  }

  private static func message(_ error: Error) -> String {
    switch error {
    case EditorThemeRepository.Failure.invalidFile:
      String(localized: "Choose a regular .style theme file.")
    case EditorThemeRepository.Failure.invalidEncoding:
      String(localized: "Save this theme as UTF-8 text, then import it again.")
    case EditorThemeRepository.Failure.emptyTheme:
      String(localized: "This file doesn’t contain any theme settings that can be used.")
    case EditorTheme.ParseError.tooLarge:
      String(localized: "Theme files must be no larger than 1 MB.")
    case EditorTheme.ParseError.containsNul, EditorTheme.ParseError.tooComplex:
      String(localized: "This theme contains unsupported content or too many settings.")
    default:
      String(
        localized: "The theme couldn’t be read or saved. Check access to the file and try again.")
    }
  }
}
