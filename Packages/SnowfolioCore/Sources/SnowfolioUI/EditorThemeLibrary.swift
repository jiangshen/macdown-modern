import EditorCore
import Foundation
import Observation

/// One app-owned observable library. Files and parsing stay in the repository;
/// only the newest selection can publish a resolved theme to document views.
@MainActor
@Observable
public final class EditorThemeLibrary {
  public private(set) var entries = [EditorThemeEntry.automatic] + EditorThemeEntry.bundled
  public private(set) var selection: String
  public private(set) var theme: EditorTheme?
  public private(set) var notices: [String] = []
  public private(set) var message: String?
  public private(set) var isLoading = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let repository: EditorThemeRepository
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var loaded = false
  @ObservationIgnored private var operation: Task<Void, Never>?

  public init(defaults: UserDefaults, repository: EditorThemeRepository = .standard) {
    self.defaults = defaults
    self.repository = repository
    selection = EditorThemeEntry.savedSelection(
      defaults.string(forKey: "editorThemeSelection"),
      legacy: defaults.string(forKey: "editorStyleName"))
  }

  public func loadIfNeeded() async {
    if let operation {
      await operation.value
      return
    }
    guard !loaded else { return }
    await refresh()
  }

  public func select(_ id: String) async {
    selection = id
    defaults.set(id, forKey: "editorThemeSelection")
    // Keep the old preference meaningful for the native app's migration data.
    if id.hasPrefix("legacy:") {
      defaults.set(String(id.dropFirst(7)), forKey: "editorStyleName")
    } else if let entry = EditorThemeEntry.bundled.first(where: { $0.id == id }) {
      defaults.set(entry.title, forKey: "editorStyleName")
    } else if id == EditorThemeEntry.automatic.id {
      defaults.removeObject(forKey: "editorStyleName")
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
      var listing: [EditorThemeEntry]?
      var listingFailed = false
      do { listing = try await repository.entries() } catch { listingFailed = true }
      let result: Result<LoadedEditorTheme, Error>
      do { result = .success(try await repository.load(selected)) } catch {
        result = .failure(error)
      }
      guard let self, self.generation == request, !Task.isCancelled else { return }
      if let listing { self.entries = listing }
      self.addSavedAliasIfNeeded()
      switch result {
      case .success(let loaded):
        self.theme = loaded.theme
        self.notices = loaded.notices
        self.message =
          listingFailed
          ? String(localized: "Some themes couldn’t be listed. Bundled themes are still available.")
          : nil
      case .failure:
        self.message = String(
          localized:
            "This theme couldn’t be loaded. The last available appearance is still in use. Choose another theme or import the file again."
        )
      }
      self.loaded = true
      self.isLoading = false
      self.operation = nil
    }
    operation = next
    await next.value
  }

  public func inspect(_ url: URL) async throws -> EditorThemeImport {
    try await repository.inspect(url)
  }

  public func importTheme(_ candidate: EditorThemeImport) async throws {
    let entry = try await repository.store(candidate)
    if !entries.contains(where: { $0.id == entry.id }) { entries.append(entry) }
    await select(entry.id)
  }

  private func addSavedAliasIfNeeded() {
    guard !entries.contains(where: { $0.id == selection }) else { return }
    let legacy = selection.hasPrefix("legacy:") ? String(selection.dropFirst(7)) : nil
    let known = legacy.flatMap { name in EditorThemeEntry.bundled.first { $0.title == name } }
    entries.append(
      .init(
        id: selection, title: known?.title ?? String(localized: "Unavailable Theme"),
        origin: legacy == nil ? .imported : .legacy))
  }
}
