import Darwin
import Foundation
import UniformTypeIdentifiers

public enum LocalPreviewResourceError: Error, Equatable, Sendable {
  case forbiddenURL
  case outsideDocumentDirectory
  case unsupportedType
  case tooLarge
}

public struct LocalPreviewResource: Sendable {
  public let data: Data
  public let mimeType: String

  public static func resolve(_ request: URL, relativeTo directory: URL) throws -> URL {
    guard request.scheme == "mdasset", request.host == "document", directory.isFileURL else {
      throw LocalPreviewResourceError.forbiddenURL
    }
    let root = directory.standardizedFileURL.resolvingSymlinksInPath()
    let relative = String(request.path.drop(while: { $0 == "/" }))
    let candidate = root.appendingPathComponent(relative).standardizedFileURL
    var cursor = root
    for component in candidate.pathComponents.dropFirst(root.pathComponents.count) {
      cursor.appendPathComponent(component)
      if (try? cursor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
        throw LocalPreviewResourceError.outsideDocumentDirectory
      }
    }
    let file = candidate.resolvingSymlinksInPath()
    guard file.pathComponents.starts(with: root.pathComponents), file != root else {
      throw LocalPreviewResourceError.outsideDocumentDirectory
    }
    let allowed = Set([
      "png", "jpg", "jpeg", "gif", "webp", "avif", "heic", "svg", "css", "woff", "woff2", "ttf",
      "otf",
    ])
    guard allowed.contains(file.pathExtension.lowercased()) else {
      throw LocalPreviewResourceError.unsupportedType
    }
    return file
  }

  @concurrent
  public static func load(_ request: URL, relativeTo directory: URL) async throws -> Self {
    try Task.checkCancellation()
    let file = try resolve(request, relativeTo: directory)
    // Open each component relative to an owned directory descriptor. O_NOFOLLOW
    // closes the gap between validation and reading if a symlink changes meanwhile.
    let root = directory.standardizedFileURL.resolvingSymlinksInPath()
    var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
    defer { close(descriptor) }
    let components = Array(file.pathComponents.dropFirst(root.pathComponents.count))
    for component in components.dropLast() {
      let next = openat(descriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      guard next >= 0 else { throw LocalPreviewResourceError.forbiddenURL }
      close(descriptor)
      descriptor = next
    }
    guard let leaf = components.last else { throw LocalPreviewResourceError.forbiddenURL }
    let resourceDescriptor = openat(
      descriptor, leaf, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard resourceDescriptor >= 0 else { throw LocalPreviewResourceError.forbiddenURL }
    let handle = FileHandle(fileDescriptor: resourceDescriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(resourceDescriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      throw LocalPreviewResourceError.forbiddenURL
    }
    let limit = 32 * 1_024 * 1_024
    guard info.st_size <= limit else { throw LocalPreviewResourceError.tooLarge }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw LocalPreviewResourceError.tooLarge }
    try Task.checkCancellation()
    let mime =
      UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    return Self(data: data, mimeType: mime)
  }
}
