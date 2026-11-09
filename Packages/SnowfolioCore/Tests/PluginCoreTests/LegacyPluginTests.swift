import Foundation
import Testing

@testable import PluginCore

@MainActor
private final class LocalPlugin: NSObject {
  var initializations = 0
  var senders: [AnyObject?] = []
  @objc var name: String { "Local fixture 🧊" }
  @objc func plugInDidInitialize() { initializations += 1 }
  @objc func run(_ sender: AnyObject?) -> Bool {
    senders.append(sender)
    return sender != nil
  }
}

@MainActor
private final class MinimalPlugin: NSObject {
  @objc func run(_ sender: AnyObject?) -> Bool { true }
}

@MainActor
private final class VoidPlugin: NSObject {
  var initialized = false
  @objc func plugInDidInitialize() { initialized = true }
  @objc func run(_ sender: AnyObject?) {}
}

@MainActor
private final class WrongArgumentPlugin: NSObject {
  @objc func run(_ sender: Int) -> Bool { true }
}

@MainActor
private final class WrongNamePlugin: NSObject {
  var initialized = false
  @objc func plugInDidInitialize() { initialized = true }
  @objc var name: Int { 7 }
  @objc func run(_ sender: AnyObject?) -> Bool { true }
}

@MainActor
private final class WrongInitializationPlugin: NSObject {
  @objc func plugInDidInitialize() -> Bool { true }
  @objc func run(_ sender: AnyObject?) -> Bool { true }
}

@Suite("Original plug-in invocation contract")
@MainActor
struct LegacyPluginTests {
  @Test("A retained instance initializes once, preserves its name, sender identity and BOOL result")
  func invocation() throws {
    let instance = LocalPlugin()
    let plugin = try LegacyPlugin(instance: instance, fallbackName: "Filename")
    #expect(plugin.name == "Local fixture 🧊")
    #expect(instance.initializations == 1)
    let sender = NSObject()
    #expect(plugin.run(sender: sender))
    #expect(!plugin.run())
    #expect(plugin.run(sender: sender))
    #expect(instance.initializations == 1)
    #expect(instance.senders.count == 3)
    #expect(instance.senders[0] === sender)
    #expect(instance.senders[1] == nil)
    #expect(instance.senders[2] === sender)
  }

  @Test("Optional name and initialization are not required")
  func optionalCallbacks() throws {
    let plugin = try LegacyPlugin(instance: MinimalPlugin(), fallbackName: "Filename 中文")
    #expect(plugin.name == "Filename 中文")
    #expect(plugin.run())
    let noRun = try LegacyPlugin(instance: NSObject(), fallbackName: "No run callback")
    #expect(!noRun.run())
  }

  @Test("Malformed selectors are rejected before initialization or invocation")
  func signatures() throws {
    let invalidRun = VoidPlugin()
    #expect(throws: PluginInvocationError.invalidSignature("run:")) {
      try LegacyPlugin(instance: invalidRun, fallbackName: "Invalid")
    }
    #expect(!invalidRun.initialized)
    #expect(throws: PluginInvocationError.invalidSignature("run:")) {
      try LegacyPlugin(instance: WrongArgumentPlugin(), fallbackName: "Invalid")
    }
    let invalidName = WrongNamePlugin()
    #expect(throws: PluginInvocationError.invalidSignature("name")) {
      try LegacyPlugin(instance: invalidName, fallbackName: "Invalid")
    }
    #expect(!invalidName.initialized)
    #expect(throws: PluginInvocationError.invalidSignature("plugInDidInitialize")) {
      try LegacyPlugin(instance: WrongInitializationPlugin(), fallbackName: "Invalid")
    }
  }
}
