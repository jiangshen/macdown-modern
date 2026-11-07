import Foundation
import cmark_gfm

/// Optional legacy underscore grammar. Child Markdown is parsed by cmark; the
/// compatibility matcher only owns underscore delimiters and their span bounds.
/// Span-search semantics derive from Hoedown 3.0.7 (ISC; bundled Hoedown-inline.txt).
final class MarkdownDelimiterExtensions {
  let native: UnsafeMutablePointer<cmark_syntax_extension>
  private var remainingWork: Int
  private var recursion = 0
  private(set) var limited = false

  private enum Kind: Equatable { case underline, strong, triple }
  private struct Span {
    let body: Range<Int>
    let end: Int
    let kind: Kind
  }

  init(sourceLength: Int) throws {
    remainingWork = max(65_536, sourceLength * 16)
    guard let native = cmark_syntax_extension_new("snowfolio_delimiters") else {
      throw MarkdownRenderingError.allocationFailure
    }
    self.native = native
    cmark_syntax_extension_set_private(native, Unmanaged.passUnretained(self).toOpaque(), nil)
    // Underscore is already a native special character. This pre-token matcher
    // does not register a delimiter-stack override for native image/plain scopes.
    cmark_syntax_extension_set_match_inline_before_func(native) {
      ext, parser, _, character, inline in
      guard character == 95, let ext, let parser, let inline,
        let state = cmark_syntax_extension_get_private(ext)
      else { return nil }
      return Unmanaged<MarkdownDelimiterExtensions>.fromOpaque(state).takeUnretainedValue()
        .match(parser, inline: inline)
    }
  }

  func kind(for node: UnsafeMutablePointer<cmark_node>) -> MarkdownNodeKind? {
    cmark_node_get_syntax_extension(node) == native ? .underline : nil
  }

  private func match(
    _ parser: UnsafeMutablePointer<cmark_parser>, inline: OpaquePointer
  ) -> UnsafeMutablePointer<cmark_node>? {
    // Image descriptions retain literal source markers, as in the original app.
    let isImage = cmark_inline_parser_in_bracket(inline, 1) != 0
    guard let chunk = cmark_inline_parser_get_chunk(inline), let data = chunk.pointee.data
    else { return nil }
    let bytes = UnsafeBufferPointer(start: data, count: Int(chunk.pointee.len))
    let offset = Int(cmark_inline_parser_get_offset(inline))
    let column = cmark_inline_parser_get_column(inline)
    let line = cmark_inline_parser_get_line(inline)
    var run = 1
    while offset + run < bytes.count, bytes[offset + run] == 95 { run += 1 }
    var span: Span?
    if !isImage, run <= 3, offset + run < bytes.count, !space(bytes[offset + run]), recursion < 32 {
      span = findSpan(bytes, body: offset + run, kind: run)
    }
    if recursion >= 32 { limited = true }
    guard let span, span.body.count <= 65_536 else {
      if (span?.body.count ?? 0) > 65_536 { limited = true }
      guard let text = cmark_node_new(CMARK_NODE_TEXT) else { return nil }
      let literalCount = isImage || limited ? run : max(1, run - 3)
      cmark_node_set_literal(text, String(repeating: "_", count: literalCount))
      text.pointee.start_line = line
      text.pointee.end_line = line
      text.pointee.start_column = column
      text.pointee.end_column = column + Int32(literalCount) - 1
      cmark_inline_parser_set_offset(inline, Int32(offset + literalCount))
      return text
    }
    let type = span.kind == .underline ? CMARK_NODE_CUSTOM_INLINE : CMARK_NODE_STRONG
    guard let node = cmark_node_new(type) else { return nil }
    if span.kind == .underline {
      cmark_node_set_syntax_extension(node, native)
      cmark_node_set_on_enter(node, "<u>")
      cmark_node_set_on_exit(node, "</u>")
    }
    var bodyNode = node
    if span.kind == .triple {
      guard let emphasis = cmark_node_new(CMARK_NODE_EMPH) else {
        cmark_node_free(node)
        return nil
      }
      cmark_node_append_child(node, emphasis)
      bodyNode = emphasis
    }
    let body = String(decoding: bytes[span.body], as: UTF8.self)
    bodyNode.pointee.start_line = line
    bodyNode.pointee.start_column = column + Int32(span.body.lowerBound - offset)
    cmark_node_set_string_content(bodyNode, body)
    recursion += 1
    cmark_parse_inlines(parser, bodyNode, parser.pointee.refmap, parser.pointee.options)
    recursion -= 1
    node.pointee.start_line = line
    node.pointee.end_line = line
    node.pointee.start_column = column
    node.pointee.end_column = column + Int32(span.end - offset) - 1
    if bodyNode != node {
      bodyNode.pointee.start_line = line
      bodyNode.pointee.start_column = column
      bodyNode.pointee.end_line = line
      bodyNode.pointee.end_column = node.pointee.end_column
      for index in offset..<span.end where bytes[index] == 10 {
        bodyNode.pointee.end_line += 1
        bodyNode.pointee.end_column = Int32(span.end - index - 1)
      }
    }
    cmark_inline_parser_set_offset(inline, Int32(span.end))
    return node
  }

  private func space(_ byte: UInt8) -> Bool { [9, 10, 11, 12, 13, 32].contains(byte) }

  private func spend() -> Bool {
    remainingWork -= 1
    if remainingWork < 0 {
      limited = true
      return false
    }
    return true
  }

  /// Retain the original one/two/three-marker choices, including fallback to a
  /// later marker in a long run. This is separate from standard CommonMark mode.
  private func findSpan(_ bytes: UnsafeBufferPointer<UInt8>, body: Int, kind: Int) -> Span? {
    var cursor = body
    if kind == 1, body + 1 < bytes.count, bytes[body] == 95, bytes[body + 1] == 95 {
      cursor += 1
    }
    while cursor < bytes.count, let found = nextMarker(bytes, from: cursor) {
      guard found > cursor else { return nil }
      cursor = found
      guard found > body else { return nil }
      let nonspace = !space(bytes[found - 1])
      if kind == 1, nonspace {
        return Span(body: body..<found, end: found + 1, kind: .underline)
      }
      if kind == 2 {
        if found + 1 < bytes.count, bytes[found + 1] == 95, nonspace {
          return Span(body: body..<found, end: found + 2, kind: .strong)
        }
        cursor += 1
      } else if kind == 3, nonspace {
        if found + 2 < bytes.count, bytes[found + 1] == 95, bytes[found + 2] == 95 {
          return Span(body: body..<found, end: found + 3, kind: .triple)
        }
        return findSpan(
          bytes, body: body - (found + 1 < bytes.count && bytes[found + 1] == 95 ? 2 : 1),
          kind: found + 1 < bytes.count && bytes[found + 1] == 95 ? 1 : 2)
      }
    }
    return nil
  }

  /// Skip escaped delimiters, code spans and link/reference constructs while
  /// choosing a matching underscore. Actual child syntax and escaping stay native.
  private func nextMarker(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
    var cursor = start
    while cursor < bytes.count {
      guard spend() else { return nil }
      let byte = bytes[cursor]
      if byte == 92 {
        cursor += min(2, bytes.count - cursor)
        continue
      }
      if byte == 95 { return cursor }
      if byte == 96 {
        var count = 0
        while cursor < bytes.count, bytes[cursor] == 96 {
          guard spend() else { return nil }
          cursor += 1
          count += 1
        }
        var matching = 0
        var fallback: Int?
        while cursor < bytes.count, matching < count {
          guard spend() else { return nil }
          if fallback == nil, bytes[cursor] == 95 { fallback = cursor }
          matching = bytes[cursor] == 96 ? matching + 1 : 0
          cursor += 1
        }
        if matching < count { return fallback }
      } else if byte == 91 {
        var fallback: Int?
        cursor += 1
        while cursor < bytes.count, bytes[cursor] != 93 {
          guard spend() else { return nil }
          if fallback == nil, bytes[cursor] == 95 { fallback = cursor }
          cursor += 1
        }
        cursor += 1
        while cursor < bytes.count, space(bytes[cursor]) {
          guard spend() else { return nil }
          cursor += 1
        }
        guard cursor < bytes.count else { return fallback }
        let closing: UInt8
        if bytes[cursor] == 91 {
          closing = 93
        } else if bytes[cursor] == 40 {
          closing = 41
        } else {
          if let fallback { return fallback }
          continue
        }
        cursor += 1
        while cursor < bytes.count, bytes[cursor] != closing {
          guard spend() else { return nil }
          if fallback == nil, bytes[cursor] == 95 { fallback = cursor }
          cursor += 1
        }
        if cursor == bytes.count { return fallback }
        cursor += 1
      } else {
        cursor += 1
      }
    }
    return nil
  }

  deinit { cmark_syntax_extension_free(cmark_get_default_mem_allocator(), native) }
}
