import Foundation
import Testing

@testable import PluginCore

@MainActor
private final class SessionPlugin: NSObject {
  var initializations = 0
  var runs = 0
  @objc func plugInDidInitialize() { initializations += 1 }
  @objc func run(_ sender: AnyObject?) -> Bool {
    runs += 1
    return true
  }
}

@Suite("Explicit native plug-in session")
@MainActor
struct PluginSessionTests {
  private func descriptor(_ url: URL) -> PluginDescriptor {
    PluginDescriptor(
      url: url, bundleIdentifier: nil, principalClassName: "SessionPlugin",
      architectures: [0x0100_000c], availability: .compatible)
  }

  @Test("Lookup executes nothing; aliases share initialization and retained run state")
  func aliases() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("Fixture.plugin")
    try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
    let alias = root.appendingPathComponent("Alias.plugin")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
    let instance = SessionPlugin()
    var loads = 0
    let session = PluginSession { descriptor in
      loads += 1
      return try LegacyPlugin(instance: instance, fallbackName: descriptor.fallbackName)
    }
    #expect(session.loadedPlugin(at: original) == nil)
    #expect(session.loadedPlugin(at: alias) == nil)
    #expect(loads == 0)
    #expect(instance.initializations == 0)
    let first = try session.load(descriptor(original))
    #expect(first.run())
    let second = try session.load(descriptor(alias))
    #expect(second.run())
    #expect(first === second)
    #expect(session.loadedPlugin(at: alias) === first)
    #expect(loads == 1)
    #expect(instance.initializations == 1)
    #expect(instance.runs == 2)
    // Removing the on-disk bundle must not unload a live instance or reset it.
    try FileManager.default.removeItem(at: original)
    #expect(try session.load(descriptor(original)) === first)
    #expect(instance.initializations == 1)
  }

  @Test("Failed loads may retry; separate URLs and sessions have independent instances")
  func retryAndIsolation() throws {
    let firstURL = URL(fileURLWithPath: "/session-fixture/First.plugin")
    let secondURL = URL(fileURLWithPath: "/session-fixture/Second.plugin")
    var attempts = 0
    let session = PluginSession { descriptor in
      attempts += 1
      if attempts == 1 { throw PluginInvocationError.invalidBundle }
      return try LegacyPlugin(instance: SessionPlugin(), fallbackName: descriptor.fallbackName)
    }
    #expect(throws: PluginInvocationError.invalidBundle) {
      try session.load(descriptor(firstURL))
    }
    #expect(session.loadedPlugin(at: firstURL) == nil)
    let first = try session.load(descriptor(firstURL))
    let second = try session.load(descriptor(secondURL))
    #expect(first !== second)
    #expect(first.name == "First")
    #expect(second.name == "Second")
    #expect(attempts == 3)
    let otherSession = PluginSession { descriptor in
      try LegacyPlugin(instance: SessionPlugin(), fallbackName: descriptor.fallbackName)
    }
    #expect(otherSession.loadedPlugin(at: firstURL) == nil)
    #expect(try otherSession.load(descriptor(firstURL)) !== first)
  }
}
