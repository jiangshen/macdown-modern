/// Shared, portable document presentation for preview, HTML, PDF and printing.
/// All CSS inputs are bounded values or closed enums; document text is never CSS.
public struct DocumentStyle: Hashable, Sendable {
  public enum Font: String, CaseIterable, Sendable {
    case standard, serif, monospaced

    var family: String {
      switch self {
      case .standard: "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
      case .serif: "ui-serif, Georgia, 'Times New Roman', serif"
      case .monospaced: "ui-monospace, SFMono-Regular, Menlo, monospace"
      }
    }
  }

  public var font: Font
  private var storedTextSize: Double
  public var textSize: Double {
    get { storedTextSize }
    set { storedTextSize = newValue.isFinite ? min(28, max(12, newValue)) : 16 }
  }
  public var fullWidth: Bool

  public init(font: Font = .standard, textSize: Double = 16, fullWidth: Bool = false) {
    self.font = font
    self.storedTextSize = textSize.isFinite ? min(28, max(12, textSize)) : 16
    self.fullWidth = fullWidth
  }

  public var css: String {
    """
    :root {
      color-scheme: light dark;
      --paper: #ffffff; --ink: #37352f; --muted: #68655f;
      --border: #deddd9; --surface: #f7f6f3; --inline-code: #a4423b;
      --document-font: \(font.family); --document-size: \(textSize)px;
      --document-width: 708px;
    }
    * { box-sizing: border-box; }
    html { background: var(--paper); }
    body {
      margin: 0; color: var(--ink); background: var(--paper);
      font-family: var(--document-font); font-size: var(--document-size);
      line-height: 1.6; overflow-wrap: anywhere; -webkit-text-size-adjust: 100%;
    }
    main {
      max-width: calc(var(--document-width) + 96px); margin-inline: auto;
      padding: 48px 48px 100px;
    }
    \(fullWidth ? "main { max-width: none; }" : "")
    main > :first-child { margin-top: 0; }
    p { margin: .5em 0; }
    h1,h2,h3,h4,h5,h6 {
      color: var(--ink); font-weight: 650; line-height: 1.3;
      letter-spacing: -.025em; margin: 1.4em 0 .3em; scroll-margin-top: 28px;
    }
    h1 { font-size: 2em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; }
    h4 { font-size: 1.125em; } h5,h6 { font-size: 1em; }
    strong { font-weight: 650; }
    a { color: inherit; text-decoration-color: var(--muted); text-underline-offset: .18em; }
    a:hover { text-decoration-color: currentColor; }
    a:focus-visible { outline: 2px solid currentColor; outline-offset: 3px; border-radius: 2px; }
    ul,ol { padding-inline-start: 1.65em; margin: .4em 0; }
    li { padding-inline-start: .15em; margin: .2em 0; }
    li > p { margin: .25em 0; } li > ul,li > ol { margin-block: .2em; }
    li:has(> input[type=checkbox]) { list-style: none; }
    input[type=checkbox] {
      accent-color: #287eaa; width: 1em; height: 1em; margin: 0 .5em 0 -1.45em;
      vertical-align: -.1em; opacity: 1;
    }
    blockquote {
      margin: 1em 0; border-inline-start: 3px solid var(--ink);
      padding: .1em 0 .1em 1em;
    }
    blockquote > :first-child { margin-top: 0; } blockquote > :last-child { margin-bottom: 0; }
    pre,code,kbd,samp { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    code { font-size: .875em; color: var(--inline-code); background: var(--surface); padding: .16em .35em; border-radius: 3px; }
    pre { font-size: .875em; line-height: 1.55; background: var(--surface); border-radius: 5px; padding: 24px; overflow-x: auto; margin: 1em 0; }
    pre code { font-size: inherit; color: inherit; background: transparent; padding: 0; white-space: pre; }
    img,video { max-width: 100%; height: auto; }
    table { display: block; max-width: 100%; overflow-x: auto; border-collapse: collapse; margin: 1em 0; font-size: .9375em; }
    th,td { border: 1px solid var(--border); padding: .5em .8em; vertical-align: top; min-width: 5em; }
    th { font-weight: 600; background: var(--surface); }
    hr { border: 0; border-top: 1px solid var(--border); margin: 2em 0; }
    .footnotes { font-size: .875em; margin-top: 2.5em; }
    .footnotes a { color: var(--muted); }
    @media (max-width: 600px) { main { padding: 28px 24px 64px; } pre { padding: 16px; } }
    @media (prefers-color-scheme: dark) {
      :root { --paper: #191919; --ink: #e6e4df; --muted: #aeaaa4; --border: #44433f; --surface: #252525; --inline-code: #f09b91; }
    }
    @media (prefers-contrast: more) {
      :root { --ink: #171614; --muted: #44413b; --border: #77736c; --inline-code: #8b2520; }
      @media (prefers-color-scheme: dark) { :root { --ink: #ffffff; --muted: #dfdcd6; --border: #aaa69e; --inline-code: #ffbdb5; } }
    }
    @media print {
      :root { color-scheme: light; --paper: #ffffff; --ink: #171614; --muted: #44413b; --border: #b8b5ae; --surface: #f7f6f3; --inline-code: #8b2520; }
      main { max-width: none; padding: 0; }
      pre,pre code { white-space: pre-wrap; overflow-wrap: anywhere; }
      h1,h2,h3,h4,h5,h6 { break-after: avoid; } tr,img { break-inside: avoid; }
      table { display: table; width: 100%; } thead { display: table-header-group; }
    }
    """
  }
}
