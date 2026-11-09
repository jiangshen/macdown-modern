import Foundation

public struct CommandLineInstallationReceipt: Equatable, Sendable {
  public let link: URL
  public let helper: URL

  public init(link: URL, helper: URL) {
    self.link = link.standardizedFileURL
    self.helper = helper.standardizedFileURL
  }
}

public enum CommandLineInstallationStatus: Equatable, Sendable {
  case absent, linked, occupied
}

public enum CommandLineInstallationError: Error, Equatable, LocalizedError, Sendable {
  case unavailableHelper, occupiedLocation, changedLink, invalidLocation
  case preservedItem(URL)

  public var errorDescription: String? {
    switch self {
    case .unavailableHelper: String(localized: "The bundled command-line tool is unavailable.")
    case .occupiedLocation:
      String(localized: "That location already contains another item. Choose a different folder.")
    case .changedLink:
      String(localized: "The command-line link has changed. Choose its location again to continue.")
    case .invalidLocation: String(localized: "Choose a local folder for the command-line tool.")
    case .preservedItem(let url):
      String(
        localized:
          "The location changed during removal. The moved item was preserved at \(url.path).")
    }
  }
}

/// The selected location contains only a symbolic link. Filesystem work stays off
/// the UI actor; creation is exclusive and removal requires the recorded target.
public enum CommandLineInstallation {
  @concurrent public static func helperIsAvailable(_ helper: URL) async -> Bool {
    isAvailable(helper)
  }

  @concurrent public static func inspect(
    _ receipt: CommandLineInstallationReceipt
  ) async throws -> CommandLineInstallationStatus {
    try status(receipt)
  }

  @concurrent public static func install(
    at link: URL, helper: URL
  ) async throws -> CommandLineInstallationReceipt {
    try Task.checkCancellation()
    guard isAvailable(helper) else { throw CommandLineInstallationError.unavailableHelper }
    let receipt = CommandLineInstallationReceipt(link: link, helper: helper)
    switch try status(receipt) {
    case .linked: return receipt
    case .occupied: throw CommandLineInstallationError.occupiedLocation
    case .absent:
      // createSymbolicLink fails if anything appears here after the status check.
      try FileManager.default.createSymbolicLink(
        at: receipt.link, withDestinationURL: receipt.helper)
      return receipt
    }
  }

  @concurrent public static func remove(_ receipt: CommandLineInstallationReceipt) async throws {
    try Task.checkCancellation()
    try removeLink(receipt)
  }

  @concurrent public static func update(
    _ receipt: CommandLineInstallationReceipt, helper: URL
  ) async throws -> CommandLineInstallationReceipt {
    try Task.checkCancellation()
    guard isAvailable(helper) else { throw CommandLineInstallationError.unavailableHelper }
    guard try status(receipt) == .linked else { throw CommandLineInstallationError.changedLink }
    let next = CommandLineInstallationReceipt(link: receipt.link, helper: helper)
    if receipt == next { return next }
    try removeLink(receipt)
    do {
      try FileManager.default.createSymbolicLink(at: next.link, withDestinationURL: next.helper)
      return next
    } catch {
      // Restore the old link exclusively. An intervening item is never replaced.
      if (try? status(receipt)) == .absent {
        try? FileManager.default.createSymbolicLink(
          at: receipt.link, withDestinationURL: receipt.helper)
      }
      throw error
    }
  }

  /// A literal POSIX shell argument, also safe for paths with quotes or metacharacters.
  public static func quotedCommand(for url: URL) -> String {
    "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func isAvailable(_ helper: URL) -> Bool {
    guard helper.isFileURL,
      (try? helper.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    else { return false }
    return FileManager.default.isExecutableFile(atPath: helper.path)
  }

  private static func status(
    _ receipt: CommandLineInstallationReceipt
  ) throws -> CommandLineInstallationStatus {
    guard receipt.link.isFileURL, receipt.helper.isFileURL,
      receipt.link.path.hasPrefix("/"), receipt.helper.path.hasPrefix("/"),
      !receipt.link.path.utf8.contains(0), !receipt.helper.path.utf8.contains(0)
    else { throw CommandLineInstallationError.invalidLocation }
    let manager = FileManager.default
    let attributes: [FileAttributeKey: Any]
    do { attributes = try manager.attributesOfItem(atPath: receipt.link.path) } catch {
      if (error as? CocoaError)?.code == .fileReadNoSuchFile { return .absent }
      throw error
    }
    guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else { return .occupied }
    let target = try manager.destinationOfSymbolicLink(atPath: receipt.link.path)
    let resolved = URL(
      fileURLWithPath: target, relativeTo: receipt.link.deletingLastPathComponent()
    ).standardizedFileURL
    return resolved == receipt.helper ? .linked : .occupied
  }

  private static func removeLink(_ receipt: CommandLineInstallationReceipt) throws {
    switch try status(receipt) {
    case .absent: return
    case .occupied: throw CommandLineInstallationError.changedLink
    case .linked: break
    }
    let manager = FileManager.default
    let staged = receipt.link.deletingLastPathComponent()
      .appendingPathComponent(".snowfolio-cli-removal-" + UUID().uuidString)
    // Move exclusively within the same folder, then check the moved item again.
    // If another process replaced the original link, preserve and restore its item.
    try manager.moveItem(at: receipt.link, to: staged)
    do {
      let moved = CommandLineInstallationReceipt(link: staged, helper: receipt.helper)
      guard try status(moved) == .linked else { throw CommandLineInstallationError.changedLink }
      try manager.removeItem(at: staged)
    } catch {
      do { try manager.moveItem(at: staged, to: receipt.link) } catch {
        throw CommandLineInstallationError.preservedItem(staged)
      }
      throw error
    }
  }
}
