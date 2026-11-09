import DocumentCore
import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Terminal Settings installation state")
@MainActor
struct CommandLineToolSettingsTests {
  @Test("Install, relaunch, relocate, update and remove preserve the user-selected location")
  func lifecycle() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let domain = "CommandLineToolSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let helper = root.appendingPathComponent("helper")
    try Data("original helper".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    let model = CommandLineToolSettings(defaults: defaults, helper: helper)
    await model.refresh()
    #expect(model.helperAvailable && model.status == .absent && model.receipt == nil)
    await model.install(in: root)
    #expect(model.status == .linked && model.message == nil && !model.isBusy)
    let link = root.appendingPathComponent("snowfolio")
    #expect(model.receipt?.link == link)
    let moved = root.appendingPathComponent("moved helper")
    try FileManager.default.moveItem(at: helper, to: moved)
    let reopened = CommandLineToolSettings(defaults: defaults, helper: moved)
    await reopened.refresh()
    #expect(reopened.receipt == model.receipt && reopened.needsUpdate)
    await reopened.update()
    #expect(!reopened.needsUpdate && reopened.receipt?.helper == moved)
    #expect(reopened.command == CommandLineInstallation.quotedCommand(for: link))
    let final = CommandLineToolSettings(defaults: defaults, helper: moved)
    await final.refresh()
    #expect(final.receipt == reopened.receipt && final.status == .linked)
    await final.remove()
    #expect(final.status == .absent && final.receipt == nil && final.message == nil)
    #expect(defaults.object(forKey: CommandLineToolSettings.receiptKey) == nil)
    #expect(try Data(contentsOf: moved) == Data("original helper".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["moved helper"])
  }

  @Test("Replacing an installed link with a user file blocks removal and preserves its receipt")
  func replacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let domain = "CommandLineToolSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let helper = root.appendingPathComponent("helper")
    try Data("helper".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
    let model = CommandLineToolSettings(defaults: defaults, helper: helper)
    await model.install(in: root)
    let receipt = try #require(model.receipt)
    try FileManager.default.removeItem(at: receipt.link)
    try Data("user document".utf8).write(to: receipt.link)
    await model.refresh()
    #expect(model.status == .occupied)
    await model.remove()
    #expect(model.receipt == receipt && model.message != nil && model.status == .occupied)
    #expect(try Data(contentsOf: receipt.link) == Data("user document".utf8))
    #expect(
      defaults.dictionary(forKey: CommandLineToolSettings.receiptKey)?["link"] as? String
        == receipt.link.path)
    #expect(model.command == CommandLineInstallation.quotedCommand(for: helper))
  }

  @Test("Malformed saved paths and missing helper never create an installation")
  func invalid() async throws {
    let domain = "CommandLineToolSettingsTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(
      ["link": "relative/path", "helper": "/missing/helper"],
      forKey: CommandLineToolSettings.receiptKey)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = CommandLineToolSettings(
      defaults: defaults, helper: root.appendingPathComponent("helper"))
    await model.refresh()
    await model.install(in: root)
    #expect(!model.helperAvailable && model.receipt == nil && model.message != nil)
    #expect(!FileManager.default.fileExists(atPath: root.path))
    #expect(
      defaults.dictionary(forKey: CommandLineToolSettings.receiptKey)?["link"] as? String
        == "relative/path")
  }
}
