import EditorCore
import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Editor theme choices")
@MainActor
struct EditorThemeLibraryTests {
  private func state() throws -> (URL, String, UserDefaults, EditorThemeRepository) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ThemeChoices-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let domain = "ThemeChoices." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    return (
      root, domain, defaults,
      EditorThemeRepository(directory: root.appendingPathComponent("Library"))
    )
  }

  @Test("Existing saved names, explicit Automatic and bundled selections survive reopening")
  func persistence() async throws {
    let (root, domain, defaults, repo) = try state()
    defer {
      defaults.removePersistentDomain(forName: domain)
      try? FileManager.default.removeItem(at: root)
    }
    let preferences = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["editorStyleName": "Writer"], editorThemeRepository: repo)
    let library = preferences.editorThemes
    #expect(library.selection == "legacy:Writer")
    await library.loadIfNeeded()
    #expect(library.theme == (try await repo.load("bundled:Writer").theme))
    #expect(library.entries.contains { $0.id == "legacy:Writer" })
    await library.select("automatic")
    let reopened = AppPreferences(
      defaults: defaults, domainName: domain,
      legacyValues: ["editorStyleName": "Mou Night"], editorThemeRepository: repo)
    #expect(reopened.editorThemes.selection == "automatic")
    await reopened.editorThemes.select("bundled:Mou Night")
    let again = EditorThemeLibrary(defaults: defaults, repository: repo)
    await again.loadIfNeeded()
    #expect(again.selection == "bundled:Mou Night" && again.theme == reopened.editorThemes.theme)
    #expect(defaults.string(forKey: "editorStyleName") == "Mou Night")
  }

  @Test(
    "Imported selection persists, unavailable choices retain the last good appearance and can recover"
  )
  func importsAndFailure() async throws {
    let (root, domain, defaults, repo) = try state()
    defer {
      defaults.removePersistentDomain(forName: domain)
      try? FileManager.default.removeItem(at: root)
    }
    let file = root.appendingPathComponent("Custom.style")
    try Data("editor\nforeground: 112233\nbackground: ffffff\n".utf8).write(to: file)
    let library = EditorThemeLibrary(defaults: defaults, repository: repo)
    let inspected = try await library.inspect(file)
    try await library.importTheme(inspected)
    #expect(library.selection.hasPrefix("imported:") && library.theme == inspected.theme)
    let reopened = EditorThemeLibrary(defaults: defaults, repository: repo)
    await reopened.loadIfNeeded()
    #expect(reopened.selection == library.selection && reopened.theme == library.theme)
    let goodID = reopened.theme?.id
    await reopened.select("imported:unavailable")
    #expect(reopened.theme?.id == goodID && reopened.message != nil && !reopened.isLoading)
    #expect(reopened.entries.contains { $0.id == reopened.selection })
    #expect(defaults.string(forKey: "editorThemeSelection") == "imported:unavailable")
    await reopened.select("automatic")
    #expect(reopened.theme == nil && reopened.message == nil)
  }

  @Test("Canceling a view waiter cannot strand the shared library, and a later choice wins")
  func cancellationAndSelection() async throws {
    let (root, domain, defaults, repo) = try state()
    defer {
      defaults.removePersistentDomain(forName: domain)
      try? FileManager.default.removeItem(at: root)
    }
    let library = EditorThemeLibrary(defaults: defaults, repository: repo)
    let waiter = Task { await library.loadIfNeeded() }
    waiter.cancel()
    await waiter.value
    #expect(!library.isLoading && library.entries.count == 16)
    let first = Task { await library.select("bundled:Writer") }
    for _ in 0..<100 where library.selection != "bundled:Writer" { await Task.yield() }
    #expect(library.selection == "bundled:Writer")
    await library.select("bundled:Mou Night")
    await first.value
    let expected = try await repo.load("bundled:Mou Night")
    #expect(library.selection == "bundled:Mou Night" && library.theme == expected.theme)
    #expect(!library.isLoading && library.message == nil)
  }
}
