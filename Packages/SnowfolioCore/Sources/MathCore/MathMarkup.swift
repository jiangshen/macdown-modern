import Foundation

/// Strict output boundary for the pinned compatibility engine. No active content,
/// external resources, arbitrary CSS or unbounded geometry enters the preview.
enum MathMarkup {
  enum Failure: Error { case unsafe, tooLarge }
  private static let svgURI = "http://www.w3.org/2000/svg"
  private static let mathURI = "http://www.w3.org/1998/Math/MathML"
  private static let numbers = try? NSRegularExpression(
    pattern: #"[+-]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][+-]?\d+)?"#)
  private static let functions = try? NSRegularExpression(pattern: #"([a-zA-Z_-]+)\s*\("#)

  static func html(
    svg: String, mathml: String, source: String, display: Bool, namespace: String
  ) throws -> String {
    let math = try validated(mathml, svg: false, namespace: namespace)
    let content = XMLElement(name: "mrow")
    for child in math.children ?? [] {
      child.detach()
      content.addChild(child)
    }
    let empty =
      content.elements(forName: "mrow").allSatisfy { ($0.children ?? []).isEmpty }
      && (content.children ?? []).allSatisfy {
        ($0 as? XMLElement)?.localName == "mrow"
          || $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
      }
    let semantics = XMLElement(name: "semantics")
    semantics.addChild(content)
    let annotation = XMLElement(name: "annotation", stringValue: source)
    guard
      let encoding = XMLNode.attribute(withName: "encoding", stringValue: "application/x-tex")
        as? XMLNode
    else { throw Failure.unsafe }
    annotation.addAttribute(encoding)
    semantics.addChild(annotation)
    math.addChild(semantics)
    let visual: String
    if empty {
      visual = ""
    } else {
      visual = try validated(svg, svg: true, namespace: namespace).xmlString(options: [
        .nodeExpandEmptyElement
      ])
    }
    let result =
      "<span class=\"md-mathjax\(empty ? " md-mathjax-empty" : "")\">"
      + "<span class=\"md-mathjax-mathml\">" + math.xmlString(options: [.nodeExpandEmptyElement])
      + "</span>"
      + "<span class=\"md-mathjax-visual\" aria-hidden=\"true\">" + visual + "</span></span>"
    guard result.utf8.count <= 1_048_576 else { throw Failure.tooLarge }
    return result
  }

  private static func validated(_ source: String, svg: Bool, namespace: String) throws -> XMLElement
  {
    try Task.checkCancellation()
    guard source.utf8.count <= 1_048_576 else { throw Failure.tooLarge }
    guard !source.localizedCaseInsensitiveContains("<!DOCTYPE"),
      !source.localizedCaseInsensitiveContains("<!ENTITY"),
      namespace.utf8.allSatisfy({ (48...57).contains($0) || (97...122).contains($0) || $0 == 45 })
    else { throw Failure.unsafe }
    let document = try XMLDocument(xmlString: source, options: [.nodeLoadExternalEntitiesNever])
    guard let root = document.rootElement(), root.localName == (svg ? "svg" : "math"),
      root.uri == (svg ? svgURI : mathURI)
    else { throw Failure.unsafe }
    let allowed: Set<String> =
      svg
      ? ["svg", "g", "defs", "path", "rect", "line", "text", "tspan", "a", "title", "desc", "use"]
      : [
        "math", "mrow", "mi", "mn", "mo", "mtext", "mfrac", "msup", "msub", "msubsup", "msqrt",
        "mroot", "mspace", "mtable", "mtr", "mlabeledtr", "mtd", "mover", "munder", "munderover",
        "menclose", "mpadded", "mphantom", "mstyle", "none", "mprescripts", "mmultiscripts",
        "maction",
      ]
    let attributes: Set<String> = [
      "id", "href", "class", "pointer-events", "style", "fill", "stroke", "stroke-width",
      "stroke-dasharray", "transform", "d",
      "viewbox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "dx", "dy", "role",
      "focusable", "aria-hidden",
      "font-size", "font-family", "font-style", "font-weight", "text-anchor", "preserveaspectratio",
      "rowspan", "columnspan", "rowalign", "columnalign", "equalrows", "equalcolumns",
      "columnspacing", "rowspacing", "framespacing", "frame", "linethickness", "scriptlevel",
      "mathsize", "displaystyle", "mathvariant", "mathcolor", "mathbackground", "stretchy", "fence",
      "form",
      "lspace", "rspace", "accent", "accentunder", "minsize", "maxsize", "separator",
      "movablelimits", "symmetric", "subscriptshift", "superscriptshift", "notation", "voffset",
      "depth", "align", "indentshift", "side", "minlabelspacing", "display", "mode", "actiontype",
      "selection",
    ]
    var queue: [(XMLNode, Int)] = [(root, 0)]
    var cursor = 0
    var ids: Set<String> = []
    while cursor < queue.count {
      if cursor.isMultiple(of: 128) { try Task.checkCancellation() }
      guard cursor < 20_000 else { throw Failure.tooLarge }
      let (node, depth) = queue[cursor]
      cursor += 1
      guard depth < 128 else { throw Failure.tooLarge }
      guard node.kind != .processingInstruction && node.kind != .DTDKind else {
        throw Failure.unsafe
      }
      if let element = node as? XMLElement {
        guard allowed.contains(element.localName ?? ""),
          element.uri == nil || element.uri == (svg ? svgURI : mathURI)
        else { throw Failure.unsafe }
        for declaration in element.namespaces ?? [] {
          guard
            [svgURI, mathURI, "http://www.w3.org/1999/xlink"].contains(
              declaration.stringValue ?? "")
          else { throw Failure.unsafe }
        }
        for attribute in element.attributes ?? [] {
          let key = (attribute.localName ?? "").lowercased()
          let value = attribute.stringValue ?? ""
          guard attributes.contains(key) || key.hasPrefix("data-") else { throw Failure.unsafe }
          if key == "id" {
            guard ids.insert(value).inserted else { throw Failure.unsafe }
            if svg {
              attribute.stringValue = identifier(value, namespace: namespace)
            } else {
              attribute.detach()
            }
          } else if key == "href" {
            guard value.hasPrefix("#"),
              let decoded = String(value.dropFirst()).removingPercentEncoding
            else { throw Failure.unsafe }
            attribute.stringValue = "#" + identifier(decoded, namespace: namespace)
          } else if key == "style" {
            try validateStyle(value)
          } else if ["fill", "stroke", "mathcolor", "mathbackground"].contains(key) {
            try validateValue(value)
          } else if [
            "d", "transform", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "dx", "dy",
            "viewbox", "stroke-width", "indentshift",
          ].contains(key) {
            try validateNumbers(value)
          }
        }
      }
      queue.append(contentsOf: (node.children ?? []).map { ($0, depth + 1) })
    }
    if svg, let raw = root.attribute(forName: "viewBox")?.stringValue {
      let values = raw.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap {
        Double($0)
      }
      guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0,
        values[2] <= 100_000, values[3] <= 100_000
      else { throw Failure.tooLarge }
    }
    root.detach()
    return root
  }

  private static func identifier(_ value: String, namespace: String) -> String {
    namespace + "-" + value.utf8.map { String(format: "%02x", $0) }.joined()
  }

  private static func validateStyle(_ value: String) throws {
    let allowed: Set<String> = [
      "vertical-align", "font-size", "width", "min-width", "height", "margin", "margin-left",
      "margin-right", "margin-top", "margin-bottom", "color", "background-color", "border",
      "border-top", "border-bottom", "border-left", "border-right", "font-family", "font-weight",
      "font-style",
    ]
    for declaration in value.split(separator: ";") {
      let parts = declaration.split(separator: ":", maxSplits: 1)
      guard parts.count == 2,
        allowed.contains(parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
      else { throw Failure.unsafe }
      try validateValue(String(parts[1]))
    }
  }

  private static func validateValue(_ value: String) throws {
    guard !value.contains("/*"),
      !value.unicodeScalars.contains(where: { $0.value < 32 && !$0.properties.isWhitespace }),
      value.rangeOfCharacter(from: CharacterSet(charactersIn: "\\@{}<>\"'")) == nil,
      let functions
    else { throw Failure.unsafe }
    let text = value as NSString
    for match in functions.matches(in: value, range: NSRange(location: 0, length: text.length)) {
      guard
        ["rgb", "rgba", "hsl", "hsla"].contains(
          text.substring(with: match.range(at: 1)).lowercased())
      else { throw Failure.unsafe }
    }
  }

  private static func validateNumbers(_ value: String) throws {
    guard let numbers else { throw Failure.unsafe }
    let lowered = value.lowercased()
    guard !lowered.contains("nan"), !lowered.contains("inf") else { throw Failure.tooLarge }
    let text = value as NSString
    for match in numbers.matches(in: value, range: NSRange(location: 0, length: text.length)) {
      guard let number = Double(text.substring(with: match.range)), number.isFinite,
        abs(number) <= 10_000_000
      else { throw Failure.tooLarge }
    }
  }
}
