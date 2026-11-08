import AppKit
import EditorCore
import MarkdownCore

/// Syntax attributes and custom paragraphs are disposable presentation. Native
/// writing font/color also drive typing, composition, carets and extra lines.
/// Those view preferences never edit Markdown source or add an undo action.
@MainActor
final class NativeSyntaxHighlighter: NSObject, @MainActor NSTextContentStorageDelegate {
  weak var editor: MarkdownTextView?
  weak var document: MarkdownDocument?
  private var syntax: MarkdownSyntax?
  private var revision: UInt64?
  private var enabled = true
  private var font: NSFont?
  private var refreshingPresentation = false
  private var settingNativeStyle = false
  private var originalTextColor: NSColor?
  private var pendingSurface = false
  private var themeID: UUID?
  private var themePresentation: NativeEditorTheme?
  private var zoomScale = 1.0
  private var paragraphSpacing: NativeEditorLineSpacing?
  var appliedLineSpacing: CGFloat? { paragraphSpacing?.applied }
  private var surfaceAppearance: NativeEditorSurfaceAppearance?
  private(set) var currentLineRange: NSRange?
  private var currentLineCaret: Int?
  private var currentLineRevision: UInt64?

  func attach(to editor: MarkdownTextView, document: MarkdownDocument) {
    self.editor = editor
    paragraphSpacing = NativeEditorLineSpacing(editor: editor)
    originalTextColor = editor.textColor
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
    document: MarkdownDocument, theme: EditorTheme? = nil, zoomScale: Double = 1,
    lineSpacing: Double? = nil
  ) {
    let normalizedZoom = DocumentZoomController.normalizedScale(zoomScale)
    let normalizedSpacing = lineSpacing.map {
      CGFloat(EditorLayoutPreferences(lineSpacing: $0).lineSpacing)
    }
    let spacingChanged = paragraphSpacing?.requested != normalizedSpacing
    paragraphSpacing?.requested = normalizedSpacing
    let themeGeometryChanged =
      spacingChanged || self.themeID != theme?.id
      || (theme != nil
        && (self.font != font || self.zoomScale != normalizedZoom || self.enabled != enabled
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
      || presentationChanged || spacingChanged || self.document !== document
    if self.document !== document {
      currentLineRevision = nil
      currentLineCaret = nil
    }
    self.document = document
    self.syntax = syntax
    self.revision = revision
    self.enabled = enabled
    self.font = font
    if presentationChanged { applySurfaceWhenSafe() }
    if changed {
      invalidate(geometryAlreadyChanging: themeGeometryChanged && canRefreshGeometry)
    }
    if themeGeometryChanged && canRefreshGeometry { editor?.viewportLayoutChanged?() }
  }

  func invalidate(geometryAlreadyChanging: Bool = false) {
    guard !refreshingPresentation, !settingNativeStyle,
      let manager = editor?.textLayoutManager, let content = manager.textContentManager
    else {
      return
    }
    _ = refreshCurrentLine()
    if pendingSurface { applySurfaceWhenSafe() }
    let spacingGeometryChanged = paragraphSpacing?.needsSynchronization == true
    let nativeGeometryChanged = synchronizeNativeWritingStyle(
      geometryAlreadyChanging: geometryAlreadyChanging)
    defer {
      if nativeGeometryChanged && !geometryAlreadyChanging { editor?.viewportLayoutChanged?() }
    }
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
    guard let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText,
      let storage = editor.textStorage
    else { return }
    let refreshedRange: NSRange
    if spacingGeometryChanged {
      // Invalidate cached paragraph presentation without forcing offscreen layout.
      // A view preference must refresh even while a parsed snapshot is stale.
      refreshedRange = NSRange(location: 0, length: storage.length)
    } else if let viewport, let document, revision == document.revision {
      let start = content.offset(from: content.documentRange.location, to: viewport.location)
      let end = content.offset(from: content.documentRange.location, to: viewport.endLocation)
      guard start >= 0, end >= start, end <= storage.length else { return }
      refreshedRange = NSRange(location: start, length: end - start)
    } else {
      return
    }
    refreshingPresentation = true
    defer { refreshingPresentation = false }
    storage.edited(.editedAttributes, range: refreshedRange, changeInLength: 0)
  }

  func compositionChanged() { invalidate() }

  private func applySurfaceWhenSafe() {
    guard let editor else { return }
    guard !editor.hasMarkedText(), !editor.isReceivingMarkedText else {
      pendingSurface = true
      return
    }
    surfaceAppearance?.apply(themePresentation)
    pendingSurface = false
  }

  /// Native writing defaults drive typing, marked text and extra-line layout.
  /// Semantic syntax and existing-paragraph spacing remain disposable copies.
  private func synchronizeNativeWritingStyle(geometryAlreadyChanging: Bool) -> Bool {
    guard let editor, let font, !editor.hasMarkedText(), !editor.isReceivingMarkedText else {
      return false
    }
    let attributes = themePresentation?.attributes(for: [], currentLine: currentLineRange != nil)
    let desiredFont = attributes?[.font] as? NSFont ?? font
    let desiredColor = attributes?[.foregroundColor] as? NSColor ?? originalTextColor
    let fontChanged = editor.font != desiredFont
    let colorChanged = editor.textColor != desiredColor
    let geometryChanged = fontChanged || paragraphSpacing?.needsSynchronization == true
    if geometryChanged && !geometryAlreadyChanging { editor.viewportPresentationWillChange?() }
    settingNativeStyle = true
    defer { settingNativeStyle = false }
    if fontChanged { editor.font = desiredFont }
    if colorChanged { editor.textColor = desiredColor }
    paragraphSpacing?.synchronize()
    return geometryChanged
  }

  func textContentStorage(
    _ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange
  ) -> NSTextParagraph? {
    guard let editor, let storage = textContentStorage.textStorage,
      range.location >= 0, range.length > 0, range.location <= storage.length,
      range.length <= storage.length - range.location
    else { return nil }
    let presentation =
      editor.hasMarkedText() || editor.isReceivingMarkedText ? nil : themePresentation
    guard
      presentation != nil || paragraphSpacing?.needsPresentation(in: storage, range: range) == true
    else { return nil }
    let paragraph = NSMutableAttributedString(
      attributedString: storage.attributedSubstring(from: range))
    paragraphSpacing?.apply(to: paragraph)
    if let presentation {
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
    }
    return NSTextParagraph(attributedString: paragraph)
  }

  func selectionChanged() {
    guard !refreshingPresentation, !settingNativeStyle else { return }
    settingNativeStyle = true
    paragraphSpacing?.synchronizeTyping()
    settingNativeStyle = false
    guard refreshCurrentLine() else { return }
    let geometry = themePresentation?.currentLineChangesGeometry == true
    if geometry { editor?.viewportPresentationWillChange?() }
    invalidate(geometryAlreadyChanging: geometry)
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
    let restoreWritingStyle = themePresentation != nil || pendingSurface
    let defaultFont = restoreWritingStyle ? font : nil
    surfaceAppearance?.restore()
    surfaceAppearance = nil
    paragraphSpacing?.restore()
    paragraphSpacing = nil
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
    if let editor, restoreWritingStyle, !editor.hasMarkedText(), !editor.isReceivingMarkedText {
      if let defaultFont, editor.font != defaultFont { editor.font = defaultFont }
      if editor.textColor != originalTextColor { editor.textColor = originalTextColor }
    }
    originalTextColor = nil
    pendingSurface = false
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
