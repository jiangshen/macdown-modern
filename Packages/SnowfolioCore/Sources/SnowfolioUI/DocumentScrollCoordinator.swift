import AppKit
import EditorCore
import SwiftUI

struct SourceReadingPosition: Codable, Equatable {
  let offset: Int
  let fraction: Double
  let atTop: Bool
  let atBottom: Bool
  var isValid: Bool { offset >= 0 && fraction.isFinite && (0...1).contains(fraction) }
}

/// UI-only per-document coordination. It owns no text, file I/O, selection or undo.
@MainActor
public final class DocumentScrollCoordinator: NSObject {
  private weak var document: MarkdownDocument?
  private weak var editor: MarkdownTextView?
  private weak var clip: NSClipView?
  private weak var preview: NativeMarkdownPreview.Coordinator?
  private var sourceStorage: Binding<Data?>?
  private var previewStorage: Binding<Data?>?
  private var readingURL: URL?
  private var fileSource: Data?
  private var filePreview: Data?
  private var linked = false
  private var mode = WorkspaceMode.split
  private var applyingSource = false
  private var liveSourceScroll = false
  private var sourceWasUsed = false
  private var previewWasUsed = false
  private var restoredSource = false
  private var restoredPreview = false
  private var sourceReading: SourceReadingPosition?
  private var presentationAnchor: SourceReadingPosition?
  private var previewReading: MarkdownScrollPosition?
  private var map: SourceLineMap?
  private var mapRevision: UInt64?
  private enum Driver { case source, preview }
  private var driver = Driver.source
  private var needsAlignment = false
  private var pendingPreview: MarkdownScrollPosition?
  private var sendingPreview = false
  private var previewEpoch: UInt64 = 0
  private var layoutTask: Task<Void, Never>?
  private var persistenceTask: Task<Void, Never>?

  public override init() {
    super.init()
    for name in [
      NSWindow.didExposeNotification, NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didBecomeKeyNotification,
    ] {
      NotificationCenter.default.addObserver(
        self, selector: #selector(windowBecameVisible), name: name, object: nil)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(windowResigned), name: NSWindow.didResignKeyNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(applicationResigned),
      name: NSApplication.willResignActiveNotification,
      object: nil)
  }

  func configure(
    document: MarkdownDocument, linked: Bool, mode: WorkspaceMode,
    sourceStorage: Binding<Data?>, previewStorage: Binding<Data?>
  ) {
    self.document = document
    self.sourceStorage = sourceStorage
    self.previewStorage = previewStorage
    if readingURL != document.fileURL {
      readingURL = document.fileURL
      let saved = document.fileURL.flatMap { DocumentReadingStore.shared.entry(for: $0) }
      fileSource = saved?.source
      filePreview = saved?.preview
    }
    if self.mode != mode {
      self.mode = mode
      if mode == .preview { driver = .preview }
      if mode == .editor { driver = .source }
    }
    if self.linked != linked {
      self.linked = linked
      pendingPreview = nil
      needsAlignment = linked
    }
    layoutChanged()
  }

  func attachSource(_ editor: MarkdownTextView) {
    guard self.editor !== editor else {
      layoutChanged()
      return
    }
    detachSource()
    self.editor = editor
    clip = editor.enclosingScrollView?.contentView
    clip?.postsBoundsChangedNotifications = true
    if let clip {
      NotificationCenter.default.addObserver(
        self, selector: #selector(sourceBoundsChanged), name: NSView.boundsDidChangeNotification,
        object: clip)
    }
    if let scroll = editor.enclosingScrollView {
      NotificationCenter.default.addObserver(
        self, selector: #selector(sourceScrollStarted),
        name: NSScrollView.willStartLiveScrollNotification,
        object: scroll)
      NotificationCenter.default.addObserver(
        self, selector: #selector(sourceScrollEnded),
        name: NSScrollView.didEndLiveScrollNotification,
        object: scroll)
    }
    editor.viewportInputBegan = { [weak self] in self?.sourceEditedOrNavigated() }
    editor.viewportLayoutChanged = { [weak self] in self?.layoutChanged() }
    editor.viewportPresentationWillChange = { [weak self] in self?.sourcePresentationWillChange() }
    layoutChanged()
  }

  func detachSource(_ expected: MarkdownTextView? = nil) {
    if let expected, editor !== expected { return }
    if let clip {
      NotificationCenter.default.removeObserver(
        self, name: NSView.boundsDidChangeNotification, object: clip)
    }
    if let scroll = editor?.enclosingScrollView {
      NotificationCenter.default.removeObserver(
        self, name: NSScrollView.willStartLiveScrollNotification, object: scroll)
      NotificationCenter.default.removeObserver(
        self, name: NSScrollView.didEndLiveScrollNotification, object: scroll)
    }
    editor?.viewportInputBegan = nil
    editor?.viewportLayoutChanged = nil
    editor?.viewportPresentationWillChange = nil
    editor = nil
    clip = nil
  }

  func attachPreview(_ preview: NativeMarkdownPreview.Coordinator) {
    if self.preview !== preview {
      previewEpoch &+= 1
      self.preview = preview
      sendingPreview = false
    }
    layoutChanged()
  }

  func previewWillReload() {
    needsAlignment = linked
    previewEpoch &+= 1
    sendingPreview = false
    if let previewReading { pendingPreview = previewReading }
  }

  func detachPreview(_ preview: NativeMarkdownPreview.Coordinator) {
    guard self.preview === preview else { return }
    previewEpoch &+= 1
    self.preview = nil
    sendingPreview = false
  }

  func sourcePresentationWillChange() {
    presentationAnchor = presentationAnchor ?? captureSource() ?? sourceReading
    needsAlignment = linked
  }

  func previewPresentationChanged(to position: MarkdownScrollPosition?, userInitiated: Bool) {
    if let position, position.isValid { previewReading = position }
    if userInitiated {
      presentationAnchor = nil
      pendingPreview = nil
      previewWasUsed = true
      restoredPreview = true
      driver = .preview
    }
    needsAlignment = linked
    layoutChanged()
  }

  func sourceEditedOrNavigated() {
    if linked { preview?.sourceInputBegan() }
    presentationAnchor = nil
    sourceWasUsed = true
    restoredSource = true
    driver = .source
    needsAlignment = linked
    layoutChanged()
  }

  func layoutChanged() {
    guard layoutTask == nil else { return }
    layoutTask = Task { @MainActor [weak self] in
      guard let self else { return }
      self.layoutTask = nil
      self.restoreSourceIfNeeded()
      self.restorePreviewIfNeeded()
      // Native focus/layout can reveal the restored selection after our first
      // scroll. Retain the reading anchor until the user chooses a new position.
      if let anchor = self.presentationAnchor,
        let actual = self.captureSource(), !self.sameReadingLine(actual, anchor)
      {
        if self.moveSource(to: anchor) {
          // Reflow changes where a visual line starts, but the original source
          // character remains the reading target. Only adopt a clamped edge.
          if let actual = self.sourceReading, actual.atTop || actual.atBottom {
            self.presentationAnchor = actual
          }
        }
      }
      if self.presentationAnchor == nil, !self.sourceWasUsed, self.restoredSource,
        let anchor = self.sourceReading,
        let actual = self.captureSource(), !self.sameReadingLine(actual, anchor)
      {
        self.moveSource(to: anchor)
      }
      if self.sourceWasUsed, let position = self.captureSource() {
        self.sourceReading = position
        self.schedulePersistence()
      }
      self.alignIfNeeded()
      self.sendPendingPreview()
    }
  }

  private func sourceMap() -> SourceLineMap? {
    guard let document else { return nil }
    if mapRevision != document.revision {
      map = SourceLineMap(document.text)
      mapRevision = document.revision
    }
    return map
  }

  private func normalizedOffset(_ value: Int, in editor: NSTextView) -> Int {
    let source = editor.string as NSString
    var value = min(source.length, max(0, value))
    if value < source.length, (0xDC00...0xDFFF).contains(source.character(at: value)) { value -= 1 }
    return value
  }

  private func caretRect(at offset: Int, in editor: NSTextView) -> NSRect? {
    guard let manager = editor.textLayoutManager, let content = manager.textContentManager,
      let location = content.location(content.documentRange.location, offsetBy: offset)
    else { return nil }
    let range = NSTextRange(location: location)
    manager.ensureLayout(for: range)
    var result: NSRect?
    manager.enumerateTextSegments(in: range, type: .standard, options: []) { _, rect, _, _ in
      if rect.height > 0 {
        result = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
      }
      return false
    }
    return result
  }

  private func maximumScroll(in clip: NSClipView) -> CGFloat {
    var proposed = clip.bounds
    proposed.origin.y = clip.documentRect.maxY + clip.contentInsets.bottom + proposed.height
    return max(0, clip.constrainBoundsRect(proposed).minY)
  }

  func captureSource() -> SourceReadingPosition? {
    guard let document, let editor, let clip, editor.sourceDocument === document,
      editor.sourceRevision == document.revision, editor.window?.isVisible == true,
      !editor.isHiddenOrHasHiddenAncestor,
      clip.bounds.height > 0
    else { return nil }
    let visible = editor.visibleRect
    let maximum = maximumScroll(in: clip)
    let offset = normalizedOffset(
      editor.characterIndexForInsertion(
        at: NSPoint(x: editor.textContainerInset.width + 1, y: visible.minY + 1)), in: editor)
    let rect = caretRect(at: offset, in: editor)
    let fraction = rect.map { min(1, max(0, (visible.minY - $0.minY) / $0.height)) } ?? 0
    return SourceReadingPosition(
      offset: offset, fraction: fraction, atTop: clip.bounds.minY <= 0.5,
      atBottom: maximum > 0.5 && clip.bounds.minY >= maximum - 0.5)
  }

  private func sourcePosition() -> MarkdownScrollPosition? {
    guard let reading = captureSource(), let editor, let map = sourceMap() else { return nil }
    var line = map.linePosition(atUTF16Offset: reading.offset)
    if let rect = caretRect(at: reading.offset, in: editor), reading.fraction > 0 {
      let next = normalizedOffset(
        editor.characterIndexForInsertion(
          at: NSPoint(x: editor.textContainerInset.width + 1, y: rect.maxY + 1)), in: editor)
      line += reading.fraction * max(0, map.linePosition(atUTF16Offset: next) - line)
    }
    return MarkdownScrollPosition(line: line, atTop: reading.atTop, atBottom: reading.atBottom)
  }

  @discardableResult
  private func moveSource(to reading: SourceReadingPosition) -> Bool {
    guard reading.isValid, let document, let editor, let clip,
      editor.sourceDocument === document, editor.sourceRevision == document.revision,
      editor.window != nil,
      !editor.isHiddenOrHasHiddenAncestor, !editor.hasMarkedText(), clip.bounds.height > 0
    else { return false }
    applyingSource = true
    defer { applyingSource = false }
    let offset = normalizedOffset(reading.offset, in: editor)
    let rect = caretRect(at: offset, in: editor)
    guard reading.atTop || reading.atBottom || rect != nil else { return false }
    let maximum = maximumScroll(in: clip)
    let lineY = rect.map { $0.minY + reading.fraction * $0.height } ?? 0
    let y = reading.atTop ? 0 : reading.atBottom ? maximum : lineY
    clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(maximum, max(0, y))))
    editor.enclosingScrollView?.reflectScrolledClipView(clip)
    // Revealing coordinates alone does not prepare TextKit 2 rendering surfaces
    // when a restored window has not yet displayed this part of the document.
    editor.textLayoutManager?.textViewportLayoutController.layoutViewport()
    editor.needsLayout = true
    editor.needsDisplay = true
    sourceReading = captureSource() ?? reading
    return true
  }

  private func moveSource(to position: MarkdownScrollPosition) {
    guard position.isValid, let map = sourceMap() else { return }
    let offset = map.utf16Offset(atLinePosition: position.line)
    if moveSource(
      to: SourceReadingPosition(
        offset: offset, fraction: 0,
        atTop: position.atTop, atBottom: position.atBottom))
    {
      restoredSource = true
      schedulePersistence()
    }
  }

  private func sameReadingLine(_ first: SourceReadingPosition, _ second: SourceReadingPosition)
    -> Bool
  {
    if second.atTop { return first.atTop }
    if second.atBottom { return first.atBottom }
    guard abs(first.fraction - second.fraction) < 0.1 else { return false }
    if first.offset == second.offset { return true }
    guard let editor, let actual = caretRect(at: first.offset, in: editor),
      let target = caretRect(at: second.offset, in: editor)
    else { return false }
    // Different UTF-16 offsets can occupy the same wrapped line after reflow.
    return abs(actual.minY - target.minY) < 1
  }

  private var hasLoadedSource: Bool {
    guard let document else { return false }
    return document.loadRevision > 0 || !document.text.isEmpty
  }

  private var savedSource: Data? { fileSource ?? sourceStorage?.wrappedValue }
  private var savedPreview: Data? { filePreview ?? previewStorage?.wrappedValue }

  private func restoreSourceIfNeeded() {
    guard !restoredSource, !sourceWasUsed, hasLoadedSource else { return }
    guard let data = savedSource else { return }
    guard let reading = try? JSONDecoder().decode(SourceReadingPosition.self, from: data),
      reading.isValid
    else {
      // Corrupt scene data must not prevent future scroll linking.
      restoredSource = true
      return
    }
    if moveSource(to: reading) {
      restoredSource = true
      presentationAnchor = nil
    }
  }

  private func restorePreviewIfNeeded() {
    guard !restoredPreview, !previewWasUsed, hasLoadedSource, previewIsReady else { return }
    guard let data = savedPreview else { return }
    guard let position = try? JSONDecoder().decode(MarkdownScrollPosition.self, from: data),
      position.isValid
    else {
      restoredPreview = true
      return
    }
    restoredPreview = true
    previewReading = position
    pendingPreview = position
  }

  private var previewIsReady: Bool {
    guard let revision = document?.revision else { return false }
    return preview?.isReadyForScrolling(revision: revision) == true
  }

  private func alignIfNeeded() {
    guard linked, needsAlignment, previewIsReady, editor?.hasMarkedText() == false else { return }
    if driver == .preview, let position = previewReading {
      let retainingPresentation = presentationAnchor != nil
      presentationAnchor = nil
      moveSource(to: position)
      if retainingPresentation { presentationAnchor = sourceReading }
    } else if savedSource != nil, !restoredSource, !sourceWasUsed {
      return
    } else if let position = sourcePosition() {
      pendingPreview = position
    } else {
      return
    }
    needsAlignment = false
  }

  private func sendPendingPreview() {
    guard !sendingPreview, previewIsReady, let preview, let position = pendingPreview else {
      return
    }
    pendingPreview = nil
    sendingPreview = true
    let epoch = previewEpoch
    preview.moveForScrolling(to: position) { [weak self, weak preview] in
      guard let self, let preview, self.preview === preview, self.previewEpoch == epoch else {
        return
      }
      self.sendingPreview = false
      self.sendPendingPreview()
    }
  }

  func previewInputBegan(revision: UInt64) {
    guard document?.revision == revision else { return }
    presentationAnchor = nil
    pendingPreview = nil
    needsAlignment = false
    liveSourceScroll = false
    previewWasUsed = true
    restoredPreview = true
    driver = .preview
  }

  func previewScrolled(
    _ position: MarkdownScrollPosition, revision: UInt64, programmatic: Bool, settled: Bool
  ) {
    guard position.isValid, let document, document.revision == revision else { return }
    previewReading = position
    if !programmatic {
      // A new user gesture supersedes queued movement from the other pane.
      previewInputBegan(revision: revision)
      if linked, editor?.hasMarkedText() == false { moveSource(to: position) }
    }
    if restoredPreview || previewWasUsed || programmatic { schedulePersistence() }
    if settled { flush() }
  }

  @objc private func sourceBoundsChanged(_ notification: Notification) {
    guard !applyingSource, editor?.hasMarkedText() == false else { return }
    if liveSourceScroll {
      presentationAnchor = nil
      sourceWasUsed = true
      restoredSource = true
      driver = .source
    }
    if presentationAnchor != nil {
      layoutChanged()
      return
    }
    if !restoredSource, savedSource != nil {
      layoutChanged()
      return
    }
    if !sourceWasUsed, restoredSource {
      layoutChanged()
      return
    }
    guard sourceWasUsed || restoredSource, let reading = captureSource() else { return }
    sourceReading = reading
    schedulePersistence()
    if linked, driver == .source, previewIsReady, let position = sourcePosition() {
      pendingPreview = position
      sendPendingPreview()
    }
  }
  @objc private func sourceScrollStarted(_ notification: Notification) {
    if linked { preview?.sourceInputBegan() }
    presentationAnchor = nil
    liveSourceScroll = true
    sourceWasUsed = true
    restoredSource = true
    driver = .source
  }
  @objc private func sourceScrollEnded(_ notification: Notification) {
    sourceBoundsChanged(notification)
    liveSourceScroll = false
    flush()
  }
  @objc private func windowBecameVisible(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === editor?.window,
      window.isVisible, !sourceWasUsed || !restoredSource || !restoredPreview || needsAlignment
    else { return }
    layoutChanged()
  }
  @objc private func windowResigned(_ notification: Notification) {
    if notification.object as? NSWindow === editor?.window { flush() }
  }
  @objc private func applicationResigned(_ notification: Notification) { flush() }

  private func schedulePersistence() {
    persistenceTask?.cancel()
    persistenceTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      self?.flush()
    }
  }

  func flush() {
    persistenceTask?.cancel()
    persistenceTask = nil
    // Stable key order avoids publishing a new scene value for an unchanged position.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let sourceData = sourceReading.flatMap { $0.isValid ? try? encoder.encode($0) : nil }
    let previewData = previewReading.flatMap { $0.isValid ? try? encoder.encode($0) : nil }
    if let sourceData, let sourceStorage, sourceData != sourceStorage.wrappedValue {
      sourceStorage.wrappedValue = sourceData
    }
    if let previewData, let previewStorage, previewData != previewStorage.wrappedValue {
      previewStorage.wrappedValue = previewData
    }
    if let readingURL {
      DocumentReadingStore.shared.save(source: sourceData, preview: previewData, for: readingURL)
    }
  }

  deinit {
    layoutTask?.cancel()
    persistenceTask?.cancel()
    NotificationCenter.default.removeObserver(self)
  }
}

public struct DocumentScrollCommands: Commands {
  @Bindable private var preferences: AppPreferences
  public init(preferences: AppPreferences) { self.preferences = preferences }
  public var body: some Commands {
    CommandGroup(after: .sidebar) {
      Toggle("Editor on Right", isOn: $preferences.editorOnRight)
        .accessibilityIdentifier("editorOnRightCommand")
      Toggle("Link Editor and Preview Scrolling", isOn: $preferences.synchronizedScrolling)
        .accessibilityIdentifier("synchronizedScrollingCommand")
    }
  }
}
