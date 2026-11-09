import Foundation

/// Retains explicitly loaded native plug-ins for the lifetime of the app session.
/// Discovery and menu refreshes must not call `load` until the user chooses to run
/// trusted code. Loaded bundles cannot safely be replaced or unloaded in-process;
/// changes to them take effect after restarting the app.
@MainActor
public final class PluginSession {
  private var plugins: [String: LegacyPlugin] = [:]
  private let loader: @MainActor (PluginDescriptor) throws -> LegacyPlugin

  public init() {
    loader = { try LegacyPlugin(descriptor: $0) }
  }

  init(loader: @escaping @MainActor (PluginDescriptor) throws -> LegacyPlugin) {
    self.loader = loader
  }

  /// A nonexecuting lookup, suitable for displaying a previously loaded name.
  public func loadedPlugin(at url: URL) -> LegacyPlugin? {
    plugins[Self.key(for: url)]
  }

  /// Explicit code-execution boundary. Failures are not cached so a user can
  /// retry a repaired bundle that has never loaded successfully in this session.
  public func load(_ descriptor: PluginDescriptor) throws -> LegacyPlugin {
    let key = Self.key(for: descriptor.url)
    if let plugin = plugins[key] { return plugin }
    let plugin = try loader(descriptor)
    plugins[key] = plugin
    return plugin
  }

  private static func key(for url: URL) -> String {
    // File URLs may gain a directory slash only while the bundle exists. A path
    // key keeps the retained instance stable if that bundle is later removed.
    url.resolvingSymlinksInPath().standardizedFileURL.path
  }
}
