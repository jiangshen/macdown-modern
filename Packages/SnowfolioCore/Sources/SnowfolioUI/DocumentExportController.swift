import AppKit
import ExportCore
import MarkdownCore
import Observation
import RenderingCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
public final class DocumentExportController {
  public private(set) var isBusy = false
  public var errorMessage: String?
  weak var document: MarkdownDocument?
  weak var preferences: AppPreferences?
  weak var window: NSWindow?
  @ObservationIgnored private var task: Task<Void, Never>?

  public init() {}

  public var isAvailable: Bool {
    document != nil && preferences != nil && window != nil && !isBusy
      && preferences?.readingStyles.isReady == true && preferences?.readingStyles.isLoading == false
      && (document?.fileURL != nil
        || (preferences?.assetFolder.isReady == true && preferences?.assetFolder.isLoading == false))
  }

  public func exportHTML() { start(.html) }
  public func exportPDF() { start(.pdf) }
  public func printDocument() { start(.print) }
  public func copyHTML() { start(.clipboard) }

  func snapshot() -> DocumentExportSnapshot? {
    guard let document, let preferences, preferences.readingStyles.isReady,
      !preferences.readingStyles.isLoading
    else { return nil }
    guard
      document.fileURL != nil
        || (preferences.assetFolder.isReady && !preferences.assetFolder.isLoading)
    else { return nil }
    let location = preferences.assetFolder.location(for: document.fileURL)
    return DocumentExportSnapshot(
      source: document.text, options: preferences.renderingOptions,
      title: document.fileURL?.deletingPathExtension().lastPathComponent
        ?? String(localized: "Untitled"),
      directory: location.directory, assetAccess: location.access,
      localImagesUnavailable: document.fileURL == nil && preferences.assetFolder.isUnavailable,
      remoteImages: preferences.remoteImages, style: preferences.documentStyle,
      templateName: preferences.htmlTemplateName)
  }

  private func start(_ action: Action) {
    guard isAvailable, let snapshot = snapshot(), let window else { return }
    isBusy = true
    errorMessage = nil
    task = Task {
      defer {
        isBusy = false
        task = nil
      }
      do {
        try await perform(action, snapshot: snapshot, window: window)
      } catch is CancellationError {} catch MarkdownExport.Failure.assetFolderUnavailable {
        errorMessage = String(
          localized:
            "The asset folder for this unsaved document is unavailable. Reconnect it or choose another folder in Settings → Privacy & Security."
        )
      } catch HTMLExportTemplate.Failure.unavailable {
        errorMessage = String(
          localized:
            "The saved HTML template is unavailable. Choose Use Default in Settings → Appearance → HTML template, then try again."
        )
      } catch {
        errorMessage = String(
          localized:
            "The document could not be exported. Check any local images and the destination folder, then try again."
        )
      }
    }
  }

  private func perform(_ action: Action, snapshot: DocumentExportSnapshot, window: NSWindow)
    async throws
  {
    defer { withExtendedLifetime(snapshot.assetAccess) {} }
    if action != .clipboard, snapshot.templateName != HTMLExportTemplate.defaultName {
      throw HTMLExportTemplate.Failure.unavailable
    }
    var destination: URL?
    var styled = snapshot.style.presentation != .unstyled
    var options = snapshot.options
    if action == .html || action == .pdf {
      let panel = NSSavePanel()
      panel.allowedContentTypes = action == .html ? [.html] : [.pdf]
      panel.nameFieldStringValue = snapshot.title + (action == .html ? ".html" : ".pdf")
      panel.canCreateDirectories = true
      let styleOption = NSButton(
        checkboxWithTitle: String(localized: "Include document styles"), target: nil, action: nil)
      styleOption.state = styled ? .on : .off
      let codeOption = NSButton(
        checkboxWithTitle: String(localized: "Include code highlighting"), target: nil, action: nil)
      codeOption.state = options.codeHighlighting ? .on : .off
      codeOption.setAccessibilityIdentifier("exportCodeHighlighting")
      styleOption.setAccessibilityIdentifier("exportDocumentStyles")
      if action == .html {
        let accessory = NSStackView(views: [styleOption, codeOption])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        panel.accessoryView = accessory
      }
      let response = await panel.beginSheetModal(for: window)
      guard response == .OK, let url = panel.url else { return }
      destination = url
      styled = styleOption.state == .on
      if action == .html { options.codeHighlighting = codeOption.state == .on }
    }
    try Task.checkCancellation()
    let output = try await MarkdownExport.build(
      source: snapshot.source, options: options,
      title: snapshot.title, directory: snapshot.directory, includeStyles: styled,
      remoteImages: snapshot.remoteImages, embedLocalImages: action != .clipboard,
      localImagesUnavailable: snapshot.localImagesUnavailable,
      style: snapshot.style,
      templateName: action == .clipboard ? HTMLExportTemplate.defaultName : snapshot.templateName)
    switch action {
    case .clipboard:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(output.fragment, forType: .string)
      NSPasteboard.general.setString(output.fragment, forType: .html)
    case .html:
      if let destination { try await output.writeHTML(to: destination) }
    case .pdf, .print:
      let surface = NativeWebOutput()
      defer { surface.close() }
      try await surface.prepare(html: output.document, remoteImages: snapshot.remoteImages)
      let info = NativeWebOutput.printInfo(allPages: action == .pdf)
      if action == .pdf, let destination {
        // Print into a disposable staging file, then atomically replace the selected
        // destination only after WebKit successfully finishes every page.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(
          UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: staging) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = staging
        let completed = await surface.printDocument(info: info, for: window, showPanel: false)
        guard completed else { throw DocumentOutputError.printFailed }
        try Task.checkCancellation()
        try await Self.writePDF(from: staging, to: destination)
      } else {
        _ = await surface.printDocument(info: info, for: window, showPanel: true)
      }
    }
  }

  @concurrent
  private static func writePDF(from staging: URL, to destination: URL) async throws {
    try Task.checkCancellation()
    let access = destination.startAccessingSecurityScopedResource()
    defer { if access { destination.stopAccessingSecurityScopedResource() } }
    let bytes = try Data(contentsOf: staging)
    try bytes.write(to: destination, options: .atomic)
  }

  private enum Action { case html, pdf, print, clipboard }
}

struct DocumentExportSnapshot: Sendable {
  let source: String
  let options: MarkdownRenderingOptions
  let title: String
  let directory: URL?
  let assetAccess: DocumentAssetAccess?
  let localImagesUnavailable: Bool
  let remoteImages: Bool
  let style: DocumentStyle
  let templateName: String
}

extension FocusedValues {
  @Entry public var documentExport: DocumentExportController?
}

public struct DocumentExportCommands: Commands {
  @FocusedValue(\.documentExport) private var output
  public init() {}

  public var body: some Commands {
    CommandGroup(after: .importExport) {
      DocumentExportMenuContent(output: output)
    }
    CommandGroup(replacing: .printItem) {
      Button("Print…") { output?.printDocument() }.keyboardShortcut("p").disabled(
        output?.isAvailable != true)
    }
  }
}

/// The same actions and availability rules serve both application lifecycles.
struct DocumentExportMenuContent: View {
  let output: DocumentExportController?

  var body: some View {
    Group {
      Button("Export HTML…") { output?.exportHTML() }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(output?.isAvailable != true)
      Button("Export PDF…") { output?.exportPDF() }.disabled(output?.isAvailable != true)
      Button("Copy HTML") { output?.copyHTML() }.disabled(output?.isAvailable != true)
    }
  }
}

struct DocumentWindowBridge: NSViewRepresentable {
  let preferTabs: Bool
  let output: DocumentExportController
  init(output: DocumentExportController, preferTabs: Bool = true) {
    self.output = output
    self.preferTabs = preferTabs
  }
  func makeNSView(context: Context) -> WindowView {
    WindowView(output: output, preferTabs: preferTabs)
  }
  func updateNSView(_ view: WindowView, context: Context) {
    view.output = output
    view.preferTabs = preferTabs
    view.synchronizeWindow()
  }
  static func dismantleNSView(_ view: WindowView, coordinator: ()) { view.output?.window = nil }

  final class WindowView: NSView {
    weak var output: DocumentExportController?
    var preferTabs: Bool
    init(output: DocumentExportController, preferTabs: Bool) {
      self.output = output
      self.preferTabs = preferTabs
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }
    func synchronizeWindow() {
      if let window { DocumentWindowPolicy.configure(window, preferTabs: preferTabs) }
      guard output?.window !== window else { return }
      Task { @MainActor [weak self] in
        guard let self, self.output?.window !== self.window else { return }
        self.output?.window = self.window
        if let window = self.window { DocumentTabPlacement.shared.place(window) }
      }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
      if let newWindow { DocumentWindowPolicy.configure(newWindow, preferTabs: preferTabs) }
      super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      synchronizeWindow()
    }
  }
}
