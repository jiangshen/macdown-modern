import Foundation
import ObjectiveC

public enum PluginInvocationError: Error, Equatable, Sendable, LocalizedError {
  case invalidBundle, incompatibleArchitecture, missingPrincipalClass
  case invalidSignature(String)

  public var errorDescription: String? {
    switch self {
    case .invalidBundle:
      String(localized: "This is not a valid native plug-in bundle.")
    case .incompatibleArchitecture:
      String(localized: "This plug-in is not compatible with Apple silicon.")
    case .missingPrincipalClass:
      String(localized: "The plug-in does not provide a supported principal class.")
    case .invalidSignature(let callback):
      String(localized: "The plug-in’s “\(callback)” callback has an unsupported signature.")
    }
  }
}

/// Explicit execution boundary for the original optional name/initialization and
/// BOOL run: contract. Construct only after the user chooses to run a plug-in.
/// All Objective-C callbacks stay on the app actor because they may use AppKit.
@MainActor
public final class LegacyPlugin {
  public let name: String
  private let instance: NSObject
  private let runMethod: Method?

  public convenience init(descriptor: PluginDescriptor) throws {
    guard descriptor.availability == .compatible else {
      throw PluginInvocationError.incompatibleArchitecture
    }
    guard let bundle = Bundle(url: descriptor.url) else {
      throw PluginInvocationError.invalidBundle
    }
    try bundle.loadAndReturnError()
    guard let type = bundle.principalClass as? NSObject.Type else {
      throw PluginInvocationError.missingPrincipalClass
    }
    try self.init(instance: type.init(), fallbackName: descriptor.fallbackName)
  }

  init(instance: NSObject, fallbackName: String) throws {
    // Validate every optional callback before invoking any of them. A malformed
    // ABI must never be guessed from responds(to:) alone.
    let run =
      instance.responds(to: NSSelectorFromString("run:"))
      ? try Self.method(instance, "run:", result: "B", arguments: ["@", ":", "@"])
      : nil
    let initialize =
      instance.responds(to: NSSelectorFromString("plugInDidInitialize"))
      ? try Self.method(instance, "plugInDidInitialize", result: "v", arguments: ["@", ":"])
      : nil
    let getter =
      instance.responds(to: NSSelectorFromString("name"))
      ? try Self.method(instance, "name", result: "@", arguments: ["@", ":"])
      : nil
    self.instance = instance
    runMethod = run
    if getter != nil,
      let title = instance.perform(NSSelectorFromString("name"))?.takeUnretainedValue() as? String,
      !title.isEmpty
    {
      name = title
    } else {
      name = fallbackName
    }
    if let initialize {
      let function = unsafeBitCast(
        method_getImplementation(initialize),
        to: (@convention(c) (AnyObject, Selector) -> Void).self)
      function(instance, NSSelectorFromString("plugInDidInitialize"))
    }
  }

  @discardableResult
  public func run(sender: AnyObject? = nil) -> Bool {
    guard let runMethod else { return false }
    let function = unsafeBitCast(
      method_getImplementation(runMethod),
      to: (@convention(c) (AnyObject, Selector, AnyObject?) -> Bool).self)
    return function(instance, NSSelectorFromString("run:"), sender)
  }

  private static func method(
    _ object: NSObject, _ name: String, result: String, arguments: [String]
  ) throws -> Method {
    let selector = NSSelectorFromString(name)
    guard let method = class_getInstanceMethod(type(of: object), selector),
      method_getNumberOfArguments(method) == arguments.count
    else { throw PluginInvocationError.invalidSignature(name) }
    let encoded = method_copyReturnType(method)
    defer { free(encoded) }
    guard String(cString: encoded) == result else {
      throw PluginInvocationError.invalidSignature(name)
    }
    for (index, expected) in arguments.enumerated() {
      guard let encoded = method_copyArgumentType(method, UInt32(index)) else {
        throw PluginInvocationError.invalidSignature(name)
      }
      defer { free(encoded) }
      // An Objective-C object type may include its quoted class/protocol name.
      let actual = String(cString: encoded)
      guard actual == expected || expected == "@" && actual.hasPrefix("@\"") else {
        throw PluginInvocationError.invalidSignature(name)
      }
    }
    return method
  }
}
