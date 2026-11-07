import CodeHighlightCore
import DiagramCore
import Foundation
import MathCore
import cmark_gfm
import cmark_gfm_extensions

/// Actor confinement keeps native parser pointers out of UI state and Sendable values.
/// Each request parses once; its native tree supplies both HTML and the Swift AST.
public actor MarkdownProcessor {
  private static let registeredExtensions: Void = {
    cmark_gfm_core_extensions_ensure_registered()
  }()

  private var codeHighlighter: CodeHighlighter?
  private var mathRenderer: MathRenderer?

  public init() {}

  public func render(
    _ source: String, options: MarkdownRenderingOptions = .init(),
    interactiveCallouts: Bool = false, includeSyntax: Bool = false,
    diagramPresentation: DiagramPresentation = .portable,
    transformDestination: (@Sendable (MarkdownNodeKind, String) throws -> String)? = nil
  ) async throws
    -> RenderedMarkdown
  {
    try Task.checkCancellation()
    let front = options.frontMatter ? try MarkdownFrontMatter.detect(in: source) : nil
    let parserSource = front?.maskedSource ?? source
    _ = Self.registeredExtensions
    var flags = CMARK_OPT_SOURCEPOS | CMARK_OPT_VALIDATE_UTF8
    if options.footnotes { flags |= CMARK_OPT_FOOTNOTES }
    if options.smartPunctuation { flags |= CMARK_OPT_SMART }
    if options.hardLineBreaks { flags |= CMARK_OPT_HARDBREAKS }
    if options.rawHTML { flags |= CMARK_OPT_UNSAFE }
    let mathSyntax =
      options.math
      ? try MarkdownMath(source: parserSource, inlineDollars: options.inlineDollarMath) : nil
    let inlineSyntax =
      options.highlight || options.superscript
      ? try MarkdownInlineExtensions(highlight: options.highlight, superscript: options.superscript)
      : nil
    defer { withExtendedLifetime((mathSyntax, inlineSyntax)) {} }
    guard let parser = cmark_parser_new(flags) else {
      throw MarkdownRenderingError.allocationFailure
    }
    defer { cmark_parser_free(parser) }
    if let mathSyntax { cmark_parser_attach_syntax_extension(parser, mathSyntax.native) }
    if let inlineSyntax { cmark_parser_attach_syntax_extension(parser, inlineSyntax.native) }
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
    try parserSource.utf8CString.withUnsafeBufferPointer { bytes in
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
    var headingNodes: [UnsafeMutablePointer<cmark_node>] = []
    var tocNodes: [UnsafeMutablePointer<cmark_node>] = []
    var anchors = HeadingAnchors()
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
    var codeBlocks: [UnsafeMutablePointer<cmark_node>] = []
    var diagramNodes: [(UnsafeMutablePointer<cmark_node>, DiagramKind, String)] = []
    var mathNodes: [(UnsafeMutablePointer<cmark_node>, String, Bool, Bool)] = []
    var callouts: [(UnsafeMutablePointer<cmark_node>, CalloutMarker)] = []
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
      var kind = inlineSyntax?.kind(for: node) ?? MarkdownNodeKind(nativeName: nativeName)
      if let token = mathSyntax?.token(for: node) {
        kind = .math(display: token.display)
        mathNodes.append((node, token.source, token.display, token.block))
      } else if options.math, kind == .codeBlock,
        let info = cmark_node_get_fence_info(node),
        String(cString: info).trimmingCharacters(in: .whitespaces).lowercased() == "math",
        let literal = cmark_node_get_literal(node)
      {
        kind = .math(display: true)
        mathNodes.append((node, String(cString: literal), true, true))
      }
      if kind == .codeBlock, let info = cmark_node_get_fence_info(node),
        let diagram = DiagramKind.fence(String(cString: info)),
        diagram.isMermaid ? options.mermaid : options.graphviz,
        let literal = cmark_node_get_literal(node)
      {
        kind = .diagram(diagram)
        diagramNodes.append((node, diagram, String(cString: literal)))
      }
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
      if options.codeHighlighting, kind == .codeBlock { codeBlocks.append(node) }
      if options.tableOfContents, kind == .paragraph,
        MarkdownNavigation.isTableOfContents(node, source: sourceText, lineStarts: lineStarts)
      {
        tocNodes.append(node)
      }
      var marker: CalloutMarker?
      if options.alerts, kind == .blockquote, line > 0, line <= lineStarts.count {
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] : sourceText.length
        let rawLine = sourceText.substring(with: NSRange(location: start, length: end - start))
        marker = MarkdownCallout.recognize(node, rawLine: rawLine)
        if let marker { callouts.append((node, marker)) }
      }
      nodes.append(
        MarkdownNode(
          id: id, parentID: parentID, kind: kind, range: range,
          literal: cmark_node_get_literal(node).map { String(cString: $0) },
          destination: cmark_node_get_url(node).map { String(cString: $0) },
          headingLevel: kind == .heading ? Int(cmark_node_get_heading_level(node)) : nil,
          callout: marker?.kind, calloutEmoji: marker?.emoji))
      if kind == .document, let metadata = front?.metadata {
        nodes.append(
          MarkdownNode(
            id: nodes.count, parentID: id, kind: .frontMatter, range: metadata.range,
            literal: sourceText.substring(with: metadata.utf16Range), destination: nil,
            headingLevel: nil, callout: nil, calloutEmoji: nil))
      }
      if kind == .heading, let title = cmark_render_plaintext(node, 0, 0) {
        let headingTitle = String(cString: title).trimmingCharacters(in: .newlines)
        headingNodes.append(node)
        headings.append(
          MarkdownHeading(
            id: id,
            title: headingTitle,
            level: Int(cmark_node_get_heading_level(node)), sourceLine: line,
            utf16Offset: lineStarts[min(max(0, line - 1), lineStarts.count - 1)],
            anchor: anchors.next(for: headingTitle)))
        free(title)
      }
    }
    try Task.checkCancellation()
    for (quote, marker) in callouts {
      try Task.checkCancellation()
      try marker.kind.decorate(quote, emoji: marker.emoji, interactive: interactiveCallouts)
    }
    for (index, node) in headingNodes.enumerated() {
      try Task.checkCancellation()
      try MarkdownNavigation.decorateHeading(node, heading: headings[index], index: index)
    }
    if !tocNodes.isEmpty {
      let toc = try MarkdownNavigation.tableOfContents(headings)
      for node in tocNodes { try MarkdownNavigation.decorateTOC(node, html: toc) }
    }
    var mathNotices = false
    for (node, source, display, block) in mathNodes {
      try Task.checkCancellation()
      if mathRenderer == nil { mathRenderer = MathRenderer() }
      guard let rendered = try mathRenderer?.render(source, display: display) else { continue }
      mathNotices = mathNotices || rendered.issue != nil
      guard
        let replacement = cmark_node_new(block ? CMARK_NODE_CUSTOM_BLOCK : CMARK_NODE_CUSTOM_INLINE)
      else { throw MarkdownRenderingError.allocationFailure }
      let position =
        "\(cmark_node_get_start_line(node)):\(cmark_node_get_start_column(node))-\(cmark_node_get_end_line(node)):\(cmark_node_get_end_column(node))"
      let html =
        "<span data-sourcepos=\"\(position)\" class=\"md-math\(display ? " md-math-display" : "")\">"
        + rendered.html + "</span>"
      guard cmark_node_set_on_enter(replacement, html) == 1,
        cmark_node_replace(node, replacement) == 1
      else {
        cmark_node_free(replacement)
        throw MarkdownRenderingError.invalidTreeTransformation
      }
      cmark_node_free(node)
    }
    var diagramNotices = false
    var renderedDiagrams = 0
    var diagramUsesMath = false
    for (node, kind, source) in diagramNodes {
      try Task.checkCancellation()
      let result = try await DiagramRenderer.shared.render(source, kind: kind)
      try Task.checkCancellation()
      diagramNotices = diagramNotices || result.issue != nil || !result.isRendered
      let position =
        "\(cmark_node_get_start_line(node)):\(cmark_node_get_start_column(node))-\(cmark_node_get_end_line(node)):\(cmark_node_get_end_column(node))"
      guard
        let html = try await result.html(
          position: position, key: RenderedDiagram.key(source: source, kind: kind),
          presentation: diagramPresentation)
      else {
        if options.codeHighlighting { codeBlocks.append(node) }
        continue
      }
      guard let replacement = cmark_node_new(CMARK_NODE_CUSTOM_BLOCK) else {
        throw MarkdownRenderingError.allocationFailure
      }
      guard cmark_node_set_on_enter(replacement, html) == 1,
        cmark_node_replace(node, replacement) == 1
      else {
        cmark_node_free(replacement)
        throw MarkdownRenderingError.invalidTreeTransformation
      }
      cmark_node_free(node)
      renderedDiagrams += 1
      diagramUsesMath = diagramUsesMath || result.usesMath
    }
    var highlightedCodeBlocks = 0
    for block in codeBlocks {
      try Task.checkCancellation()
      guard let info = cmark_node_get_fence_info(block), info.pointee != 0,
        let literal = cmark_node_get_literal(block)
      else { continue }
      if codeHighlighter == nil { codeHighlighter = try CodeHighlighter() }
      guard
        let code = try codeHighlighter?.highlight(
          String(cString: literal), language: String(cString: info))
      else { continue }
      guard let container = cmark_node_new(CMARK_NODE_CUSTOM_BLOCK) else {
        throw MarkdownRenderingError.allocationFailure
      }
      let position =
        "\(cmark_node_get_start_line(block)):\(cmark_node_get_start_column(block))-\(cmark_node_get_end_line(block)):\(cmark_node_get_end_column(block))"
      let opening =
        "<pre data-sourcepos=\"\(position)\" class=\"language-\(code.language)\" data-code-highlighted=\"true\"><code class=\"language-\(code.language)\">"
        + code.html
      guard cmark_node_set_on_enter(container, opening) == 1,
        cmark_node_set_on_exit(container, "</code></pre>") == 1,
        cmark_node_replace(block, container) == 1
      else {
        cmark_node_free(container)
        throw MarkdownRenderingError.invalidTreeTransformation
      }
      cmark_node_free(block)
      highlightedCodeBlocks += 1
    }
    guard let html = cmark_render_html(root, flags, cmark_parser_get_syntax_extensions(parser))
    else {
      throw MarkdownRenderingError.allocationFailure
    }
    defer { free(html) }
    return RenderedMarkdown(
      html: (front?.metadata?.html ?? "") + String(cString: html), nodes: nodes, headings: headings,
      syntax: includeSyntax ? try MarkdownSyntax.build(source: source, nodes: nodes) : nil,
      highlightedCodeBlocks: highlightedCodeBlocks, mathExpressions: mathNodes.count,
      diagrams: renderedDiagrams, diagramUsesMath: diagramUsesMath,
      frontMatter: front?.metadata,
      notices: (front?.notice.map { [$0] } ?? []) + (mathNotices ? [.unsupportedMath] : [])
        + (diagramNotices ? [.unsupportedDiagram] : [])
        + (inlineSyntax?.limited == true ? [.complexInlineFormatting] : []))
  }
}
