import Foundation
import Observation
import SwiftUI

/// Published release metadata only. Persisted preferences can never substitute a
/// feed or public key from the app the user originally migrated away from.
public struct ApplicationUpdateConfiguration: Equatable, Sendable {
  public let feedURL: URL
  public let publicKey: String

  public enum ValidationError: Error, Equatable, Sendable {
    case invalidFeed, invalidPublicKey
  }

  public init(feedURL: String, publicKey: String) throws {
    guard let url = URL(string: feedURL), url.scheme?.lowercased() == "https",
      url.host?.isEmpty == false, url.user == nil, url.password == nil, url.fragment == nil
    else { throw ValidationError.invalidFeed }
    guard let bytes = Data(base64Encoded: publicKey), bytes.count == 32 else {
      throw ValidationError.invalidPublicKey
    }
    self.feedURL = url
    self.publicKey = publicKey
  }
}

/// The release adapter uses Sparkle's standard UI, signature verification and
/// scheduler. Keeping this boundary small lets preferences/UI tests run offline.
@MainActor
public protocol ApplicationUpdateBackend: AnyObject {
  var canCheckForUpdates: Bool { get }
  var automaticallyChecksForUpdates: Bool { get set }
  var stateChanged: (@MainActor () -> Void)? { get set }
  func start() throws
  func checkForUpdates()
  func resetUpdateCycle()
}

@MainActor
@Observable
public final class ApplicationUpdateService {
  public static let shared = ApplicationUpdateService()
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var backend: (any ApplicationUpdateBackend)?
  public private(set) var canCheckForUpdates = false
  public private(set) var isAvailable = false
  public private(set) var status = String(localized: "Update checks are unavailable in this build.")
  private var automaticChecksValue: Bool

  public var includesPreReleases: Bool {
    didSet {
      guard oldValue != includesPreReleases else { return }
      defaults.set(includesPreReleases, forKey: "updateIncludesPreReleases")
      backend?.resetUpdateCycle()
    }
  }
  public var allowedChannels: Set<String> { includesPreReleases ? ["beta"] : [] }
  public var automaticallyChecksForUpdates: Bool {
    get { automaticChecksValue }
    set {
      guard let backend else { return }
      backend.automaticallyChecksForUpdates = newValue
      refresh()
    }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    includesPreReleases = defaults.bool(forKey: "updateIncludesPreReleases")
    automaticChecksValue = defaults.bool(forKey: "SUEnableAutomaticChecks")
  }

  /// Called after ordinary preference migration. Never invent an automatic-check
  /// choice: Sparkle keeps its original consent prompt and persisted decision.
  public func start(using backend: any ApplicationUpdateBackend) {
    guard self.backend == nil else { return }
    includesPreReleases = defaults.bool(forKey: "updateIncludesPreReleases")
    self.backend = backend
    backend.stateChanged = { [weak self] in self?.refresh() }
    do {
      try backend.start()
      isAvailable = true
      status = ""
      refresh()
    } catch {
      backend.stateChanged = nil
      self.backend = nil
      canCheckForUpdates = false
      isAvailable = false
      status = String(localized: "Update checks could not start: \(error.localizedDescription)")
    }
  }

  public func setUnavailable(_ reason: String) {
    guard backend == nil else { return }
    // Preference migration may have completed since this service was created.
    includesPreReleases = defaults.bool(forKey: "updateIncludesPreReleases")
    automaticChecksValue = defaults.bool(forKey: "SUEnableAutomaticChecks")
    status = reason
  }

  public func checkForUpdates() {
    guard canCheckForUpdates else { return }
    backend?.checkForUpdates()
  }

  private func refresh() {
    guard let backend else { return }
    canCheckForUpdates = backend.canCheckForUpdates
    automaticChecksValue = backend.automaticallyChecksForUpdates
  }
}

public struct ApplicationUpdateCommands: Commands {
  private let updates = ApplicationUpdateService.shared
  public init() {}
  public var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") { updates.checkForUpdates() }
        .disabled(!updates.canCheckForUpdates)
        .accessibilityIdentifier("checkForUpdates")
    }
  }
}

struct ApplicationUpdateSettingsControl: View {
  @Bindable var updates: ApplicationUpdateService
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Automatically check for updates", isOn: $updates.automaticallyChecksForUpdates)
        .toggleStyle(.switch).disabled(!updates.isAvailable)
        .accessibilityIdentifier("automaticUpdateChecks")
      Toggle("Include prerelease versions", isOn: $updates.includesPreReleases)
        .toggleStyle(.switch)
        .accessibilityIdentifier("includePreReleaseUpdates")
        .help("Receive beta releases as well as stable updates.")
      HStack {
        if !updates.status.isEmpty {
          Text(updates.status).foregroundStyle(.secondary)
            .accessibilityIdentifier("updateAvailabilityStatus")
        }
        Spacer()
        Button("Check for Updates…") { updates.checkForUpdates() }
          .disabled(!updates.canCheckForUpdates)
          .accessibilityIdentifier("checkForUpdates")
      }
    }
  }
}
