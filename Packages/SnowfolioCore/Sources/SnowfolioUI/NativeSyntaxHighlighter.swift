import AppKit
import EditorCore
import MarkdownCore

/// TextKit 2 rendering attributes and custom paragraphs are disposable presentation.
/// They never enter NSTextStorage, source snapshots, or the undo stack.
@MainActor
final class NativeSyntaxHighlighter: NSObject, @MainActor NSTextContentStorageDelegate {
  weak var editor: MarkdownTextView?
  weak var document: MarkdownDocument?
  private var syntax: MarkdownSyntax?
  private var revision: UInt64?
  private var enabled = true
  private var font: NSFont?
  private var refreshingPresentation = false
  private var themeID: UUID?
  private var themePresentation: NativeEditorTheme?
  private var zoomScale = 1.0
  private var surfaceAppearance: NativeEditorSurfaceAppearance?
  private(set) var currentLineRange: NSRange?
  private var currentLineCaret: Int?
  private var currentLineRevision: UInt64?

  func attach(to editor: MarkdownTextView, document: MarkdownDocument) {
    self.editor = editor
    surfaceAppearance = NativeEditorSurfaceAppearance(editor: editor)
    self.document = document
    editor.syntaxHighlighter = self
    if let content = editor.textLayoutManager?.textContentManager as? NSTextContentStorage {
      // The standard NSTextView TextKit 2 content storage has no delegate. Do
      // not replace a delegate owned by another content provider.
      if content.delegate == nil { content.delegate = self }
    }
    editor.textLayoutManager?.renderingAttributesValidator = { [weak self] manager, fragment in
      self?.validate(manager, range: fragment.rangeInElement)
    }
  }

  func update(
    syntax: MarkdownSyntax?, revision: UInt64?, enabled: Bool, font: NSFont,
    document: MarkdownDocument, theme: EditorTheme? = nil, zoomScale: Double = 1
  ) {
    let normalizedZoom = DocumentZoomController.normalizedScale(zoomScale)
    let themeGeometryChanged =
      self.themeID != theme?.id
      || (theme != nil
        && (self.zoomScale != normalizedZoom || self.enabled != enabled
          || self.syntax?.id != syntax?.id
          || self.revision != revision))
    let canRefreshGeometry =
      editor.map { !$0.hasMarkedText() && !$0.isReceivingMarkedText } ?? false
    if themeGeometryChanged && canRefreshGeometry { editor?.viewportPresentationWillChange?() }
    let presentationChanged =
      self.themeID != theme?.id || self.font != font || self.zoomScale != normalizedZoom
    if presentationChanged {
      themePresentation = theme.map { NativeEditorTheme($0, font: font, zoom: normalizedZoom) }
    }
    self.themeID = theme?.id
    self.zoomScale = normalizedZoom
    let changed =
      self.syntax?.id != syntax?.id || self.revision != revision || self.enabled != enabled
      || presentationChanged || self.document !== document
    if self.document !== document {
      currentLineRevision = nil
      currentLineCaret = nil
    }
    self.document = document
    self.syntax = syntax
    self.revision = revision
    self.enabled = enabled
    self.font = font
    if let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText, editor.font != font {
      editor.viewportPresentationWillChange?()
      editor.font = font
      editor.viewportLayoutChanged?()
    }
    if presentationChanged { surfaceAppearance?.apply(themePresentation) }
    if changed { invalidate() }
    if themeGeometryChanged && canRefreshGeometry { editor?.viewportLayoutChanged?() }
  }

  func invalidate() {
    guard !refreshingPresentation,
      let manager = editor?.textLayoutManager, let content = manager.textContentManager
    else {
      return
    }
    _ = refreshCurrentLine()
    manager.invalidateRenderingAttributes(for: content.documentRange)
    // Refresh cached viewport fragments without forcing offscreen layout. Before
    // the first viewport exists, walk only fragments TextKit has already created.
    let viewport = manager.textViewportLayoutController.viewportRange
    manager.enumerateTextLayoutFragments(
      from: viewport?.location ?? content.documentRange.location, options: []
    ) { fragment in
      if let viewport,
        fragment.rangeInElement.location.compare(viewport.endLocation) != .orderedAscending
      {
        return false
      }
      self.validate(manager, range: fragment.rangeInElement)
      return true
    }
    editor?.needsDisplay = true
    if let viewport, let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText,
      let document, revision == document.revision, let storage = editor.textStorage
    {
      let start = content.offset(from: content.documentRange.location, to: viewport.location)
      let end = content.offset(from: content.documentRange.location, to: viewport.endLocation)
      if start >= 0, end >= start, end <= storage.length {
        // Notify the owning text view that paragraph presentation changed. This
        // attributes-only notification changes no stored attributes or source bytes.
        refreshingPresentation = true
        defer { refreshingPresentation = false }
        storage.edited(
          .editedAttributes, range: NSRange(location: start, length: end - start),
          changeInLength: 0)
      }
    }
  }

  func compositionChanged() {
    if let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText, let font,
      editor.font != font
    {
      editor.viewportPresentationWillChange?()
      editor.font = font
      editor.viewportLayoutChanged?()
    }
    invalidate()
  }

  func textContentStorage(
    _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
  ) -> NSTextParagraph? {
    guard let presentation = themePresentation, let editor,
      !editor.hasMarkedText(), !editor.isReceivingMarkedText,
      let storage = textContentStorage.textStorage,
      range.location >= 0, range.length > 0, range.location <= storage.length,
      range.length <= storage.length - range.location
    else { return nil }
    let paragraph = NSMutableAttributedString(
      attributedString: storage.attributedSubstring(from: range))
    let activeLine = currentLineRange?.location == range.location
    paragraph.addAttributes(
      presentation.attributes(for: [], currentLine: activeLine),
      range: NSRange(location: 0, length: range.length))
    if enabled, let document, revision == document.revision, let syntax {
      for run in intersectingRuns(range, syntax: syntax) {
        let intersection = NSIntersectionRange(run.range, range)
        var attributes = presentation.attributes(for: run.style.tokens, currentLine: activeLine)
        if run.style.underlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if run.style.strikethrough {
          attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if run.style.highlighted, run.style.role != .code {
          attributes[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.18)
        }
        paragraph.addAttributes(
          attributes,
          range: NSRange(
            location: intersection.location - range.location, length: intersection.length))
      }
    }
    return NSTextParagraph(attributedString: paragraph)
  }

  func selectionChanged() {
    guard !refreshingPresentation, refreshCurrentLine() else { return }
    let geometry = themePresentation?.currentLineChangesGeometry == true
    if geometry { editor?.viewportPresentationWillChange?() }
    invalidate()
    if geometry { editor?.viewportLayoutChanged?() }
  }

  @discardableResult
  private func refreshCurrentLine() -> Bool {
    let previous = currentLineRange
    guard themePresentation?.hasCurrentLineStyle == true, let editor, let document,
      !editor.hasMarkedText(), !editor.isReceivingMarkedText,
      editor.selectedRanges.count == 1
    else {
      currentLineRange = nil
      currentLineCaret = nil
      currentLineRevision = nil
      return previous != nil
    }
    let selection = editor.selectedRange()
    let length = editor.textStorage?.length ?? 0
    guard selection.length == 0, selection.location <= length else {
      currentLineRange = nil
      currentLineCaret = nil
      currentLineRevision = nil
      return previous != nil
    }
    // Moving within an unchanged logical line needs no scanning or relayout.
    if currentLineRevision == document.revision,
      currentLineCaret == selection.location
        || previous.map({ NSLocationInRange(selection.location, $0) }) == true
    {
      currentLineCaret = selection.location
      return false
    }
    currentLineRange = (editor.string as NSString).lineRange(for: selection)
    currentLineCaret = selection.location
    currentLineRevision = document.revision
    return previous != currentLineRange
  }

  func currentLineBackgroundRect() -> NSRect? {
    guard themePresentation?.currentLineBackground != nil, let editor, let currentLineRange else {
      return nil
    }
    return NativeEditorCurrentLine.backgroundRect(in: editor, line: currentLineRange)
  }

  func drawCurrentLineBackground(in dirtyRect: NSRect) {
    guard let color = themePresentation?.currentLineBackground,
      let frame = currentLineBackgroundRect()
    else { return }
    let visible = frame.intersection(dirtyRect)
    guard !visible.isEmpty else { return }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    color.setFill()
    NSBezierPath.fill(visible)
  }

  private func intersectingRuns(_ range: NSRange, syntax: MarkdownSyntax) -> ArraySlice<
    MarkdownSyntaxRun
  > {
    var low = 0
    var high = syntax.runs.count
    while low < high {
      let middle = (low + high) / 2
      if NSMaxRange(syntax.runs[middle].range) <= range.location {
        low = middle + 1
      } else {
        high = middle
      }
    }
    var end = low
    while end < syntax.runs.count, syntax.runs[end].range.location < NSMaxRange(range) { end += 1 }
    return syntax.runs[low..<end]
  }

  func detach() {
    surfaceAppearance?.restore()
    surfaceAppearance = nil
    currentLineRange = nil
    currentLineCaret = nil
    currentLineRevision = nil
    if let content = editor?.textLayoutManager?.textContentManager as? NSTextContentStorage,
      content.delegate === self
    {
      content.delegate = nil
    }
    editor?.textLayoutManager?.renderingAttributesValidator = nil
    editor?.syntaxHighlighter = nil
    editor = nil
    document = nil
    syntax = nil
    revision = nil
    themeID = nil
    themePresentation = nil
    font = nil
  }

  private func validate(_ manager: NSTextLayoutManager, range: NSTextRange) {
    manager.setRenderingAttributes([:], for: range)
    guard themePresentation == nil, enabled, let editor, !editor.hasMarkedText(),
      !editor.isReceivingMarkedText,
      let document, document.revision == revision, let syntax,
      let content = manager.textContentManager
    else { return }
    let origin = content.documentRange.location
    let lower = content.offset(from: origin, to: range.location)
    let upper = content.offset(from: origin, to: range.endLocation)
    guard lower >= 0, upper >= lower, upper != NSNotFound else { return }
    var low = 0
    var high = syntax.runs.count
    while low < high {
      let middle = (low + high) / 2
      if NSMaxRange(syntax.runs[middle].range) <= lower { low = middle + 1 } else { high = middle }
    }
    while low < syntax.runs.count, syntax.runs[low].range.location < upper {
      let run = syntax.runs[low]
      let start = max(lower, run.range.location)
      let end = min(upper, NSMaxRange(run.range))
      if end > start, let first = content.location(origin, offsetBy: start),
        let last = content.location(origin, offsetBy: end),
        let textRange = NSTextRange(location: first, end: last)
      {
        manager.setRenderingAttributes(attributes(run.style), for: textRange)
      }
      low += 1
    }
  }

  private func attributes(_ style: MarkdownSyntaxStyle) -> [NSAttributedString.Key:
    Any]
  {
    // Temporary foreground/background colors preserve the editor's layout metrics.
    // Font/decoration attributes are not reliably honored by NSTextView's TextKit 2
    // rendering path; do not publish misleading font traits or mutate text storage.
    var attributes: [NSAttributedString.Key: Any] = [:]
    switch style.role {
    case .link: attributes[.foregroundColor] = NSColor.linkColor
    case .code:
      attributes[.foregroundColor] = NSColor.secondaryLabelColor
      attributes[.backgroundColor] = NSColor.quaternaryLabelColor
    case .quote, .comment, .marker: attributes[.foregroundColor] = NSColor.secondaryLabelColor
    case .heading: attributes[.foregroundColor] = NSColor.systemBlue
    case .text:
      if style.bold && style.italic {
        attributes[.foregroundColor] = NSColor.systemPink
      } else if style.bold {
        attributes[.foregroundColor] = NSColor.systemPurple
      } else if style.italic {
        attributes[.foregroundColor] = NSColor.systemOrange
      } else if style.underlined {
        attributes[.foregroundColor] = NSColor.systemTeal
      } else if style.strikethrough {
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
      } else {
        attributes[.foregroundColor] = NSColor.textColor
      }
    }
    if style.highlighted, style.role != .code {
      attributes[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.18)
    }
    return attributes
  }
}
