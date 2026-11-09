import Foundation
import PreferencesCore
import Testing

@testable import SnowfolioUI

@MainActor
private final class UpdateBackendFixture: ApplicationUpdateBackend {
  var canCheckForUpdates = true
  var automaticallyChecksForUpdates = false
  var stateChanged: (@MainActor () -> Void)?
  var startError: (any Error)?
  var starts = 0
  var checks = 0
  var resets = 0
  func start() throws {
    starts += 1
    if let startError { throw startError }
  }
  func checkForUpdates() { checks += 1 }
  func resetUpdateCycle() { resets += 1 }
}

@Suite("Application update configuration and lifecycle")
@MainActor
struct ApplicationUpdateTests {
  @Test("Release metadata requires HTTPS and a full Ed25519 public key")
  func metadata() throws {
    let key = Data(repeating: 7, count: 32).base64EncodedString()
    let config = try ApplicationUpdateConfiguration(
      feedURL: "https://example.com/snowfolio/appcast.xml", publicKey: key)
    #expect(config.publicKey == key)
    for feed in [
      "http://example.com/feed", "/feed", "file:///feed", "https://u:p@example.com/feed",
      "https://example.com/feed#fragment", "https://",
    ] {
      #expect(throws: ApplicationUpdateConfiguration.ValidationError.invalidFeed) {
        try ApplicationUpdateConfiguration(feedURL: feed, publicKey: key)
      }
    }
    for bad in ["", "not a key", Data(repeating: 7, count: 31).base64EncodedString()] {
      #expect(throws: ApplicationUpdateConfiguration.ValidationError.invalidPublicKey) {
        try ApplicationUpdateConfiguration(feedURL: config.feedURL.absoluteString, publicKey: bad)
      }
    }
  }

  @Test("Legacy beta choice migrates without enabling automatic checks or replacing the feed")
  func migration() throws {
    let domain = "UpdateMigration." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let service = ApplicationUpdateService(defaults: defaults)
    LegacyPreferencesMigration.migrate(
      [
        "updateIncludesPreReleases": true, "SUEnableAutomaticChecks": false,
        "SUFeedURL": "https://old-app.example/feed",
      ], into: defaults, targetDomain: domain)
    service.setUnavailable("Development build")
    #expect(service.includesPreReleases && service.allowedChannels == ["beta"])
    #expect(!service.automaticallyChecksForUpdates)
    #expect(!service.isAvailable && !service.canCheckForUpdates)
    service.checkForUpdates()
    service.includesPreReleases = false
    #expect(!defaults.bool(forKey: "updateIncludesPreReleases"))
    let reopened = ApplicationUpdateService(defaults: defaults)
    #expect(reopened.allowedChannels.isEmpty)
    #expect(defaults.string(forKey: "SUFeedURL") == "https://old-app.example/feed")
    let config = try ApplicationUpdateConfiguration(
      feedURL: "https://example.com/snowfolio/appcast.xml",
      publicKey: Data(repeating: 1, count: 32).base64EncodedString())
    #expect(config.feedURL.host == "example.com")
  }

  @Test(
    "Startup preserves consent, state changes disable busy checks, and channels reschedule once")
  func lifecycle() throws {
    let domain = "UpdateLifecycle." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let service = ApplicationUpdateService(defaults: defaults)
    let backend = UpdateBackendFixture()
    service.start(using: backend)
    service.start(using: backend)
    #expect(backend.starts == 1 && service.canCheckForUpdates && service.isAvailable)
    #expect(defaults.object(forKey: "SUEnableAutomaticChecks") == nil)
    service.checkForUpdates()
    #expect(backend.checks == 1)
    backend.canCheckForUpdates = false
    backend.stateChanged?()
    service.checkForUpdates()
    #expect(!service.canCheckForUpdates && backend.checks == 1)
    service.automaticallyChecksForUpdates = true
    #expect(backend.automaticallyChecksForUpdates && service.automaticallyChecksForUpdates)
    service.includesPreReleases = true
    service.includesPreReleases = true
    #expect(backend.resets == 1 && service.allowedChannels == ["beta"])
    let failed = ApplicationUpdateService(defaults: defaults)
    let broken = UpdateBackendFixture()
    broken.startError = CocoaError(.fileReadCorruptFile)
    failed.start(using: broken)
    #expect(!failed.isAvailable && !failed.canCheckForUpdates && !failed.status.isEmpty)
    #expect(broken.stateChanged == nil)
    let repaired = UpdateBackendFixture()
    failed.start(using: repaired)
    #expect(failed.isAvailable && failed.canCheckForUpdates)
  }
}
