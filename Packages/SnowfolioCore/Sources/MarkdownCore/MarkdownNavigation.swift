import Foundation
import cmark_gfm

struct HeadingAnchors {
  private var used: Set<String> = ["preview-content", "document-style", "code-style"]
  private var suffixes: [String: Int] = [:]

  mutating func next(for title: String) -> String {
    var base = ""
    var pendingDash = false
    for scalar in title.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar)
        || CharacterSet.nonBaseCharacters.contains(scalar) || scalar == "_" || scalar == "-"
      {
        if pendingDash, !base.isEmpty { base += "-" }
        base.unicodeScalars.append(scalar)
        pendingDash = false
      } else if CharacterSet.whitespacesAndNewlines.contains(scalar) {
        pendingDash = true
      }
      if base.unicodeScalars.count >= 80 { break }
    }
    if base.isEmpty { base = "section" }
    // Reserve the legacy link namespace, independently of the number of headings.
    if base.hasPrefix("toc_"), Int(base.dropFirst(4)) != nil { base = "section-" + base }
    if used.insert(base).inserted { return base }
    var suffix = suffixes[base] ?? 1
    while !used.insert(base + "-" + String(suffix)).inserted { suffix += 1 }
    suffixes[base] = suffix + 1
    return base + "-" + String(suffix)
  }
}

enum MarkdownNavigation {
  static func decorateHeading(
    _ node: UnsafeMutablePointer<cmark_node>, heading: MarkdownHeading, index: Int
  ) throws {
    let level = heading.level
    let position =
      "\(cmark_node_get_start_line(node)):\(cmark_node_get_start_column(node))-\(cmark_node_get_end_line(node)):\(cmark_node_get_end_column(node))"
    let opening =
      "<h\(level) id=\"\(MarkdownFrontMatter.escape(heading.anchor))\" data-sourcepos=\"\(position)\"><span id=\"toc_\(index)\" class=\"md-legacy-anchor\" aria-hidden=\"true\"></span>"
    guard let container = cmark_node_new(CMARK_NODE_CUSTOM_BLOCK) else {
      throw MarkdownRenderingError.allocationFailure
    }
    guard cmark_node_set_on_enter(container, opening) == 1,
      cmark_node_set_on_exit(container, "</h\(level)>") == 1,
      cmark_node_replace(node, container) == 1
    else {
      cmark_node_free(container)
      throw MarkdownRenderingError.invalidTreeTransformation
    }
    defer { cmark_node_free(node) }
    while let child = cmark_node_first_child(node) {
      guard cmark_node_append_child(container, child) == 1 else {
        throw MarkdownRenderingError.invalidTreeTransformation
      }
    }
  }

  static func isTableOfContents(
    _ node: UnsafeMutablePointer<cmark_node>, source: NSString, lineStarts: [Int]
  ) -> Bool {
    guard let text = cmark_node_first_child(node), cmark_node_get_type(text) == CMARK_NODE_TEXT,
      cmark_node_next(text) == nil, let literal = cmark_node_get_literal(text),
      String(cString: literal).trimmingCharacters(in: .whitespacesAndNewlines) == "[TOC]"
    else { return false }
    let line = Int(cmark_node_get_start_line(node))
    guard line > 0, line <= lineStarts.count, cmark_node_get_end_line(node) == line else {
      return false
    }
    let lineStart = lineStarts[line - 1]
    let lineEnd = line < lineStarts.count ? lineStarts[line] : source.length
    let bytes = Array(
      source.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart)).utf8)
    let start = Int(cmark_node_get_start_column(node)) - 1
    let end = Int(cmark_node_get_end_column(node))
    guard start >= 0, end <= bytes.count, end >= start else { return false }
    return String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(in: .whitespaces)
      == "[TOC]"
  }

  static func tableOfContents(_ headings: [MarkdownHeading]) throws -> String {
    struct Item {
      let heading: MarkdownHeading
      var children: [Int] = []
    }
    var items: [Item] = []
    var roots: [Int] = []
    var parents: [Int] = []
    for heading in headings {
      try Task.checkCancellation()
      while let parent = parents.last, items[parent].heading.level >= heading.level {
        parents.removeLast()
      }
      let index = items.count
      if let parent = parents.last {
        items[parent].children.append(index)
      } else {
        roots.append(index)
      }
      items.append(Item(heading: heading))
      parents.append(index)
    }
    func list(_ ids: [Int], top: Bool) throws -> String {
      var html = top ? "<ul class=\"toc\">" : "<ul>"
      for id in ids {
        try Task.checkCancellation()
        let item = items[id]
        let heading = item.heading
        let target =
          heading.anchor.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
          ?? heading.anchor
        html +=
          "<li><a href=\"#\(MarkdownFrontMatter.escape(target))\">\(MarkdownFrontMatter.escape(heading.title.isEmpty ? "Untitled heading" : heading.title))</a>"
        if !item.children.isEmpty { html += try list(item.children, top: false) }
        html += "</li>"
      }
      return html + "</ul>"
    }
    return "<nav class=\"md-toc\" aria-label=\"Table of contents\">" + (try list(roots, top: true))
      + "</nav>"
  }

  static func decorateTOC(_ node: UnsafeMutablePointer<cmark_node>, html: String) throws {
    guard let container = cmark_node_new(CMARK_NODE_CUSTOM_BLOCK) else {
      throw MarkdownRenderingError.allocationFailure
    }
    guard
      cmark_node_set_on_enter(
        container,
        "<div class=\"md-toc-container\" data-sourcepos=\"\(cmark_node_get_start_line(node)):\(cmark_node_get_start_column(node))-\(cmark_node_get_end_line(node)):\(cmark_node_get_end_column(node))\">"
          + html) == 1,
      cmark_node_set_on_exit(container, "</div>") == 1,
      cmark_node_replace(node, container) == 1
    else {
      cmark_node_free(container)
      throw MarkdownRenderingError.invalidTreeTransformation
    }
    cmark_node_free(node)
  }
}
