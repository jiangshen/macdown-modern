import Foundation
import Testing

@testable import EditorCore

@Suite("Editor theme library files")
struct EditorThemeRepositoryTests {
  private func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ThemeRepository-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func file(_ source: String, at url: URL) throws { try Data(source.utf8).write(to: url) }

  @Test("All 15 bundled themes match the original reader fixtures and Automatic has no override")
  func bundled() async throws {
    struct Fixtures: Decodable {
      struct Case: Decodable {
        let name: String
        let source: String
      }
      let cases: [Case]
    }
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = EditorThemeRepository(directory: root.appendingPathComponent("Library"))
    let entries = try await repo.entries()
    #expect(entries.count == 16 && Set(entries.map(\.id)).count == 16)
    #expect(try await repo.load("automatic").theme == nil)
    let url = try #require(
      Bundle.module.url(forResource: "LegacyEditorThemes", withExtension: "json"))
    let fixtures = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    for entry in EditorThemeEntry.bundled {
      let original = try #require(fixtures.cases.first { $0.name == entry.title + ".style" })
      let loaded = try await repo.load(entry.id)
      #expect(loaded.theme == (try EditorTheme.parse(original.source)), "\(entry.title)")
      #expect(loaded.notices.isEmpty, "\(entry.title)")
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Library").path))
  }

  @Test("Imports preserve exact original bytes, deduplicate and reopen without the original file")
  func imported() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("冰川.style")
    let bytes = Data("\u{FEFF}editor\r\nforeground: 112233\r\nbackground: ffffff\r\n".utf8)
    try bytes.write(to: original)
    let library = root.appendingPathComponent("Library")
    let repo = EditorThemeRepository(directory: library)
    let candidate = try await repo.inspect(original)
    let entry = try await repo.store(candidate)
    #expect(entry.title == "冰川" && entry.origin == .imported)
    #expect(try Data(contentsOf: original) == bytes)
    let duplicate = try await repo.store(candidate)
    #expect(duplicate == entry)
    #expect(try await repo.entries().count == 17)
    let digest = String(entry.id.dropFirst("imported:".count))
    let stored = library.appendingPathComponent(digest).appendingPathExtension("theme")
      .appendingPathComponent("source.style")
    #expect(try Data(contentsOf: stored) == bytes)
    try FileManager.default.removeItem(at: original)
    let reopened = EditorThemeRepository(directory: library)
    #expect(try await reopened.entries().contains(entry))
    #expect(try await reopened.load(entry.id).theme == candidate.theme)
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.path).count == 1)
  }

  @Test("MacDown files override stock names, remain editable and are never changed by discovery")
  func legacy() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacy = root.appendingPathComponent("MacDown")
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let custom = legacy.appendingPathComponent("Writer.STYLE")
    let first = "editor\nforeground: 010203\n"
    try file(first, at: custom)
    let repo = EditorThemeRepository(
      directory: root.appendingPathComponent("Library"), legacyDirectory: legacy)
    #expect(try await repo.entries().contains { $0.id == "legacy:Writer" })
    #expect(try await repo.load("legacy:Writer").theme == EditorTheme.parse(first))
    #expect(try await repo.load("legacy:Writer").theme != repo.load("bundled:Writer").theme)
    let changed = "editor\nforeground: aabbcc\n"
    try file(changed, at: custom)
    #expect(try await repo.load("legacy:Writer").theme == EditorTheme.parse(changed))
    #expect(try String(contentsOf: custom, encoding: .utf8) == changed)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Library").path))
    #expect(EditorThemeEntry.savedSelection(nil, legacy: "Writer.style") == "legacy:Writer")
    #expect(EditorThemeEntry.savedSelection("automatic", legacy: "Writer") == "automatic")
    let fallback = EditorThemeRepository(directory: root.appendingPathComponent("Elsewhere"))
    #expect(try await fallback.load("legacy:Writer").theme == fallback.load("bundled:Writer").theme)
  }

  @Test("Invalid encoding, oversized data, NULs, empty themes and non-files fail explicitly")
  func invalidFiles() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repo = EditorThemeRepository(directory: root.appendingPathComponent("Library"))
    let url = root.appendingPathComponent("Input.style")
    try Data([0xff]).write(to: url)
    await #expect(throws: EditorThemeRepository.Failure.invalidEncoding) {
      try await repo.inspect(url)
    }
    try Data(repeating: 32, count: EditorTheme.maximumBytes + 1).write(to: url)
    await #expect(throws: EditorTheme.ParseError.tooLarge) { try await repo.inspect(url) }
    try file("editor\nforeground: 112233\n\0", at: url)
    await #expect(throws: EditorTheme.ParseError.containsNul) { try await repo.inspect(url) }
    try file("# Only a comment", at: url)
    await #expect(throws: EditorThemeRepository.Failure.emptyTheme) { try await repo.inspect(url) }
    let folder = root.appendingPathComponent("Folder.style")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    await #expect(throws: EditorThemeRepository.Failure.invalidFile) {
      try await repo.inspect(folder)
    }
    await #expect(throws: EditorThemeRepository.Failure.invalidFile) {
      try await repo.inspect(root.appendingPathComponent("Input.md"))
    }
    for id in [
      "../secret", "legacy:../secret", "legacy:/secret", "imported:../secret",
      "imported:" + String(repeating: "A", count: 64),
    ] {
      await #expect(throws: EditorThemeRepository.Failure.unavailable) { try await repo.load(id) }
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Library").path))
  }

  @Test("Import review includes recoverable diagnostics, ignored settings and large fonts")
  func notices() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("Review.style")
    try file(
      "editor\nfont-size: 4096px\ncustom-setting: retained\n\nH7\nforeground: 112233\n\neditor-selection\nfont-size: 99px\nfont-style: bold\n",
      at: url)
    let repo = EditorThemeRepository(directory: root.appendingPathComponent("Library"))
    let review = try await repo.inspect(url)
    #expect(!review.theme.diagnostics.isEmpty)
    #expect(review.notices.count >= 3)
    #expect(review.theme.rules.flatMap(\.attributes).contains { $0.name == "custom-setting" })
  }

  @Test("One damaged import stays visible without hiding other themes or executing source")
  func damaged() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent(String(repeating: "f", count: 64))
      .appendingPathExtension("theme")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try file("not JSON", at: folder.appendingPathComponent("Info.json"))
    let repo = EditorThemeRepository(directory: root)
    let entries = try await repo.entries()
    #expect(entries.count == 17 && entries.last?.title.contains("Unavailable") == true)
    #expect(try await repo.load("bundled:Writer").theme != nil)
    #expect(try await repo.load("automatic").theme == nil)
    await #expect(throws: (any Error).self) {
      try await repo.load("imported:" + String(repeating: "f", count: 64))
    }
  }

  @Test(
    "Reimport repairs a damaged owned copy while recycling the old data and preserving the original"
  )
  func repair() async throws {
    let root = try directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let trash = root.appendingPathComponent("Recycled")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    let repo = EditorThemeRepository(
      directory: root.appendingPathComponent("Library"),
      recycle: { url in
        try FileManager.default.moveItem(
          at: url, to: trash.appendingPathComponent(UUID().uuidString))
      })
    let original = root.appendingPathComponent("Repair.style")
    let bytes = Data("editor\nforeground: 112233\n".utf8)
    try bytes.write(to: original)
    let candidate = try await repo.inspect(original)
    let entry = try await repo.store(candidate)
    let digest = String(entry.id.dropFirst("imported:".count))
    let stored = root.appendingPathComponent("Library").appendingPathComponent(digest)
      .appendingPathExtension("theme")
    try Data("damaged".utf8).write(to: stored.appendingPathComponent("source.style"))
    await #expect(throws: EditorThemeRepository.Failure.corruptMetadata) {
      try await repo.load(entry.id)
    }
    let repaired = try await repo.store(candidate)
    let reloaded = try await repo.load(entry.id)
    #expect(repaired.id == entry.id && reloaded.theme == candidate.theme)
    let recycled = try FileManager.default.contentsOfDirectory(
      at: trash, includingPropertiesForKeys: nil)
    #expect(recycled.count == 1)
    #expect(
      try String(
        contentsOf: #require(recycled.first).appendingPathComponent("source.style"), encoding: .utf8
      ) == "damaged")
    #expect(try Data(contentsOf: original) == bytes)
  }

}
