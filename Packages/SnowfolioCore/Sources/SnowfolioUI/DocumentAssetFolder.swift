import Foundation
import Observation

/// A balanced read-only security scope. Preview requests and export snapshots keep
/// their own reference so changing Settings cannot revoke an in-flight read.
public final class DocumentAssetAccess: Sendable {
  let id = UUID()
  public let directory: URL
  private let scoped: Bool

  private init(_ url: URL) {
    directory = url
    scoped = url.startAccessingSecurityScopedResource()
  }

  deinit {
    if scoped { directory.stopAccessingSecurityScopedResource() }
  }

  @concurrent
  static func choose(_ url: URL) async throws -> (DocumentAssetAccess, Data) {
    guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let access = DocumentAssetAccess(url)
    try validate(access)
    return (access, try bookmark(url))
  }

  @concurrent
  static func restore(_ data: Data) async throws -> (DocumentAssetAccess, Data?) {
    guard data.count <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
      relativeTo: nil, bookmarkDataIsStale: &stale)
    guard url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
    let access = DocumentAssetAccess(url)
    try validate(access)
    return (access, stale ? try bookmark(url) : nil)
  }

  private static func validate(_ access: DocumentAssetAccess) throws {
    guard try access.directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
      throw CocoaError(.fileReadUnsupportedScheme)
    }
  }

  private static func bookmark(_ url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
      includingResourceValuesForKeys: nil, relativeTo: nil)
  }
}

struct DocumentAssetLocation: Sendable {
  let directory: URL?
  let access: DocumentAssetAccess?
}

/// The old URL is only a chooser suggestion, never an implicit filesystem grant.
/// An explicit clear suppresses that suggestion without deleting legacy preferences.
@MainActor
@Observable
public final class DocumentAssetFolder {
  static let bookmarkKey = "unsavedDocumentAssetFolderBookmark"
  static let choiceKey = "unsavedDocumentAssetFolderChosen"
  private static let pathKey = "unsavedDocumentAssetFolderPath"
  public private(set) var access: DocumentAssetAccess?
  public private(set) var displayPath: String?
  public private(set) var message: String?
  public private(set) var isLoading = false
  public private(set) var isReady: Bool
  public private(set) var suggestedDirectory: URL?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var generation = UUID()
  @ObservationIgnored private var operation: Task<Void, Never>?

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    let saved = defaults.object(forKey: Self.bookmarkKey) != nil
    isReady = !saved
    displayPath = defaults.string(forKey: Self.pathKey)
    if !saved && !defaults.bool(forKey: Self.choiceKey),
      let legacy = defaults.url(forKey: "htmlDefaultDirectoryUrl"), legacy.isFileURL
    {
      suggestedDirectory = legacy
    }
  }

  var isUnavailable: Bool {
    isReady && !isLoading && access == nil && defaults.object(forKey: Self.bookmarkKey) != nil
  }

  var canClear: Bool {
    displayPath != nil || suggestedDirectory != nil
      || defaults.object(forKey: Self.bookmarkKey) != nil
  }

  func location(for fileURL: URL?) -> DocumentAssetLocation {
    if let fileURL { return .init(directory: fileURL.deletingLastPathComponent(), access: nil) }
    return .init(directory: access?.directory, access: access)
  }

  public func loadIfNeeded() async {
    if let operation {
      await operation.value
      return
    }
    guard !isReady && !isLoading else { return }
    await reload()
  }

  public func reload() async {
    let request = begin()
    let data = defaults.data(forKey: Self.bookmarkKey)
    let next = Task { @MainActor [weak self] in
      do {
        guard let data else { throw CocoaError(.fileReadCorruptFile) }
        let (access, renewed) = try await DocumentAssetAccess.restore(data)
        guard let self, self.generation == request, !Task.isCancelled else { return }
        if let renewed { self.defaults.set(renewed, forKey: Self.bookmarkKey) }
        self.publish(access)
      } catch {
        guard let self, self.generation == request, !Task.isCancelled else { return }
        // No fallback grant on failed restore. Keep the saved choice for recovery.
        self.access = nil
        self.message = String(
          localized: "The folder is unavailable. Reconnect it and retry, or choose it again.")
      }
      guard let self, self.generation == request else { return }
      self.isReady = true
      self.isLoading = false
      self.operation = nil
    }
    operation = next
    await next.value
  }

  public func choose(_ url: URL) async throws {
    let request = begin()
    defer {
      if generation == request {
        isLoading = false
        isReady = true
      }
    }
    do {
      let (access, bookmark) = try await DocumentAssetAccess.choose(url)
      try Task.checkCancellation()
      guard generation == request else { throw CancellationError() }
      defaults.set(bookmark, forKey: Self.bookmarkKey)
      defaults.set(true, forKey: Self.choiceKey)
      suggestedDirectory = nil
      publish(access)
    } catch {
      if generation == request {
        message = String(
          localized: "The folder couldn’t be opened. The previous folder choice has been kept.")
      }
      throw error
    }
  }

  public func clear() {
    generation = UUID()
    operation?.cancel()
    operation = nil
    access = nil
    displayPath = nil
    suggestedDirectory = nil
    message = nil
    isReady = true
    isLoading = false
    defaults.removeObject(forKey: Self.bookmarkKey)
    defaults.removeObject(forKey: Self.pathKey)
    defaults.set(true, forKey: Self.choiceKey)
  }

  private func begin() -> UUID {
    generation = UUID()
    operation?.cancel()
    operation = nil
    isLoading = true
    return generation
  }

  private func publish(_ access: DocumentAssetAccess) {
    self.access = access
    displayPath = access.directory.path
    defaults.set(displayPath, forKey: Self.pathKey)
    message = nil
  }
}
