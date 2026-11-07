import Foundation
import Testing

@testable import RenderingCore

@Suite("Editable and imported reading styles")
struct ReadingStyleRepositoryTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test(
    "Folder grants import nested CSS and assets atomically, then reload edits independently of originals"
  )
  func folderImport() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appending(path: "Original")
    let saved = root.appending(path: "Saved")
    try FileManager.default.createDirectory(
      at: original.appending(path: "styles"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: original.appending(path: "parts"), withIntermediateDirectories: true)
    let main = Data("@import '../parts/color.css'; p{background:url('../ice.png')}".utf8)
    let child = Data("p { color: purple }".utf8)
    let image = Data([1, 2, 3, 4])
    try main.write(to: original.appending(path: "styles/Arctic.css"))
    try child.write(to: original.appending(path: "parts/color.css"))
    try image.write(to: original.appending(path: "ice.png"))
    let repository = ReadingStyleRepository(directory: saved)
    #expect(try await repository.entries() == ReadingStyleEntry.all)
    let grant = try await repository.prepareFolder(original)
    #expect(grant.filenames == ["parts/color.css", "styles/Arctic.css"])
    let candidate = try await repository.inspect(grant, main: "styles/Arctic.css")
    let entry = try await repository.store(candidate)
    #expect(entry.title == "Arctic" && entry.origin == .imported)
    #expect(try await repository.entries().contains(entry))
    #expect(
      DocumentStyle(presentation: try await repository.load(entry.id)).css
        == candidate.stylesheet.css)
    #expect(try Data(contentsOf: original.appending(path: "styles/Arctic.css")) == main)
    #expect(try Data(contentsOf: original.appending(path: "parts/color.css")) == child)
    try FileManager.default.removeItem(at: original)
    let storedFolder = saved.appendingPathComponent(String(entry.id.dropFirst(9)))
      .appendingPathExtension("readingstyle")
    #expect(try Data(contentsOf: storedFolder.appending(path: "ice.png")) == image)
    #expect(
      DocumentStyle(presentation: try await repository.load(entry.id)).css
        == candidate.stylesheet.css)
    try Data("p { color: blue }".utf8).write(to: storedFolder.appending(path: "parts/color.css"))
    let edited = try await repository.load(entry.id)
    #expect(DocumentStyle(presentation: edited).css != candidate.stylesheet.css)
    #expect(candidate.stylesheet.css.contains("data:text/css;base64,"))
    #expect(try await repository.stylesDirectory() == saved)
  }

  @Test(
    "Local and legacy names coexist, uppercase extensions reload, and cancelled imports publish nothing"
  )
  func catalogAndCancellation() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let local = root.appending(path: "Local")
    let legacy = root.appending(path: "Legacy")
    for folder in [local, legacy] {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    try Data("body{color:red}".utf8).write(to: local.appending(path: "Ice.CSS"))
    try Data("body{color:blue}".utf8).write(to: legacy.appending(path: "Ice.css"))
    let repository = ReadingStyleRepository(directory: local, legacyDirectory: legacy)
    let entries = try await repository.entries()
    #expect(entries.contains { $0.id == "local:Ice" && $0.origin == .local })
    #expect(entries.contains { $0.id == "legacy:Ice" && $0.origin == .legacy })
    #expect(DocumentStyle(presentation: try await repository.load("local:Ice")).css.contains("red"))
    #expect(
      DocumentStyle(presentation: try await repository.load("legacy:Ice")).css.contains("blue"))
    try Data("body{color:green}".utf8).write(to: local.appending(path: "Ice.CSS"))
    #expect(
      DocumentStyle(presentation: try await repository.load("local:Ice")).css.contains("green"))
    let candidate = try await repository.inspect(local.appending(path: "Ice.CSS"))
    let operation = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await repository.store(candidate)
    }
    await #expect(throws: CancellationError.self) { try await operation.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: local.path) == ["Ice.CSS"])
    await #expect(throws: ReadingStyleRepository.Failure.unavailable) {
      try await repository.load("local:../Ice")
    }
    await #expect(throws: ReadingStyleRepository.Failure.unavailable) {
      try await repository.load("imported:../Ice")
    }
  }

  @Test("Malformed CSS, oversized sheets and excessive asset counts fail before import")
  func limits() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appending(path: "main.css")
    let repository = ReadingStyleRepository()
    try Data("p { background: url('missing.png'); broken }".utf8).write(to: file)
    await #expect(throws: StyleAssetFailure.unsupportedSyntax) {
      try await repository.inspect(file)
    }
    try Data(repeating: 65, count: DocumentStylesheet.maximumBytes + 1).write(to: file)
    await #expect(throws: DocumentStylesheet.Failure.tooLarge) {
      try await repository.inspect(file)
    }
    var css = ""
    for index in 0..<129 {
      try Data([1]).write(to: root.appending(path: "\(index).png"))
      css += ".x\(index){background:url(\(index).png)}"
    }
    try Data(css.utf8).write(to: file)
    await #expect(throws: StyleAssetFailure.tooComplex) { try await repository.inspect(file) }
    // The same confined engine must recover after a failed parse/resolve.
    try Data("p{color:purple}".utf8).write(to: file)
    #expect(try await repository.inspect(file).stylesheet.css == "p{color:purple}")
    try Data().write(to: file)
    #expect(try await repository.inspect(file).stylesheet.css.isEmpty)
  }
  @Test("A selected standalone CSS file does not require directory enumeration permission")
  func selectedFileGrant() async throws {
    let root = try folder()
    let file = root.appending(path: "Standalone.css")
    try Data("body{color:purple}".utf8).write(to: file)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
      try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o111], ofItemAtPath: root.path)
    let repository = ReadingStyleRepository()
    let candidate = try await repository.inspect(file)
    #expect(candidate.stylesheet.css == "body{color:purple}")
  }

}
