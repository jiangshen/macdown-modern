import CryptoKit
import Foundation
import MathCore

public enum DiagramKind: String, CaseIterable, Hashable, Sendable {
  case mermaid, dot, circo, fdp, neato, osage, twopi, sfdp, patchwork
  public var isMermaid: Bool { self == .mermaid }
  public static func fence(_ info: String) -> Self? {
    guard let name = info.split(whereSeparator: \.isWhitespace).first?.lowercased() else {
      return nil
    }
    if ["graphviz", "gv", "viz"].contains(name) { return .dot }
    return Self(rawValue: name)
  }
}

public enum DiagramPresentation: Sendable { case isolated, portable }

public enum DiagramIssue: String, Sendable {
  case invalidSource, tooLarge, timedOut, unavailableEngine, unsafeOutput, rendererWarning
}

public struct RenderedDiagram: Sendable {
  public let lightSVG: String?
  public let darkSVG: String?
  public let issue: DiagramIssue?
  public var isRendered: Bool { lightSVG != nil && darkSVG != nil }
  public var usesMath: Bool {
    lightSVG?.contains("katex") == true || darkSVG?.contains("katex") == true
  }

  static func failure(_ issue: DiagramIssue) -> Self {
    Self(lightSVG: nil, darkSVG: nil, issue: issue)
  }

  @concurrent
  public func html(position: String, key: String, presentation: DiagramPresentation = .portable)
    async throws -> String?
  {
    guard let lightSVG, let darkSVG else { return nil }
    let attributes =
      "class=\"md-diagram\" data-sourcepos=\"\(Self.escape(position))\" data-diagram-key=\"\(Self.escape(key))\""
    switch presentation {
    case .isolated:
      let style = Self.style + (usesMath ? MathStyle.layoutCSS : "")
      return
        "<div role=\"figure\" \(attributes)><template shadowrootmode=\"open\" data-snowfolio-diagram=\"true\"><style>\(style)</style><div class=\"diagram-light\">\(lightSVG)</div><div class=\"diagram-dark\">\(darkSVG)</div></template></div>"
    case .portable:
      let id = "sf-diagram-" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
      let light = try await DiagramSVG.sanitize(lightSVG, variant: id + "-light")
      let dark = try await DiagramSVG.sanitize(darkSVG, variant: id + "-dark")
      let style =
        Self.style.replacingOccurrences(of: ":host", with: "#" + id)
        .replacingOccurrences(of: ".diagram-light", with: "#" + id + " .diagram-light")
        .replacingOccurrences(of: ".diagram-dark", with: "#" + id + " .diagram-dark")
        .replacingOccurrences(of: "svg{", with: "#" + id + " svg{")
        + (usesMath ? MathStyle.layoutCSS : "")
      return
        "<div role=\"figure\" id=\"\(id)\" \(attributes)><style>\(style)</style><div class=\"diagram-light\">\(light)</div><div class=\"diagram-dark\">\(dark)</div></div>"
    }
  }

  public static func key(source: String, kind: DiagramKind) -> String {
    SHA256.hash(data: Data((kind.rawValue + "\u{0}" + source).utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  private static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
  }

  private static let style = """
    :host{display:block;contain:layout paint;overflow-x:auto;margin:1.25em 0;max-width:100%;}
    .diagram-light,.diagram-dark{max-width:100%;}
    svg{display:block;max-width:100%;height:auto;margin-inline:auto;}
    .diagram-dark{display:none;}
    @media(prefers-color-scheme:dark){.diagram-light{display:none;}.diagram-dark{display:block;}}
    @media print{.diagram-light{display:block!important;}.diagram-dark{display:none!important;}}
    """
}
