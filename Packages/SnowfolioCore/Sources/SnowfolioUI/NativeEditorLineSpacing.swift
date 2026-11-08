import AppKit

/// Paragraph spacing is presentation, with native defaults for new/extra lines.
/// Existing backing attributes, including marked-text attributes, stay intact.
@MainActor
final class NativeEditorLineSpacing {
  private weak var editor: MarkdownTextView?
  private let originalDefault: NSParagraphStyle?
  private let originalTyping: NSParagraphStyle?
  var requested: CGFloat?
  private(set) var applied: CGFloat?
  var needsSynchronization: Bool { requested != applied }

  init(editor: MarkdownTextView) {
    self.editor = editor
    originalDefault = editor.defaultParagraphStyle
    originalTyping = editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
  }

  func synchronize() {
    guard let editor, !editor.hasMarkedText(), !editor.isReceivingMarkedText else { return }
    if needsSynchronization {
      applied = requested
      editor.defaultParagraphStyle =
        applied.map { Self.style(originalDefault, spacing: $0) }
        ?? originalDefault
      if applied == nil { restoreTyping() }
    }
    synchronizeTyping()
  }

  func synchronizeTyping() {
    guard let editor, let applied, !editor.hasMarkedText(), !editor.isReceivingMarkedText else {
      return
    }
    let current = editor.typingAttributes[.paragraphStyle] as? NSParagraphStyle
    guard (current ?? .default).lineSpacing != applied else {
      return
    }
    var attributes = editor.typingAttributes
    attributes[.paragraphStyle] = Self.style(
      current ?? editor.defaultParagraphStyle, spacing: applied)
    editor.typingAttributes = attributes
  }

  func apply(to paragraph: NSMutableAttributedString) {
    guard let applied else { return }
    let range = NSRange(location: 0, length: paragraph.length)
    paragraph.enumerateAttribute(.paragraphStyle, in: range) { value, range, _ in
      let current = value as? NSParagraphStyle
      guard (current ?? .default).lineSpacing != applied else { return }
      paragraph.addAttribute(
        .paragraphStyle, value: Self.style(current, spacing: applied), range: range)
    }
  }

  func needsPresentation(in storage: NSTextStorage, range: NSRange) -> Bool {
    guard let applied else { return false }
    if applied != 0 { return true }
    // Keep the normal zero-spacing editor on its existing native path. Copies
    // are needed only for paragraphs carrying an earlier native typing style.
    var needed = false
    storage.enumerateAttribute(.paragraphStyle, in: range) { value, _, stop in
      if let style = value as? NSParagraphStyle, style.lineSpacing != 0 {
        needed = true
        stop.pointee = true
      }
    }
    return needed
  }

  func restore() {
    guard let editor, applied != nil, !editor.hasMarkedText(), !editor.isReceivingMarkedText else {
      return
    }
    editor.defaultParagraphStyle = originalDefault
    restoreTyping()
    requested = nil
    applied = nil
  }

  private func restoreTyping() {
    guard let editor else { return }
    var attributes = editor.typingAttributes
    attributes[.paragraphStyle] = originalTyping
    editor.typingAttributes = attributes
  }

  private static func style(_ original: NSParagraphStyle?, spacing: CGFloat) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    style.setParagraphStyle(original ?? .default)
    style.lineSpacing = spacing
    return style
  }
}
