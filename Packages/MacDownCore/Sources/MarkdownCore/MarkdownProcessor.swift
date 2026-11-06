import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Actor confinement keeps native parser pointers out of UI state and Sendable values.
/// Each request parses once; its native tree supplies both HTML and the Swift AST.
public actor MarkdownProcessor {
  private static let registeredExtensions: Void = {
    cmark_gfm_core_extensions_ensure_registered()
  }()

  public init() {}

  public func render(
    _ source: String, options: MarkdownRenderingOptions = .init(),
    transformDestination: (@Sendable (MarkdownNodeKind, String) throws -> String)? = nil
  ) throws
    -> RenderedMarkdown
  {
    try Task.checkCancellation()
    _ = Self.registeredExtensions
    var flags = CMARK_OPT_SOURCEPOS | CMARK_OPT_VALIDATE_UTF8
    if options.footnotes { flags |= CMARK_OPT_FOOTNOTES }
    if options.smartPunctuation { flags |= CMARK_OPT_SMART }
    if options.hardLineBreaks { flags |= CMARK_OPT_HARDBREAKS }
    if options.rawHTML { flags |= CMARK_OPT_UNSAFE }
    guard let parser = cmark_parser_new(flags) else {
      throw MarkdownRenderingError.allocationFailure
    }
    defer { cmark_parser_free(parser) }
    let extensions = [
      ("table", options.tables), ("strikethrough", options.strikethrough),
      ("tasklist", options.taskLists), ("autolink", options.autolinks), ("tagfilter", true),
    ]
    for (name, enabled) in extensions where enabled {
      guard let ext = cmark_find_syntax_extension(name) else {
        throw MarkdownRenderingError.unavailableExtension(name)
      }
      cmark_parser_attach_syntax_extension(parser, ext)
    }
    try source.utf8CString.withUnsafeBufferPointer { bytes in
      guard let base = bytes.baseAddress else { return }
      let length = bytes.count - 1
      for offset in stride(from: 0, to: length, by: 65_536) {
        try Task.checkCancellation()
        cmark_parser_feed(parser, base.advanced(by: offset), min(65_536, length - offset))
      }
    }
    guard let root = cmark_parser_finish(parser) else {
      throw MarkdownRenderingError.allocationFailure
    }
    defer { cmark_node_free(root) }
    try Task.checkCancellation()
    guard let iterator = cmark_iter_new(root) else {
      throw MarkdownRenderingError.allocationFailure
    }
    defer { cmark_iter_free(iterator) }
    var nodes: [MarkdownNode] = []
    var headings: [MarkdownHeading] = []
    var lineStarts = [0]
    var offset = 0
    var previousCR = false
    for scalar in source.unicodeScalars {
      if scalar == "\n", previousCR {
        lineStarts[lineStarts.count - 1] = offset + 1
      } else if scalar == "\r" || scalar == "\n" {
        lineStarts.append(offset + 1)
      }
      previousCR = scalar == "\r"
      offset += scalar.utf16.count
    }
    let sourceText = source as NSString
    var callouts: [(UnsafeMutablePointer<cmark_node>, MarkdownCallout)] = []
    var transformedDestinations: [String: String] = [:]
    var identifiers: [UInt: Int] = [:]
    while true {
      let event = cmark_iter_next(iterator)
      if event == CMARK_EVENT_DONE { break }
      guard event == CMARK_EVENT_ENTER, let node = cmark_iter_get_node(iterator) else { continue }
      if nodes.count.isMultiple(of: 256) { try Task.checkCancellation() }
      let id = nodes.count
      identifiers[UInt(bitPattern: node)] = id
      let parentID = cmark_node_parent(node).flatMap { identifiers[UInt(bitPattern: $0)] }
      let nativeName = String(cString: cmark_node_get_type_string(node))
      let kind = MarkdownNodeKind(nativeName: nativeName)
      if let transformDestination, kind == .image || kind == .link,
        let destination = cmark_node_get_url(node)
      {
        let original = String(cString: destination)
        let key = nativeName + ":" + original
        let replacement: String
        if let cached = transformedDestinations[key] {
          replacement = cached
        } else {
          replacement = try transformDestination(kind, original)
          transformedDestinations[key] = replacement
        }
        cmark_node_set_url(node, replacement)
      }
      let line = Int(cmark_node_get_start_line(node))
      let range: MarkdownSourceRange? =
        line > 0
        ? MarkdownSourceRange(
          start: .init(line: line, column: Int(cmark_node_get_start_column(node))),
          end: .init(
            line: Int(cmark_node_get_end_line(node)), column: Int(cmark_node_get_end_column(node)))
        ) : nil
      var callout: MarkdownCallout?
      if options.alerts, kind == .blockquote, line > 0, line <= lineStarts.count {
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] : sourceText.length
        let rawLine = sourceText.substring(with: NSRange(location: start, length: end - start))
        callout = MarkdownCallout.recognize(node, rawLine: rawLine)
        if let callout { callouts.append((node, callout)) }
      }
      nodes.append(
        MarkdownNode(
          id: id, parentID: parentID, kind: kind, range: range,
          literal: cmark_node_get_literal(node).map { String(cString: $0) },
          destination: cmark_node_get_url(node).map { String(cString: $0) },
          headingLevel: kind == .heading ? Int(cmark_node_get_heading_level(node)) : nil,
          callout: callout))
      if kind == .heading, let title = cmark_render_plaintext(node, 0, 0) {
        headings.append(
          MarkdownHeading(
            id: id,
            title: String(cString: title).trimmingCharacters(in: .newlines),
            level: Int(cmark_node_get_heading_level(node)), sourceLine: line,
            utf16Offset: lineStarts[min(max(0, line - 1), lineStarts.count - 1)]))
        free(title)
      }
    }
    try Task.checkCancellation()
    for (quote, kind) in callouts {
      try Task.checkCancellation()
      try kind.decorate(quote)
    }
    guard let html = cmark_render_html(root, flags, cmark_parser_get_syntax_extensions(parser))
    else {
      throw MarkdownRenderingError.allocationFailure
    }
    defer { free(html) }
    return RenderedMarkdown(html: String(cString: html), nodes: nodes, headings: headings)
  }
}
