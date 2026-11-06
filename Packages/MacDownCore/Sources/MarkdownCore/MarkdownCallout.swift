import Foundation
import cmark_gfm

/// An optional GitHub-style alert. Recognition uses the native tree AND the raw
/// marker line, so escapes, entities, code and reference links stay ordinary Markdown.
public enum MarkdownCallout: String, CaseIterable, Sendable {
  case note, tip, important, warning, caution

  public var title: String {
    switch self {
    case .note: "Note"
    case .tip: "Tip"
    case .important: "Important"
    case .warning: "Warning"
    case .caution: "Caution"
    }
  }

  private var symbol: String {
    switch self {
    case .note: "ℹ︎"
    case .tip: "✦"
    case .important: "◆"
    case .warning, .caution: "⚠︎"
    }
  }

  static func recognize(_ node: UnsafeMutablePointer<cmark_node>, rawLine: String) -> Self? {
    guard cmark_node_get_type(node) == CMARK_NODE_BLOCK_QUOTE,
      let parent = cmark_node_parent(node), cmark_node_get_type(parent) == CMARK_NODE_DOCUMENT,
      let paragraph = cmark_node_first_child(node),
      cmark_node_get_type(paragraph) == CMARK_NODE_PARAGRAPH,
      let text = cmark_node_first_child(paragraph), cmark_node_get_type(text) == CMARK_NODE_TEXT,
      let literal = cmark_node_get_literal(text)
    else { return nil }
    // cmark recognizes the structural quote first. This check disambiguates literal
    // spellings that become identical text nodes after Markdown unescaping.
    let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n"))
    guard line.first == ">" else { return nil }
    let marker = line.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
    guard let kind = allCases.first(where: { marker == "[!\($0.rawValue.uppercased())]" }),
      String(cString: literal).trimmingCharacters(in: CharacterSet(charactersIn: " \t")) == marker
    else { return nil }
    if let next = cmark_node_next(text) {
      guard [CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK].contains(cmark_node_get_type(next)) else {
        return nil
      }
    }
    return kind
  }

  /// Called only AFTER the immutable source AST/outline have been captured. Only
  /// fixed enum strings and native integer positions enter the trusted HTML wrapper.
  /// Every document child still goes through cmark's safe renderer.
  func decorate(_ quote: UnsafeMutablePointer<cmark_node>) throws {
    guard let paragraph = cmark_node_first_child(quote),
      let marker = cmark_node_first_child(paragraph),
      let container = cmark_node_new(CMARK_NODE_CUSTOM_BLOCK)
    else { throw MarkdownRenderingError.allocationFailure }
    let startLine = cmark_node_get_start_line(quote)
    let startColumn = cmark_node_get_start_column(quote)
    let endLine = cmark_node_get_end_line(quote)
    let endColumn = cmark_node_get_end_column(quote)
    let opening = """
      <aside class="md-callout md-callout-\(rawValue)" data-sourcepos="\(startLine):\(startColumn)-\(endLine):\(endColumn)">
      <p class="md-callout-title"><span class="md-callout-icon" aria-hidden="true">\(symbol)</span>\(title)</p>
      """
    guard cmark_node_set_on_enter(container, opening) == 1,
      cmark_node_set_on_exit(container, "</aside>") == 1,
      cmark_node_replace(quote, container) == 1
    else {
      cmark_node_free(container)
      throw MarkdownRenderingError.invalidTreeTransformation
    }
    // Once replaced, container belongs to the document. Free the detached quote on
    // every path; moved children belong to container and are freed with the root.
    defer { cmark_node_free(quote) }
    let lineBreak = cmark_node_next(marker)
    cmark_node_unlink(marker)
    cmark_node_free(marker)
    if let lineBreak {
      cmark_node_unlink(lineBreak)
      cmark_node_free(lineBreak)
    }
    if cmark_node_first_child(paragraph) == nil {
      cmark_node_unlink(paragraph)
      cmark_node_free(paragraph)
    }
    while let child = cmark_node_first_child(quote) {
      guard cmark_node_append_child(container, child) == 1 else {
        throw MarkdownRenderingError.invalidTreeTransformation
      }
    }
  }
}
