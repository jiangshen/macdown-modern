import Foundation

/// Executable architecture eligibility only; signing and callback validity are
/// checked at explicit load/invocation, never inferred from this metadata.
public enum PluginAvailability: Equatable, Sendable {
  case compatible, intelOnly, unsupportedArchitecture, invalidBundle
}

/// Metadata only. Reading this value never loads an executable or principal class.
public struct PluginDescriptor: Equatable, Sendable, Identifiable {
  public let url: URL
  public let bundleIdentifier: String?
  public let principalClassName: String?
  public let architectures: [Int]
  public let availability: PluginAvailability
  public var id: URL { url }
  public var fallbackName: String { url.deletingPathExtension().lastPathComponent }
}

public struct PluginFolderIssue: Equatable, Sendable {
  public let folder: URL
  public let message: String
}

public struct PluginInventory: Equatable, Sendable {
  public let plugins: [PluginDescriptor]
  public let issues: [PluginFolderIssue]
}

public enum PluginCatalog {
  /// Missing folders are normal. Discovery creates nothing and executes no code.
  /// Explicit folders make legacy migration and disposable fixtures independent
  /// of the user's actual Application Support directories.
  @concurrent public static func discover(in folders: [URL]) async throws -> PluginInventory {
    let manager = FileManager.default
    var plugins: [PluginDescriptor] = []
    var issues: [PluginFolderIssue] = []
    var visited: Set<URL> = []
    for folder in folders {
      try Task.checkCancellation()
      guard folder.isFileURL else {
        issues.append(
          PluginFolderIssue(
            folder: folder, message: String(localized: "Choose a local plug-in folder.")))
        continue
      }
      do {
        let entries = try manager.contentsOfDirectory(
          at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles])
        for url in entries where url.pathExtension.lowercased() == "plugin" {
          try Task.checkCancellation()
          let canonical = url.resolvingSymlinksInPath().standardizedFileURL
          guard visited.insert(canonical).inserted else { continue }
          plugins.append(describe(url.standardizedFileURL))
        }
      } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        continue
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        issues.append(PluginFolderIssue(folder: folder, message: error.localizedDescription))
      }
    }
    plugins.sort { $0.url.path < $1.url.path }
    return PluginInventory(plugins: plugins, issues: issues)
  }

  private static func describe(_ url: URL) -> PluginDescriptor {
    let bundle = Bundle(url: url)
    let principal = bundle?.object(forInfoDictionaryKey: "NSPrincipalClass") as? String
    let architectures = bundle?.executableArchitectures?.map(\.intValue).sorted() ?? []
    let valid =
      principal?.isEmpty == false && bundle?.executableURL != nil && !architectures.isEmpty
    let availability: PluginAvailability
    if !valid {
      availability = .invalidBundle
    } else if architectures.contains(0x0100_000c) {
      availability = .compatible
    } else if architectures.allSatisfy({ $0 == 7 || $0 == 0x0100_0007 }) {
      availability = .intelOnly
    } else {
      availability = .unsupportedArchitecture
    }
    return PluginDescriptor(
      url: url, bundleIdentifier: bundle?.bundleIdentifier,
      principalClassName: principal, architectures: architectures, availability: availability)
  }
}
