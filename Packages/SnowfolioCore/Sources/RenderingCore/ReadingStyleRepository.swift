import Darwin
import Foundation

public struct ReadingStyleImport: Sendable {
  public let title: String
  public let stylesheet: DocumentStylesheet
  fileprivate let identifier: String
  fileprivate let main: String
  fileprivate let files: [String: Data]
}

/// A temporary folder grant for the main-sheet chooser. No persistent grant is
/// needed after import: original CSS and referenced files are copied together.
public struct ReadingStyleFolder: Sendable {
  public let title: String
  public let filenames: [String]
  fileprivate let bookmark: Data
}

/// Owns bounded file discovery/reads, CSS resolution and atomic imports off the UI
/// actor. Bundled files cache; editable local/legacy/imported styles reload freshly.
public actor ReadingStyleRepository {
  public enum Failure: Error, Equatable, Sendable {
    case unavailable, invalidFile, emptyFolder, corruptMetadata
  }
  public static let standard: ReadingStyleRepository = {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support")
    return ReadingStyleRepository(
      directory: support.appending(path: "Snowfolio/Styles"),
      legacyDirectory: support.appending(path: "MacDown/Styles"))
  }()
  private let directory: URL?
  private let legacyDirectory: URL?
  private let recycle: @Sendable (URL) throws -> Void
  private let parser = CSSResourceParser()
  private var cache: [String: DocumentStyle.Presentation] = [:]
  private struct Metadata: Codable {
    let version: Int
    let title: String
    let main: String
  }

  public init(
    directory: URL? = nil, legacyDirectory: URL? = nil,
    recycle: @escaping @Sendable (URL) throws -> Void = {
      try FileManager.default.trashItem(at: $0, resultingItemURL: nil)
    }
  ) {
    self.directory = directory
    self.legacyDirectory = legacyDirectory
    self.recycle = recycle
  }

  public func entries() throws -> [ReadingStyleEntry] {
    var result = ReadingStyleEntry.all
    for (folder, prefix, origin) in [
      (directory, "local:", ReadingStyleEntry.Origin.local),
      (legacyDirectory, "legacy:", .legacy),
    ] {
      guard let folder else { continue }
      for url in try children(folder) where url.pathExtension.lowercased() == "css" {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        let name = url.deletingPathExtension().lastPathComponent
        result.append(.init(id: prefix + name, title: name, origin: origin))
      }
    }
    if let directory {
      for url in try children(directory) where url.pathExtension == "readingstyle" {
        let id = url.deletingPathExtension().lastPathComponent
        guard Self.validIdentifier(id) else { continue }
        let title = (try? metadata(url).title) ?? String(localized: "Unavailable Style")
        result.append(.init(id: "imported:" + id, title: title, origin: .imported))
      }
    }
    return result
  }

  public func load(_ id: String) throws -> DocumentStyle.Presentation {
    try Task.checkCancellation()
    if id == ReadingStyleEntry.notebook.id { return .notebook }
    if id == ReadingStyleEntry.unstyled.id { return .unstyled }
    if let entry = ReadingStyleEntry.bundled.first(where: { $0.id == id }) {
      if let cached = cache[id] { return cached }
      guard
        let url = Bundle.module.url(
          forResource: entry.title, withExtension: "css", subdirectory: "Styles")
      else { throw Failure.unavailable }
      let result = DocumentStyle.Presentation.stylesheet(
        try DocumentStylesheet(data: Data(contentsOf: url)))
      cache[id] = result
      return result
    }
    for (prefix, folder) in [("local:", directory), ("legacy:", legacyDirectory)] {
      if id.hasPrefix(prefix) {
        let name = String(id.dropFirst(prefix.count))
        guard Self.fileComponent(name) else { throw Failure.unavailable }
        if let folder,
          let file = try children(folder).first(where: {
            $0.pathExtension.lowercased() == "css"
              && $0.deletingPathExtension().lastPathComponent == name
          })
        {
          if prefix == "legacy:", ReadingStyleEntry.bundled.contains(where: { $0.title == name }) {
            let stock = try load("bundled:" + name)
            let original = try LocalPreviewResource.read(
              StyleAssetSnapshot.request(file.lastPathComponent), relativeTo: folder
            ).data
            if Data(DocumentStyle(presentation: stock).css.utf8) == original { return stock }
          }
          return .stylesheet(
            try StyleAssetSnapshot.build(
              main: file.lastPathComponent, directory: folder, parser: parser
            ).stylesheet)
        }
        if prefix == "legacy:" { return try load("bundled:" + name) }
        throw Failure.unavailable
      }
    }
    guard id.hasPrefix("imported:"), let directory else { throw Failure.unavailable }
    let identifier = String(id.dropFirst(9))
    guard Self.validIdentifier(identifier) else { throw Failure.unavailable }
    let folder = directory.appendingPathComponent(identifier).appendingPathExtension("readingstyle")
    let info = try metadata(folder)
    return .stylesheet(
      try StyleAssetSnapshot.build(main: info.main, directory: folder, parser: parser).stylesheet)
  }

  public func inspect(_ url: URL) throws -> ReadingStyleImport {
    try Task.checkCancellation()
    guard url.isFileURL, url.pathExtension.lowercased() == "css" else { throw Failure.invalidFile }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    return try inspect(
      main: url.lastPathComponent, directory: url.deletingLastPathComponent(),
      mainData: readSelectedSheet(url))
  }

  public func prepareFolder(_ url: URL) throws -> ReadingStyleFolder {
    guard url.isFileURL else { throw Failure.invalidFile }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
      throw Failure.invalidFile
    }
    let root = url.standardizedFileURL.resolvingSymlinksInPath()
    let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
    guard
      let walker = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles])
    else { throw Failure.invalidFile }
    var files: [String] = []
    var count = 0
    for case let file as URL in walker {
      try Task.checkCancellation()
      count += 1
      guard count <= 512, walker.level <= 32 else { throw StyleAssetFailure.tooComplex }
      let values = try file.resourceValues(forKeys: Set(keys))
      if values.isSymbolicLink == true {
        walker.skipDescendants()
        continue
      }
      if values.isRegularFile == true, file.pathExtension.lowercased() == "css" {
        files.append(
          file.pathComponents.suffix(walker.level).joined(separator: "/"))
      }
    }
    files.sort { $0.localizedStandardCompare($1) == .orderedAscending }
    guard !files.isEmpty else { throw Failure.emptyFolder }
    let bookmark = try url.bookmarkData(
      options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    return .init(title: url.lastPathComponent, filenames: files, bookmark: bookmark)
  }

  public func inspect(_ folder: ReadingStyleFolder, main: String) throws -> ReadingStyleImport {
    guard folder.filenames.contains(main), Self.relativePath(main) else {
      throw Failure.invalidFile
    }
    var stale = false
    let root = try URL(
      resolvingBookmarkData: folder.bookmark, options: .withSecurityScope,
      relativeTo: nil, bookmarkDataIsStale: &stale)
    let access = root.startAccessingSecurityScopedResource()
    defer { if access { root.stopAccessingSecurityScopedResource() } }
    return try inspect(main: main, directory: root)
  }

  private func inspect(main: String, directory: URL, mainData: Data? = nil) throws
    -> ReadingStyleImport
  {
    let result = try StyleAssetSnapshot.build(
      main: main, directory: directory, parser: parser, mainData: mainData)
    let name = ((main as NSString).lastPathComponent as NSString).deletingPathExtension
    let title = String(
      String.UnicodeScalarView(
        name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.prefix(128)))
    return .init(
      title: title.isEmpty ? String(localized: "Imported Style") : title,
      stylesheet: result.stylesheet, identifier: UUID().uuidString.lowercased(), main: main,
      files: result.files)
  }

  /// A CSS-file grant need not include read access to its parent directory.
  /// Open the selected leaf directly; additional resources still need folder access.
  private func readSelectedSheet(_ url: URL) throws -> Data {
    let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard descriptor >= 0 else { throw Failure.invalidFile }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      throw Failure.invalidFile
    }
    let limit = DocumentStylesheet.maximumBytes
    guard info.st_size <= limit else { throw DocumentStylesheet.Failure.tooLarge }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else {
      throw DocumentStylesheet.Failure.tooLarge
    }
    try Task.checkCancellation()
    return data
  }

  public func store(_ candidate: ReadingStyleImport) throws -> ReadingStyleEntry {
    guard let directory else { throw Failure.unavailable }
    try Task.checkCancellation()
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let staging = directory.appendingPathComponent(
      ".import-" + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: staging, withIntermediateDirectories: false)
    do {
      for (path, data) in candidate.files {
        try Task.checkCancellation()
        let target = staging.appendingPathComponent(path)
        try manager.createDirectory(
          at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
      }
      let info = Metadata(version: 1, title: candidate.title, main: candidate.main)
      try JSONEncoder().encode(info).write(
        to: staging.appendingPathComponent("Info.json"), options: .atomic)
      try Task.checkCancellation()
      let target = directory.appendingPathComponent(candidate.identifier).appendingPathExtension(
        "readingstyle")
      try manager.moveItem(at: staging, to: target)
    } catch {
      try? recycle(staging)
      throw error
    }
    return .init(id: "imported:" + candidate.identifier, title: candidate.title, origin: .imported)
  }

  public func stylesDirectory() throws -> URL {
    guard let directory else { throw Failure.unavailable }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func children(_ folder: URL) throws -> [URL] {
    let entries: [URL]
    do {
      entries = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])
    } catch let error as CocoaError
      where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile
    {
      return []
    }
    guard entries.count <= 512 else { throw StyleAssetFailure.tooComplex }
    return entries.sorted {
      $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
  }

  private func metadata(_ folder: URL) throws -> Metadata {
    let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else { throw Failure.corruptMetadata }
    defer { close(descriptor) }
    let file = openat(descriptor, "Info.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard file >= 0 else { throw Failure.corruptMetadata }
    let handle = FileHandle(fileDescriptor: file, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= 16_384,
      let data = try handle.read(upToCount: 16_385), data.count <= 16_384
    else { throw Failure.corruptMetadata }
    let result = try JSONDecoder().decode(Metadata.self, from: data)
    guard result.version == 1, Self.relativePath(result.main),
      (result.main as NSString).pathExtension.lowercased() == "css", result.title.utf8.count <= 1024
    else { throw Failure.corruptMetadata }
    return result
  }

  private static func fileComponent(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
  }
  private static func relativePath(_ path: String) -> Bool {
    !path.isEmpty && !path.hasPrefix("/")
      && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
        fileComponent(String($0))
      }
  }
  private static func validIdentifier(_ value: String) -> Bool {
    UUID(uuidString: value)?.uuidString.lowercased() == value
  }
}
