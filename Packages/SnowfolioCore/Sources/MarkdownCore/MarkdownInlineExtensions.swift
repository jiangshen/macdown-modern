import Foundation
import cmark_gfm

/// Optional dialects extend cmark's inline grammar. Code, links, escaping,
/// reference definitions and delimiter nesting remain native parser decisions.
final class MarkdownInlineExtensions {
  private final class Token {
    let kind: MarkdownNodeKind
    init(_ kind: MarkdownNodeKind) { self.kind = kind }
  }
  let native: UnsafeMutablePointer<cmark_syntax_extension>
  private let highlight: Bool
  private let superscript: Bool
  private struct Boundaries {
    var spaces: [Int] = []
    var closers: [Int: [Int]] = [:]
    var levels: [Int: Int] = [:]
    init(_ bytes: UnsafeMutablePointer<UInt8>, count: Int) {
      var level = 0
      var escaped = false
      for offset in 0..<count {
        let byte = bytes[offset]
        if [9, 10, 13, 32].contains(byte) { spaces.append(offset) }
        if byte == 94 { levels[offset] = level }
        if !escaped {
          if byte == 40 { level += 1 }
          if byte == 41 {
            closers[level, default: []].append(offset)
            level -= 1
          }
        }
        escaped = !escaped && byte == 92
      }
    }
    static func first(atOrAfter offset: Int, in values: [Int]) -> Int? {
      var low = 0
      var high = values.count
      while low < high {
        let middle = (low + high) / 2
        if values[middle] < offset { low = middle + 1 } else { high = middle }
      }
      return low < values.count ? values[low] : nil
    }
  }
  private var boundaries: [UInt: Boundaries] = [:]
  private var recursion = 0
  private(set) var limited = false

  init(highlight: Bool, superscript: Bool) throws {
    guard let native = cmark_syntax_extension_new("snowfolio_inline") else {
      throw MarkdownRenderingError.allocationFailure
    }
    self.native = native
    self.highlight = highlight
    self.superscript = superscript
    cmark_syntax_extension_set_private(native, Unmanaged.passUnretained(self).toOpaque(), nil)
    var characters: UnsafeMutablePointer<cmark_llist>?
    for character in (highlight ? [61] : []) + (superscript ? [94, 41] : []) {
      characters = cmark_llist_append(
        cmark_get_default_mem_allocator(), characters,
        UnsafeMutableRawPointer(bitPattern: character))
    }
    cmark_syntax_extension_set_special_inline_chars(native, characters)
    cmark_syntax_extension_set_emphasis(native, 1)
    cmark_syntax_extension_set_match_inline_func(native) { ext, parser, parent, character, inline in
      guard let ext, let parser, let parent, let inline,
        let state = cmark_syntax_extension_get_private(ext)
      else { return nil }
      return Unmanaged<MarkdownInlineExtensions>.fromOpaque(state).takeUnretainedValue()
        .match(parser, parent: parent, character: character, inline: inline)
    }
    cmark_syntax_extension_set_inline_from_delim_func(native) { ext, _, inline, opener, closer in
      guard let ext, let inline, let opener, let closer,
        let state = cmark_syntax_extension_get_private(ext)
      else { return nil }
      return Unmanaged<MarkdownInlineExtensions>.fromOpaque(state).takeUnretainedValue()
        .insert(inline, opener: opener, closer: closer)
    }
  }

  func kind(for node: UnsafeMutablePointer<cmark_node>) -> MarkdownNodeKind? {
    guard cmark_node_get_syntax_extension(node) == native,
      let value = cmark_node_get_user_data(node)
    else { return nil }
    return Unmanaged<Token>.fromOpaque(value).takeUnretainedValue().kind
  }

  private func match(
    _ parser: UnsafeMutablePointer<cmark_parser>,
    parent: UnsafeMutablePointer<cmark_node>, character: UInt8, inline: OpaquePointer
  ) -> UnsafeMutablePointer<cmark_node>? {
    guard cmark_inline_parser_in_bracket(inline, 1) == 0 else { return nil }
    if highlight, character == 61 {
      var left: Int32 = 0
      var right: Int32 = 0
      var before: Int32 = 0
      var after: Int32 = 0
      let column = cmark_inline_parser_get_column(inline)
      let count = cmark_inline_parser_scan_delimiters(
        inline, Int32.max, 61, &left, &right, &before, &after)
      guard
        let node = text(String(repeating: "=", count: Int(count)), inline: inline, column: column)
      else { return nil }
      if count >= 2, left != 0 || right != 0 {
        cmark_inline_parser_push_delimiter(inline, 61, left, right, node)
        // The emphasis modulo-three rule is specific to * and _, not ==.
        cmark_inline_parser_get_last_delimiter(inline)?.pointee.length = 2
      }
      return node
    }
    guard superscript, character == 94 || character == 41,
      let chunk = cmark_inline_parser_get_chunk(inline), let bytes = chunk.pointee.data
    else { return nil }
    let offset = Int(cmark_inline_parser_get_offset(inline))
    let count = Int(chunk.pointee.len)
    let column = cmark_inline_parser_get_column(inline)
    if character == 41 {
      guard let node = text(")", inline: inline, column: column) else { return nil }
      cmark_inline_parser_set_offset(inline, Int32(offset + 1))
      cmark_inline_parser_push_delimiter(inline, 94, 0, 1, node)
      return node
    }
    // Keep native footnote references in charge.
    guard offset + 1 < count else { return nil }
    if offset > 0, bytes[offset - 1] == 91, cmark_inline_parser_in_bracket(inline, 0) != 0 {
      return nil
    }
    if bytes[offset + 1] == 40 {
      guard let node = text("^(", inline: inline, column: column) else { return nil }
      cmark_inline_parser_set_offset(inline, Int32(offset + 2))
      cmark_inline_parser_push_delimiter(inline, 94, 1, 0, node)
      return node
    }
    guard recursion < 32 else {
      limited = true
      return nil
    }
    var delimiter = cmark_inline_parser_get_last_delimiter(inline)
    var inSuperscript = false
    var visited = 0
    while let current = delimiter {
      if current.pointee.delim_char == 94, current.pointee.can_open != 0 {
        inSuperscript = true
        break
      }
      visited += 1
      guard visited <= 128 else {
        limited = true
        return nil
      }
      delimiter = current.pointee.previous
    }
    // Index each native inline container once. Repeated long unmatched ^ tokens
    // must not repeatedly scan the remainder of a large paragraph.
    let key = UInt(bitPattern: parent)
    if boundaries[key] == nil { boundaries[key] = Boundaries(bytes, count: count) }
    guard let index = boundaries[key] else { return nil }
    var end = Boundaries.first(atOrAfter: offset + 1, in: index.spaces) ?? count
    if inSuperscript, let level = index.levels[offset],
      let closing = Boundaries.first(atOrAfter: offset + 1, in: index.closers[level] ?? [])
    {
      end = min(end, closing)
    }
    guard end - offset - 1 <= 65_536 else {
      limited = true
      return nil
    }
    guard end > offset + 1,
      let node = container(.superscript, tag: "sup")
    else { return nil }
    let body = String(
      decoding: UnsafeBufferPointer(start: bytes + offset + 1, count: end - offset - 1),
      as: UTF8.self)
    node.pointee.start_line = cmark_inline_parser_get_line(inline)
    node.pointee.end_line = node.pointee.start_line
    node.pointee.start_column = column + 1
    node.pointee.end_column = column + Int32(end - offset) - 1
    cmark_node_set_string_content(node, body)
    recursion += 1
    cmark_parse_inlines(parser, node, parser.pointee.refmap, parser.pointee.options)
    recursion -= 1
    node.pointee.start_column = column
    cmark_inline_parser_set_offset(inline, Int32(end))
    return node
  }

  private func text(_ value: String, inline: OpaquePointer, column: Int32) -> UnsafeMutablePointer<
    cmark_node
  >? {
    guard let node = cmark_node_new(CMARK_NODE_TEXT) else { return nil }
    cmark_node_set_literal(node, value)
    node.pointee.start_line = cmark_inline_parser_get_line(inline)
    node.pointee.end_line = node.pointee.start_line
    node.pointee.start_column = column
    node.pointee.end_column = column + Int32(value.utf8.count) - 1
    return node
  }

  private func container(_ kind: MarkdownNodeKind, tag: String) -> UnsafeMutablePointer<cmark_node>?
  {
    guard let node = cmark_node_new(CMARK_NODE_CUSTOM_INLINE) else { return nil }
    cmark_node_set_syntax_extension(node, native)
    cmark_node_set_on_enter(node, "<" + tag + ">")
    cmark_node_set_on_exit(node, "</" + tag + ">")
    cmark_node_set_user_data(node, Unmanaged.passRetained(Token(kind)).toOpaque())
    cmark_node_set_user_data_free_func(node) { _, value in
      if let value { Unmanaged<Token>.fromOpaque(value).release() }
    }
    return node
  }

  private func insert(
    _ inline: OpaquePointer, opener: UnsafeMutablePointer<delimiter>,
    closer: UnsafeMutablePointer<delimiter>
  ) -> UnsafeMutablePointer<delimiter>? {
    let next = closer.pointee.next
    let opening = opener.pointee.inl_text
    let closing = closer.pointee.inl_text
    guard let opening, let closing else { return next }
    let isHighlight = opener.pointee.delim_char == 61
    let openingSize: Int32 = 2
    let closingSize: Int32 = isHighlight ? 2 : 1
    var child = cmark_node_next(opening)
    var nestedHighlight = false
    if isHighlight {
      while let current = child, current != closing {
        if kind(for: current) == .highlight {
          nestedHighlight = true
          break
        }
        child = cmark_node_next(current)
      }
    }
    let hasContent = cmark_node_next(opening) != closing && !nestedHighlight
    var created: UnsafeMutablePointer<cmark_node>?
    if hasContent, opener.pointee.length >= openingSize, closer.pointee.length >= closingSize {
      created = container(
        isHighlight ? .highlight : .superscript, tag: isHighlight ? "mark" : "sup")
    }
    if let node = created {
      node.pointee.start_line = opening.pointee.start_line
      node.pointee.start_column = opening.pointee.end_column - openingSize + 1
      node.pointee.end_line = closing.pointee.start_line
      node.pointee.end_column = closing.pointee.start_column + closingSize - 1
      var child = cmark_node_next(opening)
      while let current = child, current != closing {
        child = cmark_node_next(current)
        cmark_node_append_child(node, current)
      }
      cmark_node_insert_after(opening, node)
    }
    let remainingOpen = openerLength(opening) - Int(openingSize)
    let remainingClose = openerLength(closing) - Int(closingSize)
    let reuseCloser = created != nil && isHighlight && remainingClose >= 2
    // A run such as ==a====b== closes one highlight and opens the next.
    // Keep that remaining delimiter; all interior records must be removed
    // before source marker nodes can be freed.
    var cursor = closer.pointee.previous
    while let current = cursor {
      let previous = current.pointee.previous
      cmark_inline_parser_remove_delimiter(inline, current)
      if current == opener { break }
      cursor = previous
    }
    if reuseCloser {
      closer.pointee.length = 2
    } else {
      cmark_inline_parser_remove_delimiter(inline, closer)
    }
    if created != nil {
      if remainingOpen == 0 {
        cmark_node_free(opening)
      } else {
        cmark_node_set_literal(opening, String(repeating: "=", count: remainingOpen))
        opening.pointee.end_column -= openingSize
      }
      if remainingClose == 0 {
        cmark_node_free(closing)
      } else {
        cmark_node_set_literal(closing, String(repeating: "=", count: remainingClose))
        closing.pointee.start_column += closingSize
      }
    }
    return reuseCloser ? closer : next
  }

  private func openerLength(_ node: UnsafeMutablePointer<cmark_node>) -> Int {
    cmark_node_get_literal(node).map { strlen($0) } ?? 0
  }

  deinit { cmark_syntax_extension_free(cmark_get_default_mem_allocator(), native) }
}
