import Foundation
import Testing

@testable import DocumentCore

@Suite("Command-line installation ownership")
struct CommandLineInstallationTests {
  private func fixture() throws -> (root: URL, helper: URL, link: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let helper = root.appendingPathComponent("tool ' 🧊 $() `quoted`")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    return (root, helper, root.appendingPathComponent("snowfolio"))
  }

  @Test("Installation is idempotent and removing the link preserves its executable")
  func roundTrip() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let original = try Data(contentsOf: f.helper)
    let receipt = try await CommandLineInstallation.install(at: f.link, helper: f.helper)
    #expect(try await CommandLineInstallation.inspect(receipt) == .linked)
    #expect(try await CommandLineInstallation.install(at: f.link, helper: f.helper) == receipt)
    try await CommandLineInstallation.remove(receipt)
    try await CommandLineInstallation.remove(receipt)
    #expect(try await CommandLineInstallation.inspect(receipt) == .absent)
    #expect(try Data(contentsOf: f.helper) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.root.path).count == 1)
  }

  @Test("Files, directories and foreign links are never replaced", arguments: [0, 1, 2, 3])
  func collision(kind: Int) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let other = f.root.appendingPathComponent("other")
    try Data("User contents".utf8).write(to: other)
    switch kind {
    case 0: try Data("Keep me".utf8).write(to: f.link)
    case 1:
      try FileManager.default.createDirectory(at: f.link, withIntermediateDirectories: false)
      try Data("Keep child".utf8).write(to: f.link.appendingPathComponent("child.md"))
    default:
      try FileManager.default.createSymbolicLink(
        at: f.link, withDestinationURL: kind == 2 ? other : other.appendingPathExtension("missing"))
    }
    let receipt = CommandLineInstallationReceipt(link: f.link, helper: f.helper)
    #expect(try await CommandLineInstallation.inspect(receipt) == .occupied)
    await #expect(throws: CommandLineInstallationError.occupiedLocation) {
      try await CommandLineInstallation.install(at: f.link, helper: f.helper)
    }
    await #expect(throws: CommandLineInstallationError.changedLink) {
      try await CommandLineInstallation.remove(receipt)
    }
    #expect(try Data(contentsOf: other) == Data("User contents".utf8))
    switch kind {
    case 0: #expect(try Data(contentsOf: f.link) == Data("Keep me".utf8))
    case 1:
      #expect(
        try Data(contentsOf: f.link.appendingPathComponent("child.md")) == Data("Keep child".utf8))
    default:
      #expect(
        try FileManager.default.destinationOfSymbolicLink(atPath: f.link.path) != f.helper.path)
    }
  }

  @Test("A relocated app updates only its recorded link and supports removing a dangling link")
  func relocation() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let first = try await CommandLineInstallation.install(at: f.link, helper: f.helper)
    let nextHelper = f.root.appendingPathComponent("new helper")
    try FileManager.default.moveItem(at: f.helper, to: nextHelper)
    #expect(try await CommandLineInstallation.inspect(first) == .linked)
    let next = try await CommandLineInstallation.update(first, helper: nextHelper)
    #expect(next.helper == nextHelper)
    #expect(try await CommandLineInstallation.inspect(next) == .linked)
    try FileManager.default.removeItem(at: nextHelper)
    try await CommandLineInstallation.remove(next)
    #expect(try await CommandLineInstallation.inspect(next) == .absent)
  }

  @Test("An unavailable replacement leaves the old installation intact")
  func unavailableUpdate() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let receipt = try await CommandLineInstallation.install(at: f.link, helper: f.helper)
    await #expect(throws: CommandLineInstallationError.unavailableHelper) {
      try await CommandLineInstallation.update(
        receipt, helper: f.root.appendingPathComponent("missing"))
    }
    #expect(try await CommandLineInstallation.inspect(receipt) == .linked)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.helper.path)
    #expect(await CommandLineInstallation.helperIsAvailable(f.helper) == false)
  }

  @Test("Parent folders are not created implicitly and non-file locations fail")
  func locations() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let missing = f.root.appendingPathComponent("missing", isDirectory: true)
    await #expect(throws: (any Error).self) {
      try await CommandLineInstallation.install(
        at: missing.appendingPathComponent("snowfolio"), helper: f.helper)
    }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    let remote = try #require(URL(string: "https://example.invalid/snowfolio"))
    await #expect(throws: CommandLineInstallationError.invalidLocation) {
      try await CommandLineInstallation.install(at: remote, helper: f.helper)
    }
  }

  @Test("Relative symbolic links to the same helper can be adopted and removed")
  func relative() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    try FileManager.default.createSymbolicLink(
      atPath: f.link.path, withDestinationPath: f.helper.lastPathComponent)
    let receipt = try await CommandLineInstallation.install(at: f.link, helper: f.helper)
    #expect(try await CommandLineInstallation.inspect(receipt) == .linked)
    try await CommandLineInstallation.remove(receipt)
    #expect(try Data(contentsOf: f.helper) == Data("#!/bin/sh\nexit 0\n".utf8))
  }

  @Test("Copied commands preserve quotes, Unicode and literal shell metacharacters")
  func quotedCommand() throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.root) }
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = [
      "-c", "printf '%s' " + CommandLineInstallation.quotedCommand(for: f.helper),
    ]
    process.standardOutput = output
    try process.run()
    let bytes = try output.fileHandleForReading.readToEnd() ?? Data()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    #expect(String(decoding: bytes, as: UTF8.self) == f.helper.path)
  }
}
