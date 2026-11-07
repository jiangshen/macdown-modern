import CryptoKit
import Foundation

public struct EditorThemeEntry: Equatable, Identifiable, Sendable {
  public enum Origin: String, CaseIterable, Sendable { case automatic, bundled, legacy, imported }
  public let id: String
  public let title: String
  public let origin: Origin

  public init(id: String, title: String, origin: Origin) {
    self.id = id
    self.title = title
    self.origin = origin
  }

  public static let automatic = Self(id: "automatic", title: "Automatic", origin: .automatic)
  public static let bundled: [Self] = [
    "Mou Fresh Air", "Mou Fresh Air+", "Mou Night", "Mou Night+", "Mou Paper", "Mou Paper+",
    "Solarized (Dark)", "Solarized (Dark)+", "Solarized (Light)", "Solarized (Light)+",
    "Tomorrow", "Tomorrow+", "Tomorrow Blue", "Writer", "Writer+",
  ].map { Self(id: "bundled:" + $0, title: $0, origin: .bundled) }

  public static func savedSelection(_ modern: String?, legacy: String?) -> String {
    if let modern { return modern }
    guard let legacy, !legacy.isEmpty else { return automatic.id }
    let name = legacy.hasSuffix(".style") ? String(legacy.dropLast(6)) : legacy
    return "legacy:" + name
  }
}

public struct EditorThemeImport: Sendable {
  public let title: String
  public let theme: EditorTheme
  public let notices: [String]
  fileprivate let data: Data
}

public struct LoadedEditorTheme: Sendable {
  public let theme: EditorTheme?
  public let notices: [String]
}

/// Owns file I/O and bounded decoding away from the UI actor. Imported files are
/// immutable copies; an atomic directory rename publishes metadata and source together.
public actor EditorThemeRepository {
  public enum Failure: Error, Equatable, Sendable {
    case unavailable, invalidFile, invalidEncoding, emptyTheme, corruptMetadata
  }
  private struct Metadata: Codable {
    let version: Int
    let title: String
  }

  public static let standard: EditorThemeRepository = {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support")
    return EditorThemeRepository(
      directory: support.appending(path: "Snowfolio/Themes"),
      legacyDirectory: support.appending(path: "MacDown/Themes"))
  }()

  private let directory: URL
  private let legacyDirectory: URL?
  private let recycle: @Sendable (URL) throws -> Void
  private var bundledCache: [String: LoadedEditorTheme] = [:]

  public init(
    directory: URL, legacyDirectory: URL? = nil,
    recycle: @escaping @Sendable (URL) throws -> Void = {
      try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }
  ) {
    self.directory = directory
    self.legacyDirectory = legacyDirectory
    self.recycle = recycle
  }

  public func entries() throws -> [EditorThemeEntry] {
    var result = [EditorThemeEntry.automatic] + EditorThemeEntry.bundled
    if let legacyDirectory {
      for url in try children(legacyDirectory) where url.pathExtension.lowercased() == "style" {
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
          continue
        }
        let name = url.deletingPathExtension().lastPathComponent
        result.append(.init(id: "legacy:" + name, title: name, origin: .legacy))
      }
    }
    for folder in try children(directory) where folder.pathExtension == "theme" {
      let raw = folder.deletingPathExtension().lastPathComponent
      guard Self.isDigest(raw) else { continue }
      let title = (try? readMetadata(folder).title) ?? "Unavailable Theme (\(raw.prefix(8)))"
      result.append(.init(id: "imported:" + raw, title: title, origin: .imported))
    }
    return result.sorted {
      if $0.origin != $1.origin {
        return Self.order($0.origin) < Self.order($1.origin)
      }
      return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
  }

  public func load(_ id: String) throws -> LoadedEditorTheme {
    try Task.checkCancellation()
    if id == EditorThemeEntry.automatic.id { return .init(theme: nil, notices: []) }
    if let entry = EditorThemeEntry.bundled.first(where: { $0.id == id }) {
      if let cached = bundledCache[id] { return cached }
      guard
        let url = Bundle.module.url(
          forResource: entry.title, withExtension: "style", subdirectory: "Themes")
      else { throw Failure.unavailable }
      let loaded = try decode(try read(url, limit: EditorTheme.maximumBytes))
      bundledCache[id] = loaded
      return loaded
    }
    if id.hasPrefix("legacy:") {
      let name = String(id.dropFirst("legacy:".count))
      guard Self.isFileComponent(name) else { throw Failure.unavailable }
      if let legacyDirectory {
        if let url = try children(legacyDirectory).first(where: {
          $0.pathExtension.lowercased() == "style"
            && $0.deletingPathExtension().lastPathComponent == name
        }) {
          return try decode(try read(url, limit: EditorTheme.maximumBytes))
        }
      }
      // Older versions copied stock themes into MacDown's mutable data directory.
      // Keep the saved choice usable if that directory is no longer present.
      return try load("bundled:" + name)
    }
    guard id.hasPrefix("imported:") else { throw Failure.unavailable }
    let digest = String(id.dropFirst("imported:".count))
    guard Self.isDigest(digest) else { throw Failure.unavailable }
    let folder = directory.appendingPathComponent(digest).appendingPathExtension("theme")
    _ = try readMetadata(folder)
    let data = try read(
      folder.appendingPathComponent("source.style"), limit: EditorTheme.maximumBytes)
    guard Self.digest(data) == digest else { throw Failure.corruptMetadata }
    return try decode(data)
  }

  public func inspect(_ url: URL) throws -> EditorThemeImport {
    guard url.isFileURL, url.pathExtension.lowercased() == "style" else {
      throw Failure.invalidFile
    }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let data = try read(url, limit: EditorTheme.maximumBytes)
    let loaded = try decode(data)
    guard let theme = loaded.theme else { throw Failure.emptyTheme }
    let title = String(
      url.deletingPathExtension().lastPathComponent.unicodeScalars.filter {
        !CharacterSet.controlCharacters.contains($0)
      }.prefix(128).map(Character.init))
    return .init(
      title: title.isEmpty ? "Imported Theme" : title, theme: theme, notices: loaded.notices,
      data: data)
  }

  public func store(_ candidate: EditorThemeImport) throws -> EditorThemeEntry {
    try Task.checkCancellation()
    let id = Self.digest(candidate.data)
    let destination = directory.appendingPathComponent(id).appendingPathExtension("theme")
    var replacingDamagedCopy = false
    if FileManager.default.fileExists(atPath: destination.path) {
      do {
        _ = try load("imported:" + id)
        return .init(
          id: "imported:" + id, title: try readMetadata(destination).title, origin: .imported)
      } catch is CancellationError { throw CancellationError() } catch {
        replacingDamagedCopy = true
      }
    }
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let staging = directory.appendingPathComponent(
      ".import-" + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: staging, withIntermediateDirectories: false)
    do {
      let metadata = try JSONEncoder().encode(Metadata(version: 1, title: candidate.title))
      try metadata.write(to: staging.appendingPathComponent("Info.json"), options: .atomic)
      try candidate.data.write(to: staging.appendingPathComponent("source.style"), options: .atomic)
      try Task.checkCancellation()
      if replacingDamagedCopy { try recycle(destination) }
      try manager.moveItem(at: staging, to: destination)
    } catch {
      // Only this unpublished staging copy is ours. Keep failure cleanup reversible.
      try? recycle(staging)
      throw error
    }
    return .init(id: "imported:" + id, title: candidate.title, origin: .imported)
  }

  private func children(_ folder: URL) throws -> [URL] {
    guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
    try Task.checkCancellation()
    return try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
  }

  private func readMetadata(_ folder: URL) throws -> Metadata {
    let metadata = try JSONDecoder().decode(
      Metadata.self, from: read(folder.appendingPathComponent("Info.json"), limit: 8192))
    guard metadata.version == 1, !metadata.title.isEmpty, metadata.title.utf8.count <= 4096 else {
      throw Failure.corruptMetadata
    }
    return metadata
  }

  private func read(_ url: URL, limit: Int) throws -> Data {
    try Task.checkCancellation()
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      throw Failure.invalidFile
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while data.count <= limit {
      try Task.checkCancellation()
      let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)) ?? Data()
      if chunk.isEmpty { break }
      data.append(chunk)
    }
    guard data.count <= limit else { throw EditorTheme.ParseError.tooLarge }
    return data
  }

  private func decode(_ data: Data) throws -> LoadedEditorTheme {
    guard let source = String(data: data, encoding: .utf8) else { throw Failure.invalidEncoding }
    let theme = try EditorTheme.parse(source)
    guard theme.rules.contains(where: { !$0.attributes.isEmpty }) else { throw Failure.emptyTheme }
    var notices = theme.diagnostics.map { "Line \($0.line): \($0.message)" }
    var ignored = false
    var largeFonts = false
    for rule in theme.rules {
      for attribute in rule.attributes {
        if case .custom = attribute.value { ignored = true }
        if rule.selector == "editor-selection" {
          if ["font-size", "font-family"].contains(attribute.name) { ignored = true }
          if case .fontStyle(let style) = attribute.value,
            style.contains(.bold) || style.contains(.italic)
          {
            ignored = true
          }
        }
        if case .fontSize(let size) = attribute.value, abs(size.points) > 144 { largeFonts = true }
      }
    }
    if ignored {
      notices.append("Some settings in this file are not supported and will be ignored.")
    }
    if largeFonts {
      notices.append("This theme uses very large text sizes that may make editing difficult.")
    }
    try Task.checkCancellation()
    return .init(theme: theme, notices: notices)
  }

  private static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  private static func isFileComponent(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".." && !value.contains("/")
      && !value.utf8.contains(0)
  }

  private static func order(_ origin: EditorThemeEntry.Origin) -> Int {
    EditorThemeEntry.Origin.allCases.firstIndex(of: origin) ?? 0
  }
}
