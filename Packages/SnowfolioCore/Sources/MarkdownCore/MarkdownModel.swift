import DiagramCore
import Foundation

/// CommonMark positions use one-based lines and UTF-8 byte columns.
public struct MarkdownSourcePosition: Equatable, Sendable {
  public let line: Int
  public let column: Int
}

public struct MarkdownSourceRange: Equatable, Sendable {
  public let start: MarkdownSourcePosition
  /// Inclusive end, matching cmark's `data-sourcepos` convention.
  public let end: MarkdownSourcePosition
}

public enum MarkdownNodeKind: Equatable, Sendable {
  case document, frontMatter, heading, paragraph, text, codeBlock, inlineCode, link, image
  case highlight, superscript
  case emphasis, strong, strikethrough, list, listItem, blockquote, html
  case table, tableRow, tableCell, thematicBreak, softBreak, lineBreak
  case math(display: Bool)
  case diagram(DiagramKind)
  case other(String)

  init(nativeName: String) {
    switch nativeName {
    case "document": self = .document
    case "heading": self = .heading
    case "paragraph": self = .paragraph
    case "text": self = .text
    case "code_block": self = .codeBlock
    case "code": self = .inlineCode
    case "link": self = .link
    case "image": self = .image
    case "emph": self = .emphasis
    case "strong": self = .strong
    case "strikethrough": self = .strikethrough
    case "list": self = .list
    case "item", "tasklist": self = .listItem
    case "block_quote": self = .blockquote
    case "html_block", "html_inline": self = .html
    case "table": self = .table
    case "table_header", "table_row": self = .tableRow
    case "table_cell": self = .tableCell
    case "thematic_break": self = .thematicBreak
    case "softbreak": self = .softBreak
    case "linebreak": self = .lineBreak
    default: self = .other(nativeName)
    }
  }
}

/// Flat preorder AST avoids recursive traversal and is safe to pass across actors.
/// Parent identifiers refer to preceding entries in the same immutable node array.
public struct MarkdownNode: Identifiable, Equatable, Sendable {
  public let id: Int
  public let parentID: Int?
  public let kind: MarkdownNodeKind
  public let range: MarkdownSourceRange?
  public let literal: String?
  public let destination: String?
  public let headingLevel: Int?
  /// Optional presentation for a top-level quote; original source AST remains intact.
  public let callout: MarkdownCallout?
  public let calloutEmoji: String?
}

public struct MarkdownHeading: Identifiable, Equatable, Sendable {
  public let id: Int
  public let title: String
  public let level: Int
  public let sourceLine: Int
  public let utf16Offset: Int
  public let anchor: String
}

public struct MarkdownRenderingOptions: Equatable, Hashable, Sendable {
  public var tables = true
  public var strikethrough = true
  public var taskLists = true
  public var autolinks = true
  public var footnotes = true
  public var highlight = false
  public var superscript = false
  public var smartPunctuation = false
  public var hardLineBreaks = false
  public var rawHTML = false
  public var alerts = true
  public var codeHighlighting = true
  public var frontMatter = true
  public var tableOfContents = true
  public var math = false
  public var inlineDollarMath = false
  public var mermaid = false
  public var graphviz = false

  public init() {}
}

public struct RenderedMarkdown: Sendable {
  public let html: String
  public let nodes: [MarkdownNode]
  public let headings: [MarkdownHeading]
  public let syntax: MarkdownSyntax?
  public let highlightedCodeBlocks: Int
  public let mathExpressions: Int
  public let diagrams: Int
  public let diagramUsesMath: Bool
  public let frontMatter: MarkdownFrontMatter?
  public let notices: [MarkdownRenderNotice]
}

public enum MarkdownRenderNotice: String, Sendable {
  case invalidFrontMatter, complexFrontMatter, unsupportedMath, unsupportedDiagram,
    complexInlineFormatting
}

public enum MarkdownRenderingError: Error, Sendable {
  case allocationFailure
  case unavailableExtension(String)
  case invalidTreeTransformation
}
