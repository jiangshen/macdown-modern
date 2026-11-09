import AppKit
import Observation
import SwiftUI

/// Weak links into the existing workspace, not another owner of document state.
@MainActor
@Observable
final class NativeWorkspaceCommandContext {
  weak var editor: EditorCommandController?
  weak var output: DocumentExportController?
  weak var zoom: DocumentZoomController?
}

@MainActor
@Observable
private final class NativeMenuFocus {
  weak var commands: NativeWorkspaceCommandContext?

  func refresh() {
    commands = (NSApp.mainWindow?.windowController as? NativeDocumentWindowController)?.commands
  }
}

/// Native document commands use the responder chain. Workspace commands reuse the
/// same SwiftUI menu content and controllers as the existing application host.
@MainActor
public final class NativeApplicationMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
  let mainMenu = NSMenu()
  private let preferences: AppPreferences
  private let focus = NativeMenuFocus()
  private let services = NSMenu(title: String(localized: "Services"))
  private let windows = NSMenu(title: String(localized: "Window"))
  private let help = NSMenu(title: String(localized: "Help"))
  private var settings: SettingsWindowController?
  private let plugins = NativePluginMenuController()

  public override convenience init() { self.init(preferences: NativeDocumentPreferences.shared) }

  init(preferences: AppPreferences) {
    self.preferences = preferences
    super.init()
    buildMenus()
    for name in [
      NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
      NSWindow.willCloseNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowChanged), name: name, object: nil)
    }
  }

  public func install() {
    focus.refresh()
    NSApp.mainMenu = mainMenu
    NSApp.servicesMenu = services
    NSApp.windowsMenu = windows
    NSApp.helpMenu = help
    plugins.refresh()
  }

  private func attach(_ menu: NSMenu, title: String) {
    menu.title = title
    menu.delegate = self
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.submenu = menu
    mainMenu.addItem(item)
  }

  @discardableResult
  private func item(
    _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
    target: AnyObject? = nil
  ) -> NSMenuItem {
    let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
    item.target = target
    return item
  }

  private func buildMenus() {
    let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Snowfolio"
    let application = NSMenu(title: name)
    attach(application, title: name)
    item(
      application, String(localized: "About \(name)"),
      #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    let updateItem = item(
      application, String(localized: "Check for Updates…"), #selector(checkForUpdates), target: self
    )
    updateItem.setAccessibilityIdentifier("checkForUpdates")
    application.addItem(.separator())
    item(application, String(localized: "Settings…"), #selector(showSettings), ",", target: self)
    application.addItem(.separator())
    let servicesItem = NSMenuItem(
      title: String(localized: "Services"), action: nil, keyEquivalent: "")
    servicesItem.submenu = services
    application.addItem(servicesItem)
    application.addItem(.separator())
    item(application, String(localized: "Hide \(name)"), #selector(NSApplication.hide(_:)), "h")
    item(
      application, String(localized: "Hide Others"),
      #selector(NSApplication.hideOtherApplications(_:)), "h"
    )
    .keyEquivalentModifierMask = [.command, .option]
    item(
      application, String(localized: "Show All"), #selector(NSApplication.unhideAllApplications(_:))
    )
    application.addItem(.separator())
    item(
      application, String(localized: "Quit \(name)"), #selector(NSApplication.terminate(_:)), "q")

    let file = NSMenu(title: String(localized: "File"))
    attach(file, title: String(localized: "File"))
    item(file, String(localized: "New"), #selector(NSDocumentController.newDocument(_:)), "n")
    item(file, String(localized: "New Tab"), #selector(newTab), "t", target: self)
    item(file, String(localized: "Open…"), #selector(NSDocumentController.openDocument(_:)), "o")
    // NSDocumentController supplies the standard Open Recent menu, respecting
    // maximumRecentDocumentCount. A second manual menu duplicates Cocoa's item.
    file.addItem(.separator())
    item(file, String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w")
    item(file, String(localized: "Save"), #selector(NSDocument.save(_:)), "s")
    item(file, String(localized: "Duplicate"), #selector(NSDocument.duplicate(_:)), "s")
      .keyEquivalentModifierMask = [.command, .shift]
    item(file, String(localized: "Save As…"), #selector(NSDocument.saveAs(_:)), "S")
      .keyEquivalentModifierMask = [.command, .shift, .option]
    item(
      file, String(localized: "Revert to Saved…"), #selector(NSDocument.revertToSaved(_:)))
    item(
      file, String(localized: "Browse All Versions…"),
      #selector(NSDocument.browseVersions(_:)))
    file.addItem(.separator())
    let export = NSMenuItem(title: String(localized: "Export"), action: nil, keyEquivalent: "")
    export.submenu = NSHostingMenu(rootView: NativeExportMenu(focus: focus))
    file.addItem(export)
    item(file, String(localized: "Print…"), #selector(printDocument), "p", target: self)

    let edit = NSMenu(title: String(localized: "Edit"))
    attach(edit, title: String(localized: "Edit"))
    item(edit, String(localized: "Undo"), Selector(("undo:")), "z")
    item(edit, String(localized: "Redo"), Selector(("redo:")), "Z")
    edit.addItem(.separator())
    item(edit, String(localized: "Cut"), #selector(NSText.cut(_:)), "x")
    item(edit, String(localized: "Copy"), #selector(NSText.copy(_:)), "c")
    item(edit, String(localized: "Paste"), #selector(NSText.paste(_:)), "v")
    item(edit, String(localized: "Delete"), #selector(NSText.delete(_:)))
    item(edit, String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a")
    edit.addItem(.separator())
    let find = NSMenuItem(title: String(localized: "Find"), action: nil, keyEquivalent: "")
    let findMenu = NSMenu(title: String(localized: "Find"))
    for (title, key, tag) in [
      (String(localized: "Find…"), "f", NSTextFinder.Action.showFindInterface),
      (String(localized: "Find Next"), "g", .nextMatch),
      (String(localized: "Find Previous"), "G", .previousMatch),
      (String(localized: "Use Selection for Find"), "e", .setSearchString),
    ] {
      item(findMenu, title, #selector(NSTextView.performFindPanelAction(_:)), key).tag = Int(
        tag.rawValue)
    }
    find.submenu = findMenu
    edit.addItem(find)
    let spelling = NSMenuItem(
      title: String(localized: "Spelling and Grammar"), action: nil, keyEquivalent: "")
    let spellingMenu = NSMenu(title: String(localized: "Spelling and Grammar"))
    item(
      spellingMenu, String(localized: "Show Spelling and Grammar"),
      #selector(NSText.showGuessPanel(_:)))
    item(spellingMenu, String(localized: "Check Document Now"), #selector(NSText.checkSpelling(_:)))
    spellingMenu.addItem(.separator())
    item(
      spellingMenu, String(localized: "Check Spelling While Typing"),
      #selector(NSTextView.toggleContinuousSpellChecking(_:)))
    item(
      spellingMenu, String(localized: "Check Grammar With Spelling"),
      #selector(NSTextView.toggleGrammarChecking(_:)))
    item(
      spellingMenu, String(localized: "Correct Spelling Automatically"),
      #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)))
    item(
      spellingMenu, String(localized: "Complete Automatically"),
      #selector(NSTextView.toggleAutomaticTextCompletion(_:)))
    spelling.submenu = spellingMenu
    edit.addItem(spelling)
    edit.addItem(.separator())
    item(
      edit, String(localized: "Emoji & Symbols"),
      #selector(NSApplication.orderFrontCharacterPalette(_:)))

    attach(
      NSHostingMenu(rootView: NativeFormatMenu(focus: focus)), title: String(localized: "Format"))
    attach(
      NSHostingMenu(rootView: NativeViewMenu(focus: focus, preferences: preferences)),
      title: String(localized: "View"))
    let pluginItem = NSMenuItem(
      title: String(localized: "Plug-ins"), action: nil, keyEquivalent: "")
    pluginItem.setAccessibilityIdentifier("pluginMenu")
    pluginItem.submenu = plugins.menu
    mainMenu.addItem(pluginItem)
    attach(windows, title: String(localized: "Window"))
    item(windows, String(localized: "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
    item(windows, String(localized: "Zoom"), #selector(NSWindow.performZoom(_:)))
    windows.addItem(.separator())
    item(windows, String(localized: "Show Tab Bar"), #selector(NSWindow.toggleTabBar(_:)))
    item(
      windows, String(localized: "Move Tab to New Window"),
      #selector(NSWindow.moveTabToNewWindow(_:)))
    item(windows, String(localized: "Merge All Windows"), #selector(NSWindow.mergeAllWindows(_:)))
    windows.addItem(.separator())
    item(
      windows, String(localized: "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
    attach(help, title: String(localized: "Help"))
    item(help, String(localized: "Snowfolio Help"), #selector(showHelp), target: self)
  }

  @objc private func windowChanged(_ notification: Notification) { focus.refresh() }

  public func menuNeedsUpdate(_ menu: NSMenu) { focus.refresh() }

  public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(checkForUpdates) {
      menuItem.toolTip = ApplicationUpdateService.shared.status
      return ApplicationUpdateService.shared.canCheckForUpdates
    }
    if menuItem.action == #selector(printDocument) {
      return focus.commands?.output?.isAvailable == true
    }
    return true
  }

  @objc private func checkForUpdates(_ sender: Any?) {
    ApplicationUpdateService.shared.checkForUpdates()
  }

  @objc private func showSettings(_ sender: Any?) {
    if settings == nil { settings = SettingsWindowController(preferences: preferences) }
    settings?.showWindow(sender)
  }

  @objc private func newTab(_ sender: Any?) {
    DocumentTabPlacement.shared.request(from: NSApp.keyWindow, existingWindows: NSApp.windows)
    NSDocumentController.shared.newDocument(sender)
  }

  @objc private func printDocument(_ sender: Any?) { focus.commands?.output?.printDocument() }

  @objc private func showHelp(_ sender: Any?) {
    if let url = URL(string: "https://github.com/jiangshen/snowfolio#readme") {
      NSWorkspace.shared.open(url)
    }
  }

  deinit { NotificationCenter.default.removeObserver(self) }
}

private struct NativeFormatMenu: View {
  let focus: NativeMenuFocus
  var body: some View { MarkdownFormatMenuContent(editor: focus.commands?.editor) }
}

private struct NativeExportMenu: View {
  let focus: NativeMenuFocus
  var body: some View { DocumentExportMenuContent(output: focus.commands?.output) }
}

private struct NativeViewMenu: View {
  let focus: NativeMenuFocus
  let preferences: AppPreferences
  var body: some View {
    DocumentZoomMenuContent(zoom: focus.commands?.zoom)
    Divider()
    DocumentScrollMenuContent(preferences: preferences)
  }
}
