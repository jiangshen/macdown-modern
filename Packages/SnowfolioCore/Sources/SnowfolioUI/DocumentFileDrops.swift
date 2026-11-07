import AppKit
import Observation
import SwiftUI
import WebKit

/// Read file references only. Do not load file contents or resolve links on the UI thread.
enum MarkdownFileDrop {
  static func accepts(_ urls: [URL]) -> Bool {
    !urls.isEmpty
      && urls.allSatisfy {
        $0.isFileURL && ["md", "markdown"].contains($0.pathExtension.lowercased())
      }
  }

  @MainActor static func urls(from pasteboard: NSPasteboard) -> [URL]? {
    guard let items = pasteboard.pasteboardItems, !items.isEmpty,
      items.allSatisfy({ $0.types.contains(.fileURL) }),
      let urls = pasteboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
      urls.count == items.count, accepts(urls)
    else { return nil }
    return urls
  }

  static func unique(_ urls: [URL]) -> [URL] {
    var seen = Set<URL>()
    // Keep the original URL (including any security scope), using a normalized key only.
    return urls.filter { seen.insert($0.standardizedFileURL).inserted }
  }
}

@MainActor
final class MarkdownFileDropHandler {
  var openFiles: (@MainActor ([URL]) -> Bool)?

  /// nil lets a native editor or WebKit continue handling its ordinary drag types.
  func operation(for sender: any NSDraggingInfo) -> NSDragOperation? {
    guard openFiles != nil, MarkdownFileDrop.urls(from: sender.draggingPasteboard) != nil else {
      return nil
    }
    return sender.draggingSourceOperationMask.contains(.copy) ? .copy : []
  }

  func perform(_ sender: any NSDraggingInfo) -> Bool? {
    guard let openFiles, let urls = MarkdownFileDrop.urls(from: sender.draggingPasteboard) else {
      return nil
    }
    guard sender.draggingSourceOperationMask.contains(.copy) else { return false }
    return openFiles(urls)
  }
}

/// Tracks only whether a window can still anchor a UI operation; it never owns the window.
@MainActor
final class DocumentWindowAnchor: NSObject {
  private weak var target: NSWindow?
  private var closed = false
  var window: NSWindow? { closed ? nil : target }

  init(_ window: NSWindow?) {
    target = window
    super.init()
    if let window {
      NotificationCenter.default.addObserver(
        self, selector: #selector(willClose), name: NSWindow.willCloseNotification, object: window)
    }
  }

  @objc private func willClose(_ notification: Notification) { closed = true }
}

@MainActor
@Observable
final class DroppedDocumentOpener {
  private var activeBatches = 0
  var isOpening: Bool { activeBatches > 0 }
  var failures: [String] = []

  func open(
    _ urls: [URL], from anchor: DocumentWindowAnchor,
    using action: @MainActor (URL) async throws -> Void
  ) async {
    guard MarkdownFileDrop.accepts(urls) else { return }
    activeBatches += 1
    defer { activeBatches -= 1 }
    for url in MarkdownFileDrop.unique(urls) {
      if Task.isCancelled { break }
      let existing = NSApp.windows
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      do {
        try await action(url)
        Self.placeNewWindow(at: url, anchor: anchor, existing: existing, windows: NSApp.windows)
      } catch {
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { break }
        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
      }
    }
  }

  /// An already-open document keeps its existing window/group. Only a newly created
  /// host window for this exact URL is placed into the drop's originating group.
  static func placeNewWindow(
    at url: URL, anchor: DocumentWindowAnchor, existing: [NSWindow], windows: [NSWindow]
  ) {
    guard let source = anchor.window,
      source.tabbingIdentifier == DocumentWindowPolicy.tabbingIdentifier,
      let created = windows.first(where: { candidate in
        candidate.tabbingIdentifier == DocumentWindowPolicy.tabbingIdentifier
          && candidate.representedURL?.standardizedFileURL == url.standardizedFileURL
          && !existing.contains(where: { $0 === candidate })
      })
    else { return }
    if source.tabGroup !== created.tabGroup { source.addTabbedWindow(created, ordered: .above) }
    source.tabGroup?.selectedWindow = created
  }
}

struct DocumentDropButton: NSViewRepresentable {
  let openFiles: @MainActor ([URL]) -> Bool

  func makeNSView(context: Context) -> MarkdownFileDropButton {
    let button = MarkdownFileDropButton()
    button.title = String(localized: "Open Files…")
    button.bezelStyle = .rounded
    button.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil)
    button.imagePosition = .imageLeading
    button.controlSize = .small
    button.target = button
    button.action = #selector(MarkdownFileDropButton.chooseFiles(_:))
    button.toolTip = String(localized: "Drop Markdown files here, or choose files to open.")
    button.setAccessibilityIdentifier("openMarkdownFiles")
    button.setAccessibilityLabel(String(localized: "Open Files…"))
    button.registerForDraggedTypes([.fileURL])
    button.fileDrop.openFiles = openFiles
    return button
  }

  func updateNSView(_ button: MarkdownFileDropButton, context: Context) {
    button.fileDrop.openFiles = openFiles
  }

  static func dismantleNSView(_ button: MarkdownFileDropButton, coordinator: ()) {
    button.fileDrop.openFiles = nil
  }
}

final class MarkdownFileDropButton: NSButton {
  let fileDrop = MarkdownFileDropHandler()

  @objc func chooseFiles(_ sender: Any?) {
    NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: sender)
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    let operation = fileDrop.operation(for: sender) ?? []
    highlight(operation == .copy)
    return operation
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingEntered(sender)
  }
  override func draggingExited(_ sender: (any NSDraggingInfo)?) { highlight(false) }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    fileDrop.operation(for: sender) == .copy
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    defer { highlight(false) }
    return fileDrop.perform(sender) ?? false
  }
}

final class MarkdownPreviewWebView: WKWebView {
  let fileDrop = MarkdownFileDropHandler()

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    fileDrop.operation(for: sender) ?? super.draggingEntered(sender)
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    fileDrop.operation(for: sender) ?? super.draggingUpdated(sender)
  }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    if let operation = fileDrop.operation(for: sender) { return operation == .copy }
    return super.prepareForDragOperation(sender)
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    fileDrop.perform(sender) ?? super.performDragOperation(sender)
  }
}
