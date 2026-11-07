import Foundation
import Observation
import RenderingCore

/// App-owned resolved presentation. Failed or superseded loads never replace the
/// last good appearance, and the saved selection remains visible for recovery.
@MainActor
@Observable
public final class ReadingStyleLibrary {
  public private(set) var selection: String
  public private(set) var presentation = DocumentStyle.Presentation.notebook
  public private(set) var message: String?
  public private(set) var isLoading = false
  public private(set) var isReady = false
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let repository: ReadingStyleRepository
  @ObservationIgnored private var loaded = false
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
    if !loaded { await refresh() }
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
      let result: Result<DocumentStyle.Presentation, Error>
      do { result = .success(try await repository.load(selected)) } catch {
        result = .failure(error)
      }
      guard let self, self.generation == request, !Task.isCancelled else { return }
      switch result {
      case .success(let presentation):
        self.presentation = presentation
        self.message = nil
      case .failure:
        self.message = String(
          localized: "This style couldn’t be loaded. The last available appearance is still in use."
        )
      }
      self.loaded = true
      self.isReady = true
      self.isLoading = false
      self.operation = nil
    }
    operation = next
    await next.value
  }
}
