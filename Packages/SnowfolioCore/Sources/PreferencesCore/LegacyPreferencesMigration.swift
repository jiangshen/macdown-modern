import Foundation

public enum LegacyPreferencesMigration {
  public static let markerKey = "modernPreferencesMigrationVersion"

  /// Copy persisted preferences, preserving explicit false values and new-app choices.
  /// The old domain is read-only. Queued CLI requests are not durable preferences.
  @MainActor
  @discardableResult
  public static func migrate(
    _ legacy: [String: Any], into defaults: UserDefaults,
    targetDomain: String
  ) -> Int {
    let existing = defaults.persistentDomain(forName: targetDomain) ?? [:]
    guard (existing[markerKey] as? Int ?? 0) < 1 else { return 0 }
    let transientKeys = Set([
      "filesToOpenOnNextLaunch", "pipedContentFileToOpenOnNextLaunch", markerKey,
    ])
    var copied = 0
    for (key, value) in legacy where existing[key] == nil && !transientKeys.contains(key) {
      defaults.set(value, forKey: key)
      copied += 1
    }
    defaults.set(1, forKey: markerKey)
    return copied
  }
}
