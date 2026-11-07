import Foundation
import Observation
import RenderingCore

/// App-owned resolved presentation. Failed or superseded loads never replace the
/// last good appearance, and the saved selection remains visible for recovery.
@MainActor
@Observable
public final class ReadingStyleLibrary {
  public private(set) var entries = ReadingStyleEntry.all
  public private(set) var selection: String
  public private(set) var presentation = DocumentStyle.Presentation.notebook
  public private(set) var message: String?
  public private(set) var isLoading = false
  public private(set) var isReady = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let repository: ReadingStyleRepository
  @ObservationIgnored private var loaded = false
  @ObservationIgnored private var catalogLoaded = false
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var operation: Task<Void, Never>?

  public init(
    defaults: UserDefaults, selection: String, repository: ReadingStyleRepository = .standard
  ) {
    self.defaults = defaults
    self.selection = selection
    self.repository = repository
    if selection == ReadingStyleEntry.notebook.id || selection == ReadingStyleEntry.unstyled.id {
      presentation = selection == ReadingStyleEntry.notebook.id ? .notebook : .unstyled
      loaded = true
      isReady = true
    }
  }

  public func loadIfNeeded() async {
    if let operation {
      await operation.value
      return
    }
    if !loaded || !catalogLoaded { await refresh() }
  }

  public func select(_ id: String) async {
    selection = id
    defaults.set(id, forKey: "readingStyleSelection")
    if id == ReadingStyleEntry.unstyled.id {
      defaults.removeObject(forKey: "htmlStyleName")
    } else if let entry = ReadingStyleEntry.bundled.first(where: { $0.id == id }) {
      defaults.set(entry.title, forKey: "htmlStyleName")
    }
    await refresh()
  }

  public func refresh() async {
    let request = UUID()
    generation = request
    operation?.cancel()
    isLoading = true
    let selected = selection
    let repository = repository
    let next = Task { @MainActor [weak self] in
      var listing: [ReadingStyleEntry]?
      do { listing = try await repository.entries() } catch {}
      let result: Result<DocumentStyle.Presentation, Error>
      do { result = .success(try await repository.load(selected)) } catch {
        result = .failure(error)
      }
      guard let self, self.generation == request, !Task.isCancelled else { return }
      if let listing { self.entries = listing }
      self.catalogLoaded = listing != nil
      self.addSavedAlias()
      switch result {
      case .success(let presentation):
        self.presentation = presentation
        self.message =
          listing == nil
          ? String(localized: "Some styles couldn’t be listed. Reload to try again.") : nil
      case .failure(let error):
        self.message =
          Self.description(error) + " "
          + String(localized: "The last available appearance is still in use.")
      }
      self.loaded = true
      self.isReady = true
      self.isLoading = false
      self.operation = nil
    }
    operation = next
    await next.value
  }

  public func inspect(_ url: URL) async throws -> ReadingStyleImport {
    try await repository.inspect(url)
  }
  public func prepareFolder(_ url: URL) async throws -> ReadingStyleFolder {
    try await repository.prepareFolder(url)
  }
  public func inspect(_ folder: ReadingStyleFolder, main: String) async throws -> ReadingStyleImport
  {
    try await repository.inspect(folder, main: main)
  }
  public func importStyle(_ candidate: ReadingStyleImport) async throws {
    let entry = try await repository.store(candidate)
    await select(entry.id)
  }
  public func stylesDirectory() async throws -> URL {
    try await repository.stylesDirectory()
  }

  private func addSavedAlias() {
    guard !entries.contains(where: { $0.id == selection }) else { return }
    let title =
      selection.hasPrefix("legacy:")
      ? String(selection.dropFirst(7)) : String(localized: "Unavailable Style")
    entries.append(
      .init(
        id: selection, title: title, origin: selection.hasPrefix("legacy:") ? .legacy : .imported))
  }

  static func description(_ error: Error) -> String {
    switch error {
    case StyleAssetFailure.remoteStylesheetOrFont:
      String(
        localized:
          "Remote stylesheet imports and web fonts can’t be loaded. Save them in the style folder and use local links."
      )
    case StyleAssetFailure.importCycle:
      String(
        localized:
          "This style has a circular stylesheet import. Remove the circular link and reload.")
    case StyleAssetFailure.unsupportedSyntax:
      String(
        localized:
          "This stylesheet contains CSS syntax that can’t be resolved. Check the CSS and try again."
      )
    case StyleAssetFailure.tooLarge, DocumentStylesheet.Failure.tooLarge,
      LocalPreviewResourceError.tooLarge:
      String(localized: "The stylesheet or its supporting files exceed the size limit.")
    case StyleAssetFailure.tooComplex:
      String(localized: "This style has too many files, imports or CSS rules.")
    case DocumentStylesheet.Failure.invalidEncoding:
      String(localized: "Save this stylesheet as UTF-8 text and try again.")
    case StyleAssetFailure.unsupportedResource, LocalPreviewResourceError.unsupportedType:
      String(
        localized:
          "This stylesheet links to an unsupported file type. Use local CSS, images and font files."
      )
    case ReadingStyleRepository.Failure.emptyFolder:
      String(localized: "Choose a folder containing a CSS stylesheet.")
    case ReadingStyleRepository.Failure.invalidFile:
      String(localized: "Choose a CSS file or a folder containing its supporting files.")
    default:
      String(
        localized:
          "This style couldn’t be read. Check file access; use Import Style Folder for styles with local images, fonts or imports."
      )
    }
  }

}
