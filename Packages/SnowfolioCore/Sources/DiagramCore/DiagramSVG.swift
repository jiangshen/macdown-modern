import Foundation

public enum DiagramSVGError: Error, Sendable { case invalid, tooLarge, unsafe }

/// Engine output is data. Validate it before it can enter a preview or export.
/// IDs and stylesheet references are prefixed for appearance and export instances.
public enum DiagramSVG {
  @concurrent
  public static func sanitize(_ svg: String, variant: String) async throws -> String {
    try sanitized(svg, variant: variant)
  }

  static func sanitized(_ svg: String, variant: String) throws -> String {
    try Task.checkCancellation()
    guard svg.utf8.count <= 2_097_152 else { throw DiagramSVGError.tooLarge }
    guard !variant.isEmpty,
      variant.utf8.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
          || $0 == 95
      })
    else { throw DiagramSVGError.invalid }
    var source = svg
    // Graphviz emits a standard external SVG DTD; it is unnecessary in output.
    // Never parse an internal subset or resolve any entity supplied by a diagram.
    if let start = source.range(of: "<!DOCTYPE", options: .caseInsensitive) {
      guard let end = source[start.upperBound...].firstIndex(of: ">"),
        !source[start.lowerBound...end].contains("[")
      else { throw DiagramSVGError.unsafe }
      source.removeSubrange(start.lowerBound...end)
    }
    guard !source.localizedCaseInsensitiveContains("<!ENTITY"),
      !source.localizedCaseInsensitiveContains("<!DOCTYPE")
    else { throw DiagramSVGError.unsafe }
    let document: XMLDocument
    do {
      document = try XMLDocument(xmlString: source, options: [.nodeLoadExternalEntitiesNever])
    } catch { throw DiagramSVGError.invalid }
    guard let root = document.rootElement(), root.localName == "svg",
      root.uri == "http://www.w3.org/2000/svg"
    else { throw DiagramSVGError.invalid }
    let allowed: Set<String> = [
      "svg", "g", "defs", "style", "title", "desc", "path", "rect", "circle", "ellipse", "line",
      "polyline", "polygon", "text", "tspan", "textpath", "marker", "clippath", "mask", "pattern",
      "lineargradient", "radialgradient", "stop", "use", "symbol", "filter", "fedropshadow",
      "fegaussianblur", "feoffset", "femerge", "femergenode", "feblend", "fecolormatrix",
      "fecomponenttransfer", "fefuncr", "fefuncg", "fefuncb", "fefunca", "fecomposite", "feflood",
      "a", "foreignobject", "div", "span", "p", "br", "strong", "b", "em", "i", "code", "sub",
      "sup",
      "ul", "ol", "li", "hr", "image",
      "math", "semantics", "annotation", "mrow", "mi", "mn", "mo", "mtext", "mfrac", "msup",
      "msub", "msubsup", "msqrt", "mroot", "mspace", "mtable", "mtr", "mtd", "mover", "munder",
      "munderover", "menclose", "mpadded", "mphantom", "mstyle", "none", "mprescripts",
      "mmultiscripts",
    ]
    var elements: [XMLElement] = []
    var queue: [(XMLNode, Int)] = [(root, 0)]
    var cursor = 0
    var identifiers: Set<String> = []
    var animationNames: Set<String> = []
    let keyframes = try NSRegularExpression(
      pattern: "@(?:-webkit-)?keyframes\\s+([A-Za-z_][A-Za-z_0-9-]*)", options: [.caseInsensitive])
    while cursor < queue.count {
      if cursor.isMultiple(of: 256) { try Task.checkCancellation() }
      guard cursor < 20_000 else { throw DiagramSVGError.tooLarge }
      let (node, depth) = queue[cursor]
      cursor += 1
      guard depth < 128 else { throw DiagramSVGError.tooLarge }
      if node.kind == .processingInstruction || node.kind == .DTDKind {
        throw DiagramSVGError.unsafe
      }
      if let element = node as? XMLElement {
        let name = (element.localName ?? "").lowercased()
        guard allowed.contains(name) else { throw DiagramSVGError.unsafe }
        if let uri = element.uri,
          ![
            "http://www.w3.org/2000/svg", "http://www.w3.org/1999/xhtml",
            "http://www.w3.org/1998/Math/MathML",
          ].contains(uri)
        {
          throw DiagramSVGError.unsafe
        }
        elements.append(element)
        if let id = element.attribute(forName: "id")?.stringValue {
          guard !id.isEmpty,
            id.unicodeScalars.allSatisfy({
              CharacterSet.alphanumerics.contains($0) || "_-.:".unicodeScalars.contains($0)
            }), identifiers.insert(id).inserted
          else { throw DiagramSVGError.unsafe }
        }
        if name == "style" {
          let css = element.stringValue ?? ""
          try validateCSS(css)
          let text = css as NSString
          for match in keyframes.matches(in: css, range: NSRange(location: 0, length: text.length))
          {
            animationNames.insert(text.substring(with: match.range(at: 1)))
          }
        }
        for attribute in element.attributes ?? [] {
          let key = (attribute.localName ?? attribute.name ?? "").lowercased()
          let value = attribute.stringValue ?? ""
          guard !key.hasPrefix("on"),
            !["src", "srcset", "action", "formaction", "base"].contains(key)
          else { throw DiagramSVGError.unsafe }
          if key == "href" {
            if value.hasPrefix("#") { continue }
            if name == "a", let url = URL(string: value),
              ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
            {
              continue
            }
            if name == "image",
              [
                "data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,",
                "data:image/gif;base64,",
              ].contains(where: value.hasPrefix)
            {
              continue
            }
            throw DiagramSVGError.unsafe
          }
          if key == "style"
            || [
              "fill", "stroke", "filter", "clip-path", "mask", "marker-start", "marker-mid",
              "marker-end",
            ].contains(key)
          {
            try validateCSS(value)
          }
        }
        if name == "a",
          let target = XMLNode.attribute(withName: "target", stringValue: "_self") as? XMLNode
        {
          element.removeAttribute(forName: "target")
          element.addAttribute(target)
        }
      }
      queue.append(contentsOf: (node.children ?? []).map { ($0, depth + 1) })
    }
    if let raw = root.attribute(forName: "viewBox")?.stringValue {
      let values = raw.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap {
        Double($0)
      }
      guard values.count == 4, values.allSatisfy(\.isFinite), values[2] > 0, values[3] > 0,
        values[2] <= 100_000, values[3] <= 100_000
      else { throw DiagramSVGError.tooLarge }
    }
    // Two appearance variants share a shadow root. Prefix IDs/references within
    // each SVG; portable markup applies an additional unique instance prefix.
    let idTokens = try NSRegularExpression(pattern: "#([\\p{L}_][\\p{L}\\p{N}_-]*)")
    for (index, element) in elements.enumerated() {
      if index.isMultiple(of: 128) { try Task.checkCancellation() }
      for attribute in element.attributes ?? [] {
        guard let key = attribute.localName?.lowercased(), let value = attribute.stringValue else {
          continue
        }
        if key == "id" {
          attribute.stringValue = variant + "-" + value
        } else if key == "href", value.hasPrefix("#"),
          identifiers.contains(String(value.dropFirst()))
        {
          attribute.stringValue = "#" + variant + "-" + value.dropFirst()
        } else if key == "aria-labelledby" || key == "aria-describedby" {
          attribute.stringValue = value.split(separator: " ").map {
            identifiers.contains(String($0)) ? variant + "-" + $0 : String($0)
          }.joined(separator: " ")
        } else {
          attribute.stringValue = try prefixAnimations(
            prefixURLs(value, ids: identifiers, variant: variant), names: animationNames,
            variant: variant)
        }
      }
      if element.localName?.lowercased() == "style" {
        let css = try prefixAnimations(
          prefixURLs(element.stringValue ?? "", ids: identifiers, variant: variant),
          names: animationNames, variant: variant)
        let regex = try NSRegularExpression(pattern: "[^{}]+(?=\\{)")
        let text = css as NSString
        var rewritten = css
        for match in regex.matches(in: css, range: NSRange(location: 0, length: text.length))
          .reversed()
        {
          var selector = text.substring(with: match.range)
          let selectorText = selector as NSString
          for idMatch in idTokens.matches(
            in: selector, range: NSRange(location: 0, length: selectorText.length)
          ).reversed() {
            let id = selectorText.substring(with: idMatch.range(at: 1))
            if identifiers.contains(id), let range = Range(idMatch.range, in: selector) {
              selector.replaceSubrange(range, with: "#" + variant + "-" + id)
            }
          }
          let range = Range(match.range, in: rewritten)
          if let range { rewritten.replaceSubrange(range, with: selector) }
        }
        element.stringValue = rewritten
      }
    }
    return root.xmlString(options: [.nodeExpandEmptyElement])
  }

  private static func validateCSS(_ css: String) throws {
    guard !css.contains("\\") else { throw DiagramSVGError.unsafe }
    let comments = try NSRegularExpression(
      pattern: "/\\*.*?\\*/", options: [.dotMatchesLineSeparators])
    let plain = comments.stringByReplacingMatches(
      in: css,
      range: NSRange(location: 0, length: (css as NSString).length), withTemplate: "")
    let lowered = plain.lowercased()
    guard
      !["@import", "@page", "@font-face", "@property", "@namespace", "@counter-style"].contains(
        where: lowered.contains), !lowered.contains("expression("),
      !lowered.contains("javascript:"), !lowered.contains("-moz-binding")
    else { throw DiagramSVGError.unsafe }
    // CSS image-set/image/src may fetch quoted URLs without url(...).
    let resourceFunctions = try NSRegularExpression(
      pattern: "(?:image-set|image|src)\\s*\\(", options: [.caseInsensitive])
    guard
      resourceFunctions.firstMatch(
        in: plain,
        range: NSRange(location: 0, length: (plain as NSString).length)) == nil
    else { throw DiagramSVGError.unsafe }
    let urls = try NSRegularExpression(pattern: "url\\s*\\(([^)]*)\\)", options: [.caseInsensitive])
    let text = plain as NSString
    for match in urls.matches(in: plain, range: NSRange(location: 0, length: text.length)) {
      let value = text.substring(with: match.range(at: 1)).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
      guard value.hasPrefix("#"), !value.contains("(") else { throw DiagramSVGError.unsafe }
    }
  }

  private static func prefixAnimations(_ css: String, names: Set<String>, variant: String) throws
    -> String
  {
    guard !names.isEmpty else { return css }
    let definitions = try NSRegularExpression(
      pattern: "(@(?:-webkit-)?keyframes\\s+)([A-Za-z_][A-Za-z_0-9-]*)", options: [.caseInsensitive]
    )
    var result = css
    let text = css as NSString
    for match in definitions.matches(in: css, range: NSRange(location: 0, length: text.length))
      .reversed()
    {
      let name = text.substring(with: match.range(at: 2))
      if names.contains(name), let range = Range(match.range(at: 2), in: result) {
        result.replaceSubrange(range, with: variant + "-" + name)
      }
    }
    let references = try NSRegularExpression(
      pattern: "animation-name\\s*:\\s*([^;}]+)", options: [.caseInsensitive])
    let updated = result as NSString
    for match in references.matches(in: result, range: NSRange(location: 0, length: updated.length))
      .reversed()
    {
      let value = updated.substring(with: match.range(at: 1))
      let replaced = value.split(separator: ",").map { part in
        let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
        return names.contains(name) ? variant + "-" + name : name
      }.joined(separator: ",")
      if let range = Range(match.range(at: 1), in: result) {
        result.replaceSubrange(range, with: replaced)
      }
    }
    return result
  }

  private static func prefixURLs(_ value: String, ids: Set<String>, variant: String) throws
    -> String
  {
    guard value.localizedCaseInsensitiveContains("url") else { return value }
    let expression = try NSRegularExpression(
      pattern: "url\\(\\s*['\"]?#([^'\"\\s()]+)['\"]?\\s*\\)", options: [.caseInsensitive])
    let text = value as NSString
    var result = value
    for match in expression.matches(in: value, range: NSRange(location: 0, length: text.length))
      .reversed()
    {
      let id = text.substring(with: match.range(at: 1))
      if ids.contains(id), let range = Range(match.range, in: result) {
        result.replaceSubrange(range, with: "url(#" + variant + "-" + id + ")")
      }
    }
    return result
  }
}
