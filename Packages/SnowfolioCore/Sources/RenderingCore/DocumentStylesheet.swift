import Foundation

/// Immutable CSS data shared by preview and fresh export snapshots. File discovery,
/// external asset resolution and template compatibility are separate consumers.
public struct DocumentStylesheet: Hashable, Sendable {
  public enum Failure: Error, Equatable, Sendable { case tooLarge, invalidEncoding }
  public static let maximumBytes = 1_048_576
  public let css: String

  public init(data: Data) throws {
    guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
    guard var css = String(data: data, encoding: .utf8) else { throw Failure.invalidEncoding }
    css.makeContiguousUTF8()
    self.css = css
  }

  // CSS identifiers and string values do not use Swift's canonical Unicode
  // equality. Distinct authored scalar sequences must trigger a style update.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    UTF8Text.equal(lhs.css, rhs.css)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(css.utf8.count)
    for byte in css.utf8 { hasher.combine(byte) }
  }
}

public struct ReadingStyleEntry: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public static let notebook = Self(id: "snowfolio", title: "Snowfolio")
  public static let unstyled = Self(id: "none", title: "None")
  public static let bundled = [
    "Clearness", "Clearness Dark", "GitHub", "GitHub2", "Solarized (Light)", "Solarized (Dark)",
  ].map { Self(id: "bundled:" + $0, title: $0) }
  public static let all = [notebook, unstyled] + bundled
}

/// File reads occur on the repository actor. A successfully loaded bundled sheet
/// is cached; changing typography or exporting performs no further file I/O.
public actor ReadingStyleRepository {
  public enum Failure: Error, Equatable, Sendable { case unavailable, customLegacyStyle }
  public static let standard: ReadingStyleRepository = {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support")
    return ReadingStyleRepository(legacyDirectory: support.appending(path: "MacDown/Styles"))
  }()
  private let legacyDirectory: URL?
  private var cache: [String: DocumentStyle.Presentation] = [:]
  public init(legacyDirectory: URL? = nil) { self.legacyDirectory = legacyDirectory }

  public func load(_ id: String) throws -> DocumentStyle.Presentation {
    try Task.checkCancellation()
    if id == ReadingStyleEntry.notebook.id { return .notebook }
    if id == ReadingStyleEntry.unstyled.id { return .unstyled }
    let resolved = id.hasPrefix("legacy:") ? "bundled:" + id.dropFirst(7) : id
    guard let entry = ReadingStyleEntry.bundled.first(where: { $0.id == resolved }) else {
      throw Failure.unavailable
    }
    // Stock legacy choices may use the bundled fallback, but never substitute
    // stock CSS for an edited user file while custom-file integration is pending.
    if id.hasPrefix("legacy:"), let legacyDirectory {
      let file = legacyDirectory.appendingPathComponent(entry.title).appendingPathExtension("css")
      if FileManager.default.fileExists(atPath: file.path) {
        guard
          let original = Bundle.module.url(
            forResource: entry.title, withExtension: "css", subdirectory: "Styles"),
          let base = URL(string: "mdasset://document/"),
          let request = URL(string: entry.title + ".css", relativeTo: base)?.absoluteURL,
          try LocalPreviewResource.read(request, relativeTo: legacyDirectory).data
            == Data(contentsOf: original)
        else { throw Failure.customLegacyStyle }
      }
    }
    if let cached = cache[entry.id] { return cached }
    guard
      let url = Bundle.module.url(
        forResource: entry.title, withExtension: "css", subdirectory: "Styles")
    else {
      throw Failure.unavailable
    }
    let result = DocumentStyle.Presentation.stylesheet(
      try DocumentStylesheet(data: Data(contentsOf: url)))
    cache[entry.id] = result
    return result
  }
}
