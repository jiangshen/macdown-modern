import Foundation

public enum CodeHighlightTheme: String, CaseIterable, Sendable {
  case adaptive, prism, coy, dark, funky, okaidia, solarizedlight, tomorrow, twilight

  public var title: String {
    switch self {
    case .adaptive: "Snowfolio"
    case .prism: "Prism"
    case .coy: "Coy"
    case .dark: "Dark"
    case .funky: "Funky"
    case .okaidia: "Okaidia"
    case .solarizedlight: "Solarized Light"
    case .tomorrow: "Tomorrow"
    case .twilight: "Twilight"
    }
  }

  public static func legacyName(_ name: String?) -> Self {
    guard let name else { return .adaptive }
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return Self(rawValue: normalized.isEmpty || normalized == "default" ? "prism" : normalized)
      ?? .prism
  }

  public var css: String {
    guard self != .adaptive else { return Self.adaptiveCSS }
    let file = self == .prism ? "prism" : "prism-" + rawValue
    guard let url = Bundle.module.url(forResource: file, withExtension: "css"),
      let css = try? String(contentsOf: url, encoding: .utf8)
    else {
      assertionFailure("Bundled Prism theme missing")
      return Self.adaptiveCSS
    }
    return css
  }

  private static let adaptiveCSS = """
    pre[data-code-highlighted] { color: #37352f; background: #f7f6f3; }
    pre .token.comment, pre .token.prolog, pre .token.doctype, pre .token.cdata { color: #68655f; }
    pre .token.punctuation { color: inherit; }
    pre .token.keyword, pre .token.atrule { color: #7c3ea1; }
    pre .token.string, pre .token.char, pre .token.attr-value, pre .token.inserted { color: #2a6f3b; }
    pre .token.number, pre .token.boolean, pre .token.constant { color: #945200; }
    pre .token.function, pre .token.class-name, pre .token.builtin { color: #245aa8; }
    pre .token.tag, pre .token.property, pre .token.selector, pre .token.deleted { color: #a4423b; }
    pre .token.operator, pre .token.entity, pre .token.url, pre .token.variable { color: #6950a1; }
    pre .token.regex, pre .token.important { color: #875118; }
    pre .token.bold, pre .token.important { font-weight: 650; }
    pre .token.italic { font-style: italic; }
    @media (prefers-color-scheme: dark) {
      pre[data-code-highlighted] { color: #e8e6e1; background: #2c2c2a; }
      pre .token.comment, pre .token.prolog, pre .token.doctype, pre .token.cdata { color: #b5b1aa; }
      pre .token.keyword, pre .token.atrule { color: #d5aff0; }
      pre .token.string, pre .token.char, pre .token.attr-value, pre .token.inserted { color: #a4d9a9; }
      pre .token.number, pre .token.boolean, pre .token.constant { color: #e9c07c; }
      pre .token.function, pre .token.class-name, pre .token.builtin { color: #9fc8ff; }
      pre .token.tag, pre .token.property, pre .token.selector, pre .token.deleted { color: #ffb4a9; }
      pre .token.operator, pre .token.entity, pre .token.url, pre .token.variable { color: #c8b8f3; }
      pre .token.regex, pre .token.important { color: #e3c395; }
    }
    @media (prefers-contrast: more) { pre .token { color: inherit; } }
    @media print {
      pre[data-code-highlighted] { color: #171614; background: #f7f6f3; }
      pre .token.comment, pre .token.prolog, pre .token.doctype, pre .token.cdata { color: #55524b; }
      pre .token.keyword, pre .token.atrule, pre .token.operator { color: #62317f; }
      pre .token.string, pre .token.char, pre .token.attr-value, pre .token.inserted { color: #20542d; }
      pre .token.number, pre .token.boolean, pre .token.constant { color: #704000; }
      pre .token.function, pre .token.class-name, pre .token.builtin { color: #1c4886; }
      pre .token.tag, pre .token.property, pre .token.selector, pre .token.deleted { color: #8b2520; }
    }
    """
}
