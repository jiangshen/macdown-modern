import AppKit
import MarkdownCore

/// TextKit 2 rendering attributes are disposable presentation. They never enter
/// NSTextStorage, source snapshots, native typing attributes, or the undo stack.
@MainActor
final class NativeSyntaxHighlighter {
  weak var editor: MarkdownTextView?
  weak var document: MarkdownDocument?
  private var syntax: MarkdownSyntax?
  private var revision: UInt64?
  private var enabled = true
  private var font: NSFont?

  func attach(to editor: MarkdownTextView, document: MarkdownDocument) {
    self.editor = editor
    self.document = document
    editor.syntaxHighlighter = self
    editor.textLayoutManager?.renderingAttributesValidator = { [weak self] manager, fragment in
      self?.validate(manager, range: fragment.rangeInElement)
    }
  }

  func update(
    syntax: MarkdownSyntax?, revision: UInt64?, enabled: Bool, font: NSFont,
    document: MarkdownDocument
  ) {
    let changed =
      self.syntax?.id != syntax?.id || self.revision != revision || self.enabled != enabled
      || self.font != font || self.document !== document
    self.document = document
    self.syntax = syntax
    self.revision = revision
    self.enabled = enabled
    self.font = font
    if let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText, editor.font != font {
      editor.font = font
    }
    if changed { invalidate() }
  }

  func invalidate() {
    guard let manager = editor?.textLayoutManager, let content = manager.textContentManager else {
      return
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
  }

  func compositionChanged() {
    if let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText, let font,
      editor.font != font
    {
      editor.font = font
    }
    invalidate()
  }

  func detach() {
    editor?.textLayoutManager?.renderingAttributesValidator = nil
    editor?.syntaxHighlighter = nil
    editor = nil
    document = nil
  }

  private func validate(_ manager: NSTextLayoutManager, range: NSTextRange) {
    manager.setRenderingAttributes([:], for: range)
    guard enabled, let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText,
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
      } else if style.strikethrough {
        attributes[.foregroundColor] = NSColor.secondaryLabelColor
      } else {
        attributes[.foregroundColor] = NSColor.textColor
      }
    }
    return attributes
  }
}
