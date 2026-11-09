import AppKit
import SnowfolioUI
import Sparkle

@MainActor
final class SparkleUpdateBackend: NSObject, ApplicationUpdateBackend, SPUUpdaterDelegate {
  private let configuration: ApplicationUpdateConfiguration
  private let channels: @MainActor () -> Set<String>
  private var controller: SPUStandardUpdaterController?
  private var observations: [NSKeyValueObservation] = []
  var stateChanged: (@MainActor () -> Void)?

  init(
    configuration: ApplicationUpdateConfiguration, channels: @escaping @MainActor () -> Set<String>
  ) {
    self.configuration = configuration
    self.channels = channels
    super.init()
    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    for key in [\SPUUpdater.canCheckForUpdates, \SPUUpdater.automaticallyChecksForUpdates] {
      observations.append(
        controller.updater.observe(key, options: [.new]) { [weak self] _, _ in
          Task { @MainActor [weak self] in self?.stateChanged?() }
        })
    }
  }

  var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }
  var automaticallyChecksForUpdates: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? false }
    set { controller?.updater.automaticallyChecksForUpdates = newValue }
  }
  func start() throws {
    guard let controller else { throw CocoaError(.coderInvalidValue) }
    try controller.updater.start()
  }
  func checkForUpdates() { controller?.checkForUpdates(nil) }
  func resetUpdateCycle() { controller?.updater.resetUpdateCycleAfterShortDelay() }
  func allowedChannels(for updater: SPUUpdater) -> Set<String> { channels() }

  // A copied Sparkle1 preference may contain MacDown's feed. The published
  // Snowfolio configuration is authoritative, never that inherited override.
  func feedURLString(for updater: SPUUpdater) -> String? { configuration.feedURL.absoluteString }
}

@MainActor
enum SnowfolioUpdateBootstrap {
  static func start() {
    let service = ApplicationUpdateService.shared
    #if DEBUG
      // Do not create/start Sparkle or replace a development app with a release.
      service.setUnavailable(String(localized: "Automatic updates are off in development builds."))
    #else
      do {
        let configuration = try ApplicationUpdateConfiguration(
          feedURL: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "",
          publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
        let backend = SparkleUpdateBackend(configuration: configuration) { [weak service] in
          service?.allowedChannels ?? []
        }
        service.start(using: backend)
      } catch {
        service.setUnavailable(String(localized: "This build does not include automatic updates."))
      }
    #endif
  }
}

#if !NATIVE_DOCUMENT_HOST
  /// App-owned lifecycle keeps URL handling and updater startup in one place.
  @MainActor
  final class SnowfolioApplicationDelegate: NSObject, NSApplicationDelegate {
    private let links = DocumentURLController()
    func applicationWillFinishLaunching(_ notification: Notification) { links.install() }
    func applicationDidFinishLaunching(_ notification: Notification) {
      links.install()
      SnowfolioUpdateBootstrap.start()
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
  }
#endif
