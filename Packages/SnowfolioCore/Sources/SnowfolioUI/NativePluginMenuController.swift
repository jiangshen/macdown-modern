import AppKit
import PluginCore

/// Menu discovery reads metadata only. Plug-in code is loaded on the app actor
/// after the user explicitly accepts its first Run in this application session.
@MainActor
final class NativePluginMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
  let menu = NSMenu(title: String(localized: "Plug-ins"))
  private let session = PluginSession()
  private let folders: [URL]
  private let installationFolder: URL
  private var inventory: PluginInventory?
  private var discoveryError: String?
  private var refreshTask: Task<Void, Never>?
  private var isRunning = false

  override convenience init() {
    let support = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support", isDirectory: true)
    let modern = support.appendingPathComponent("Snowfolio/PlugIns", isDirectory: true)
    #if DEBUG
      if let path = ProcessInfo.processInfo.environment["SNOWFOLIO_TEST_PLUGIN_FOLDER"],
        path.hasPrefix("/")
      {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        self.init(folders: [folder], installationFolder: folder)
        return
      }
    #endif
    self.init(
      folders: [modern, support.appendingPathComponent("MacDown/PlugIns", isDirectory: true)],
      installationFolder: modern)
  }

  init(folders: [URL], installationFolder: URL) {
    self.folders = folders
    self.installationFolder = installationFolder
    super.init()
    menu.delegate = self
    rebuildMenu()
  }

  func refresh() {
    guard refreshTask == nil else { return }
    let folders = folders
    refreshTask = Task { [weak self] in
      defer { self?.refreshTask = nil }
      do {
        let discovered = try await PluginCatalog.discover(in: folders)
        guard let self, !Task.isCancelled else { return }
        inventory = discovered
        discoveryError = nil
      } catch is CancellationError {
        return
      } catch {
        self?.discoveryError = error.localizedDescription
      }
      // Store the result only. Do not mutate an NSMenu while it is tracking.
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) { rebuildMenu() }

  private func rebuildMenu() {
    menu.removeAllItems()
    if let inventory, !inventory.plugins.isEmpty {
      for descriptor in inventory.plugins {
        let title = session.loadedPlugin(at: descriptor.url)?.name ?? descriptor.fallbackName
        let suffix: String
        switch descriptor.availability {
        case .compatible: suffix = ""
        case .intelOnly: suffix = String(localized: " — Intel only")
        case .unsupportedArchitecture: suffix = String(localized: " — Unsupported architecture")
        case .invalidBundle: suffix = String(localized: " — Invalid plug-in")
        }
        let item = command(
          title + suffix, action: #selector(runPlugin),
          identifier: "runPlugin." + descriptor.url.path)
        item.representedObject = descriptor
        item.toolTip =
          session.loadedPlugin(at: descriptor.url) == nil
          ? descriptor.url.path
          : String(
            localized:
              "\(descriptor.url.path)\nLoaded for this session. Restart Snowfolio after replacing this plug-in."
          )
      }
    } else {
      let title =
        refreshTask == nil
        ? String(localized: "No Plug-ins Found") : String(localized: "Checking Plug-ins…")
      _ = command(title, action: nil, identifier: "pluginInventoryStatus")
    }
    if let discoveryError { addIssue(discoveryError) }
    for issue in inventory?.issues ?? [] {
      addIssue(
        String(localized: "Could not read \(issue.folder.lastPathComponent)"), detail: issue.message
      )
    }
    menu.addItem(.separator())
    _ = command(
      String(localized: "Refresh Plug-ins"), action: #selector(refreshPlugins),
      identifier: "refreshPlugins")
    _ = command(
      String(localized: "Open Plug-ins Folder"), action: #selector(openFolder),
      identifier: "openPluginFolder")
  }

  @discardableResult
  private func command(_ title: String, action: Selector?, identifier: String) -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
    item.target = self
    item.setAccessibilityIdentifier(identifier)
    if action == nil { item.isEnabled = false }
    return item
  }

  private func addIssue(_ title: String, detail: String? = nil) {
    let item = command(title, action: nil, identifier: "pluginFolderIssue")
    item.toolTip = detail ?? title
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(runPlugin) {
      guard let descriptor = menuItem.representedObject as? PluginDescriptor else { return false }
      return descriptor.availability == .compatible && !isRunning
        && NSApp.mainWindow?.attachedSheet == nil
    }
    if menuItem.action == #selector(refreshPlugins) { return refreshTask == nil && !isRunning }
    return menuItem.action == #selector(openFolder)
  }

  @objc private func refreshPlugins(_ sender: NSMenuItem) { refresh() }

  @objc private func openFolder(_ sender: NSMenuItem) {
    do {
      try FileManager.default.createDirectory(
        at: installationFolder, withIntermediateDirectories: true)
      guard NSWorkspace.shared.open(installationFolder) else {
        throw CocoaError(.fileReadUnknown)
      }
    } catch {
      Task {
        await showError(
          error.localizedDescription, window: NSApp.mainWindow,
          title: String(localized: "Could Not Open Plug-ins Folder"))
      }
    }
  }

  @objc private func runPlugin(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let descriptor = sender.representedObject as? PluginDescriptor
    else {
      return
    }
    isRunning = true
    let window = NSApp.mainWindow
    let document = window?.windowController?.document as? NSDocument
    Task {
      defer { isRunning = false }
      if session.loadedPlugin(at: descriptor.url) == nil {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Run “\(descriptor.fallbackName)”?")
        alert.informativeText = String(
          localized:
            "Native plug-ins run code inside Snowfolio and can access your documents and files. Only run plug-ins from a source you trust.\n\n\(descriptor.url.path)"
        )
        alert.addButton(withTitle: String(localized: "Run Plug-in"))
          .setAccessibilityIdentifier("confirmPluginRun")
        alert.addButton(withTitle: String(localized: "Cancel"))
          .setAccessibilityIdentifier("cancelPluginRun")
        guard await present(alert, window: window) == .alertFirstButtonReturn else { return }
      }
      // Same-process plug-ins use shared.currentDocument. Restore their original
      // target after an async sheet rather than silently editing another window.
      if let window, let document {
        guard NSDocumentController.shared.documents.contains(where: { $0 === document }) else {
          return
        }
        window.makeKeyAndOrderFront(nil)
        guard NSDocumentController.shared.currentDocument === document else {
          await showError(
            String(localized: "Select the document you want to use, then run the plug-in again."),
            window: window)
          return
        }
      }
      do {
        let plugin = try session.load(descriptor)
        guard plugin.run(sender: sender) else {
          await showError(
            String(localized: "The plug-in reported that it could not complete its action."),
            window: window)
          return
        }
      } catch {
        await showError(error.localizedDescription, window: window)
      }
    }
  }

  private func showError(
    _ message: String, window: NSWindow?,
    title: String = String(localized: "Could Not Run Plug-in")
  ) async {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: String(localized: "OK"))
      .setAccessibilityIdentifier("dismissPluginError")
    _ = await present(alert, window: window)
  }

  private func present(_ alert: NSAlert, window: NSWindow?) async -> NSApplication.ModalResponse {
    if let window { return await alert.beginSheetModal(for: window) }
    // A plug-in may be useful without a document; a standard app-modal alert
    // handles that case without inventing an empty document to host a sheet.
    return alert.runModal()
  }

  deinit { refreshTask?.cancel() }
}
