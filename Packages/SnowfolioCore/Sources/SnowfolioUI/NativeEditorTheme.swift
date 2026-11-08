import AppKit
import CoreText
import EditorCore
import MarkdownCore

/// Compiles parsed theme data once on the UI actor. Per-paragraph resolution uses
/// only bounded semantic token sets; it never parses CSS or opens files in layout.
@MainActor
final class NativeEditorTheme {
  private struct Rule {
    let selector: String
    var attributes: [NSAttributedString.Key: Any] = [:]
    var caretColor: NSColor?
    var size: EditorTheme.FontSize?
    var family: String?
    var traits: NSFontTraitMask = []
    init(_ rule: EditorTheme.Rule) {
      selector = rule.selector
      for attribute in rule.attributes.reversed() {
        switch attribute.value {
        case .color(let value):
          let key: NSAttributedString.Key?
          switch attribute.name {
          case "foreground-color": key = .foregroundColor
          case "background-color": key = .backgroundColor
          case "caret-color":
            caretColor = Self.color(value)
            key = nil
          default: key = nil
          }
          if let key { attributes[key] = Self.color(value) }
        case .fontSize(let value): size = value
        case .fontFamily(let value): family = value
        case .fontStyle(let value):
          if value.contains(.bold) { traits.insert(.boldFontMask) }
          if value.contains(.italic) { traits.insert(.italicFontMask) }
          if value.contains(.underlined) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
          }
        case .custom: break
        }
      }
    }

    private static func color(_ value: EditorTheme.Color) -> NSColor {
      NSColor(
        srgbRed: Double(value.red) / 255, green: Double(value.green) / 255,
        blue: Double(value.blue) / 255, alpha: Double(value.alpha) / 255)
    }

    private static func namedFace(_ name: String, replacing font: NSFont) -> NSFont? {
      // System-font conversion can give a named face different caret metrics.
      // Start from that face's native descriptor and pass its matching language hint.
      guard let face = NSFont(name: name, size: font.pointSize) else {
        return NSFontManager.shared.convert(font, toFace: name)
      }
      let key = NSFontDescriptor.AttributeName(
        rawValue: kCTFontDescriptorLanguageAttribute as String)
      guard let language = font.fontDescriptor.fontAttributes[key] as? String, !language.isEmpty
      else {
        return face
      }
      return NSFont(
        descriptor: face.fontDescriptor.addingAttributes([key: language]), size: face.pointSize)
        ?? face
    }

    func apply(to attributes: inout [NSAttributedString.Key: Any], base: NSFont, zoom: Double) {
      var font = attributes[.font] as? NSFont ?? base
      let manager = NSFontManager.shared
      if let size, size.points != 0 {
        let points =
          size.relative ? base.pointSize + Double(size.points) * zoom : Double(size.points) * zoom
        font = manager.convert(font, toSize: max(4 * zoom, min(8192, points)))
      }
      if let family { font = Self.namedFace(family, replacing: font) ?? font }
      if !traits.isEmpty { font = manager.convert(font, toHaveTrait: traits) }
      attributes.merge(self.attributes) { _, new in new }
      attributes[.font] = font
    }
  }

  let baseAttributes: [NSAttributedString.Key: Any]
  let backgroundColor: NSColor?
  let caretColor: NSColor?
  let selectionAttributes: [NSAttributedString.Key: Any]
  let currentLineBackground: NSColor?
  let hasCurrentLineStyle: Bool
  let currentLineChangesGeometry: Bool
  private let currentLine: Rule?
  private struct Resolution: Hashable {
    let tokens: [MarkdownSyntaxToken]
    let currentLine: Bool
  }
  private let rules: [Rule]
  private let base: NSFont
  private let zoom: Double
  private var cache: [Resolution: [NSAttributedString.Key: Any]] = [:]

  init(_ theme: EditorTheme, font: NSFont, zoom: Double) {
    self.zoom = DocumentZoomController.normalizedScale(zoom)
    let compiled = theme.rules.map(Rule.init)
    var attributes: [NSAttributedString.Key: Any] = [
      .font: font, .foregroundColor: NSColor.textColor,
    ]
    for rule in compiled where rule.selector == "editor" {
      rule.apply(to: &attributes, base: font, zoom: self.zoom)
    }
    backgroundColor = attributes.removeValue(forKey: .backgroundColor) as? NSColor
    caretColor = compiled.last { $0.selector == "editor" }?.caretColor
    let selection = compiled.last { $0.selector == "editor-selection" }
    selectionAttributes =
      selection?.attributes.filter { key, _ in
        [.foregroundColor, .backgroundColor, .underlineStyle].contains(key)
      } ?? [:]
    var current = compiled.last { $0.selector == "editor-current-line" }
    currentLineBackground = current?.attributes.removeValue(forKey: .backgroundColor) as? NSColor
    hasCurrentLineStyle =
      currentLineBackground != nil
      || current.map {
        !$0.attributes.isEmpty || $0.size != nil || $0.family != nil || !$0.traits.isEmpty
      } ?? false
    currentLineChangesGeometry =
      current.map {
        $0.size != nil || $0.family != nil || !$0.traits.isEmpty
      } ?? false
    currentLine = current
    baseAttributes = attributes
    base = attributes[.font] as? NSFont ?? font
    rules = compiled.filter { !$0.selector.hasPrefix("editor") }
  }

  func attributes(for tokens: [MarkdownSyntaxToken], currentLine active: Bool = false)
    -> [NSAttributedString.Key: Any]
  {
    let key = Resolution(tokens: tokens, currentLine: active)
    if let cached = cache[key] { return cached }
    let selectors = Set(tokens.map(Self.selector))
    var attributes = baseAttributes
    // Preserve original global theme rule ordering when semantic scopes overlap.
    for rule in rules where selectors.contains(rule.selector) {
      rule.apply(to: &attributes, base: base, zoom: zoom)
    }
    if active { currentLine?.apply(to: &attributes, base: base, zoom: zoom) }
    if cache.count < 512 { cache[key] = attributes }
    return attributes
  }

  private static func selector(_ token: MarkdownSyntaxToken) -> String {
    switch token {
    case .heading(let level): return "H\(level)"
    case .entity: return "HTML_ENTITY"
    case .referenceDefinition: return "REFERENCE"
    case .note: return "NOTE"
    case .emphasis: return "EMPH"
    case .strong: return "STRONG"
    case .inlineCode: return "CODE"
    case .codeBlock: return "VERBATIM"
    case .link: return "LINK"
    case .automaticURL: return "AUTO_LINK_URL"
    case .automaticEmail: return "AUTO_LINK_EMAIL"
    case .image: return "IMAGE"
    case .blockquote: return "BLOCKQUOTE"
    case .comment: return "COMMENT"
    case .inlineHTML: return "HTML"
    case .blockHTML: return "HTMLBLOCK"
    case .horizontalRule: return "HRULE"
    case .listBullet: return "LIST_BULLET"
    case .listEnumerator: return "LIST_ENUMERATOR"
    }
  }
}
