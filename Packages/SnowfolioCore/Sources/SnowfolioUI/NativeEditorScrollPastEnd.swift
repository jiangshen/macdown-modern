import AppKit

@MainActor
final class MarkdownEditorClipView: NSClipView {
  override var documentRect: NSRect {
    var rect = super.documentRect
    if let minimum = (documentView as? MarkdownTextView)?.scrollPastEndMinimumHeight {
      rect.size.height = max(rect.height, minimum)
    }
    return rect
  }
}

@MainActor
final class MarkdownEditorScrollView: NSScrollView {
  override func layout() {
    super.layout()
    (documentView as? MarkdownTextView)?.refreshScrollPastEnd()
  }
}

/// Adds reversible scrolling space through the native clip view. Text and the
/// text view's own frame remain native; trailing blank lines already supply space.
@MainActor
final class NativeEditorScrollPastEnd {
  private weak var editor: MarkdownTextView?
  private weak var scroll: NSScrollView?
  private var originalInsets: NSEdgeInsets?
  private var originalAutomatic = true
  private var effectiveBaseInsets = NSEdgeInsetsZero
  private(set) var minimumHeight: CGFloat?
  private var updating = false
  private struct SourceKey: Equatable {
    let document: ObjectIdentifier?
    let revision: UInt64?
    let loadRevision: UInt64?
    let length: Int
  }
  private struct GeometryKey: Equatable {
    let source: SourceKey
    let width: CGFloat
    let inset: NSSize
    let font: NSFont?
    let spacing: CGFloat?
    let usage: CGRect
  }
  private var sourceKey: SourceKey?
  private var lastVisible: NSRange?
  private var geometryKey: GeometryKey?
  private var contentHeight: CGFloat = 0
  private var trailingHeight: CGFloat = 0

  init(editor: MarkdownTextView) { self.editor = editor }

  func refresh() {
    guard !updating, let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText,
      let container = editor.enclosingScrollView
    else { return }
    updating = true
    defer { updating = false }
    if scroll !== container {
      restore()
      scroll = container
    }
    guard editor.layoutPreferences?.scrollsPastEnd == true else {
      restore()
      return
    }
    guard let manager = editor.textLayoutManager, editor.window != nil else { return }
    let key = SourceKey(
      document: editor.sourceDocument.map(ObjectIdentifier.init),
      revision: editor.sourceRevision, loadRevision: editor.sourceDocument?.loadRevision,
      length: editor.textStorage?.length ?? 0)
    if sourceKey != key {
      let source = editor.string as NSString
      sourceKey = key
      let found = source.rangeOfCharacter(
        from: .whitespacesAndNewlines.inverted, options: .backwards)
      lastVisible =
        found.location == NSNotFound
        ? nil : source.rangeOfComposedCharacterSequence(at: found.location)
      geometryKey = nil
    }
    let geometry = GeometryKey(
      source: key, width: editor.textContainer?.containerSize.width ?? 0,
      inset: editor.textContainerInset,
      font: editor.font, spacing: editor.syntaxHighlighter?.appliedLineSpacing,
      usage: manager.usageBoundsForTextContainer)
    if geometryKey != geometry {
      contentHeight = 0
      trailingHeight = 0
      if let lastVisible {
        let end = NSRange(location: key.length, length: 0)
        guard let last = rectangle(lastVisible, in: editor),
          let terminal = rectangle(end, in: editor)
        else { return }
        contentHeight = terminal.maxY + editor.textContainerInset.height
        trailingHeight = max(0, terminal.maxY - last.maxY)
      }
      geometryKey = GeometryKey(
        source: key, width: geometry.width, inset: geometry.inset, font: geometry.font,
        spacing: geometry.spacing,
        usage: manager.usageBoundsForTextContainer)
    }
    let extra = max(
      0,
      min(container.contentView.bounds.height, contentHeight)
        - trailingHeight - 2 * editor.textContainerInset.height)
    guard extra > 0 else {
      restore()
      return
    }
    if originalInsets == nil {
      originalInsets = container.contentInsets
      effectiveBaseInsets = container.contentView.contentInsets
      originalAutomatic = container.automaticallyAdjustsContentInsets
    }
    let previousMinimum = minimumHeight
    minimumHeight = max(
      0,
      container.contentView.bounds.height - effectiveBaseInsets.top - effectiveBaseInsets.bottom)
    var desired = effectiveBaseInsets
    desired.bottom += extra
    let insetsChanged = !equal(container.contentInsets, desired)
    guard insetsChanged || previousMinimum != minimumHeight else { return }
    if insetsChanged {
      container.automaticallyAdjustsContentInsets = false
      container.contentInsets = desired
    }
    container.contentView.scroll(to: container.contentView.bounds.origin)
    container.reflectScrolledClipView(container.contentView)
    editor.viewportLayoutChanged?()
  }

  private func rectangle(_ range: NSRange, in editor: MarkdownTextView) -> NSRect? {
    guard let manager = editor.textLayoutManager, let content = manager.textContentManager,
      let start = content.location(content.documentRange.location, offsetBy: range.location),
      let end = content.location(start, offsetBy: range.length),
      let textRange = NSTextRange(location: start, end: end)
    else { return nil }
    manager.ensureLayout(for: textRange)
    var result: NSRect?
    manager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, rect, _, _ in
      if rect.height > 0 { result = rect }
      return false
    }
    guard let result else { return nil }
    let local = result.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
    guard local.minY.isFinite, local.height.isFinite, local.height > 0 else { return nil }
    return local
  }

  private func restore() {
    let insets = originalInsets
    originalInsets = nil
    minimumHeight = nil
    if insets != nil { geometryKey = nil }
    guard let scroll, let insets else { return }
    scroll.contentInsets = insets
    scroll.automaticallyAdjustsContentInsets = originalAutomatic
    scroll.contentView.scroll(to: scroll.contentView.bounds.origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    editor?.viewportLayoutChanged?()
  }

  private func equal(_ first: NSEdgeInsets, _ second: NSEdgeInsets) -> Bool {
    first.top == second.top && first.left == second.left
      && first.bottom == second.bottom && first.right == second.right
  }
}
