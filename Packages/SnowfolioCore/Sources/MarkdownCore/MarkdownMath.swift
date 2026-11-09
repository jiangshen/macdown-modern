import Foundation
import cmark_gfm

/// One extension per parser request; no global mutable callbacks or parser state.
final class MarkdownMath {
  final class Token {
    var source: String
    let display: Bool
    let block: Bool
    let closingLine: Int?
    let opening: String?
    var closed = false
    init(
      source: String, display: Bool, block: Bool = false, closingLine: Int? = nil,
      opening: String? = nil
    ) {
      self.source = source
      self.display = display
      self.block = block
      self.closingLine = closingLine
      self.opening = opening
    }
  }
  let native: UnsafeMutablePointer<cmark_syntax_extension>
  private let inlineDollars: Bool
  private let blockPairs: [Int: (line: Int, opening: String)]
  private var preparedParent: UnsafeMutablePointer<cmark_node>?
  private var runs: [Int: Int] = [:]
  private var inlineClosers: [Int] = []
  private var displayClosers: [Int] = []
  private struct Bracket: Hashable {
    let backslashes: Int
    let display: Bool
    var width: Int { backslashes + 1 }
  }
  private var bracketOpeners: [Int: Bracket] = [:]
  private var bracketClosers: [Bracket: [Int]] = [:]

  init(source: String, inlineDollars: Bool) throws {
    guard let native = cmark_syntax_extension_new("snowfolio_math") else {
      throw MarkdownRenderingError.allocationFailure
    }
    self.native = native
    self.inlineDollars = inlineDollars
    blockPairs = Self.blockPairs(in: source)
    cmark_syntax_extension_set_private(native, Unmanaged.passUnretained(self).toOpaque(), nil)
    var chars = cmark_llist_append(
      cmark_get_default_mem_allocator(), nil,
      UnsafeMutableRawPointer(bitPattern: 36))
    chars = cmark_llist_append(
      cmark_get_default_mem_allocator(), chars, UnsafeMutableRawPointer(bitPattern: 92))
    cmark_syntax_extension_set_special_inline_chars(native, chars)
    cmark_syntax_extension_set_open_block_func(native) {
      ext, indented, parser, parent, input, length in
      guard indented == 0, let ext, let parser, let parent, let input,
        let state = cmark_syntax_extension_get_private(ext)
      else { return nil }
      return Unmanaged<MarkdownMath>.fromOpaque(state).takeUnretainedValue()
        .openBlock(parser, parent: parent, input: input, length: Int(length))
    }
    cmark_syntax_extension_set_match_block_func(native) { ext, parser, input, length, node in
      guard let ext, let parser, let input, let node,
        let state = cmark_syntax_extension_get_private(ext)
      else { return 0 }
      return Unmanaged<MarkdownMath>.fromOpaque(state).takeUnretainedValue()
        .continueBlock(parser, node: node, input: input, length: Int(length))
    }
    // The native pre-token bridge adjusts both node and parser coordinates
    // after a multiline match; changing only the byte offset loses later lines.
    cmark_syntax_extension_set_match_inline_before_func(native) {
      ext, _, parent, character, parser in
      guard character == 36 || character == 92, let ext, let parser, let parent,
        let state = cmark_syntax_extension_get_private(ext)
      else { return nil }
      return Unmanaged<MarkdownMath>.fromOpaque(state).takeUnretainedValue().match(
        parser, parent: parent, character: character)
    }
  }

  func token(for node: UnsafeMutablePointer<cmark_node>) -> Token? {
    guard cmark_node_get_syntax_extension(node) == native,
      let pointer = cmark_node_get_user_data(node)
    else { return nil }
    let token = Unmanaged<Token>.fromOpaque(pointer).takeUnretainedValue()
    if token.block, let literal = cmark_node_get_literal(node) {
      token.source = String(cString: literal)
      if token.opening == #"\\["# { token.source = Self.decodeLegacy(Array(token.source.utf8)) }
      if !token.closed { token.source = (token.opening ?? "$$") + "\n" + token.source }
    }
    return token
  }

  /// Pair stand-alone delimiters before parsing so an unmatched opener cannot
  /// swallow the rest of a document. Native cmark still decides code/list/quote scope.
  private static func blockPairs(in source: String) -> [Int: (line: Int, opening: String)] {
    let bytes = Array(source.utf8)
    var result: [Int: (line: Int, opening: String)] = [:]
    var openers: [(line: Int, marker: String, closing: String)] = []
    var closers: [String: [Int]] = [:]
    var start = 0
    var cursor = 0
    var line = 1
    func scan(_ end: Int) {
      guard end - start <= 1024 else { return }
      let text = String(decoding: bytes[start..<end], as: UTF8.self).trimmingCharacters(
        in: .whitespaces)
      // Prefixes are only a candidate filter; the block parser validates them.
      let stripped = text.drop(while: { "> -+*0123456789.)\t".contains($0) })
      let marker = String(stripped)
      let closing: String
      switch marker {
      case "$$": closing = "$$"
      case #"\["#: closing = #"\]"#
      case #"\\["#: closing = #"\\]"#
      case #"\]"#, #"\\]"#:
        closers[marker, default: []].append(line)
        return
      default: return
      }
      openers.append((line, marker, closing))
      if marker == "$$" { closers[closing, default: []].append(line) }
    }
    while cursor < bytes.count {
      if bytes[cursor] == 10 || bytes[cursor] == 13 {
        scan(cursor)
        if bytes[cursor] == 13, cursor + 1 < bytes.count, bytes[cursor + 1] == 10 { cursor += 1 }
        start = cursor + 1
        line += 1
      }
      cursor += 1
    }
    scan(bytes.count)
    for opener in openers {
      if let closingLine = Self.first(after: opener.line, in: closers[opener.closing] ?? []) {
        result[opener.line] = (closingLine, opener.marker)
      }
    }
    return result
  }

  private func openBlock(
    _ parser: UnsafeMutablePointer<cmark_parser>, parent: UnsafeMutablePointer<cmark_node>,
    input: UnsafeMutablePointer<UInt8>, length: Int
  ) -> UnsafeMutablePointer<cmark_node>? {
    let line = Int(cmark_parser_get_line_number(parser))
    guard let pair = blockPairs[line] else { return nil }
    let first = Int(cmark_parser_get_first_nonspace(parser))
    guard first <= length else { return nil }
    let text = String(
      decoding: UnsafeBufferPointer(start: input + first, count: length - first), as: UTF8.self
    )
    .trimmingCharacters(in: .whitespacesAndNewlines)
    guard text == pair.opening,
      let node = cmark_parser_add_child(parser, parent, CMARK_NODE_CODE_BLOCK, Int32(first + 1))
    else { return nil }
    cmark_node_set_syntax_extension(node, native)
    let token = Token(
      source: "", display: true, block: true, closingLine: pair.line, opening: pair.opening)
    cmark_node_set_user_data(node, Unmanaged.passRetained(token).toOpaque())
    cmark_node_set_user_data_free_func(node) { _, value in
      if let value { Unmanaged<Token>.fromOpaque(value).release() }
    }
    Self.consumeLine(parser, input: input, length: length)
    return node
  }

  private func continueBlock(
    _ parser: UnsafeMutablePointer<cmark_parser>, node: UnsafeMutablePointer<cmark_node>,
    input: UnsafeMutablePointer<UInt8>, length: Int
  ) -> Int32 {
    guard let pointer = cmark_node_get_user_data(node) else { return 0 }
    let token = Unmanaged<Token>.fromOpaque(pointer).takeUnretainedValue()
    guard token.block, !token.closed else { return 0 }
    if Int(cmark_parser_get_line_number(parser)) == token.closingLine {
      let first = Int(cmark_parser_get_first_nonspace(parser))
      guard first <= length else { return 0 }
      let text = String(
        decoding: UnsafeBufferPointer(start: input + first, count: length - first), as: UTF8.self
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)
      let expected = token.opening?.replacingOccurrences(of: "[", with: "]")
      if text == expected {
        token.closed = true
        Self.consumeLine(parser, input: input, length: length)
      }
    }
    return 1
  }

  private static func consumeLine(
    _ parser: UnsafeMutablePointer<cmark_parser>, input: UnsafeMutablePointer<UInt8>, length: Int
  ) {
    let offset = Int(cmark_parser_get_offset(parser))
    input.withMemoryRebound(to: CChar.self, capacity: length) {
      cmark_parser_advance_offset(parser, $0, Int32(max(0, length - offset)), 0)
    }
  }

  /// Index delimiter runs once per inline container. Repeated unmatched dollars
  /// must not rescan a long paragraph quadratically.
  private func prepare(_ bytes: UnsafePointer<UInt8>, count: Int) {
    runs.removeAll(keepingCapacity: true)
    inlineClosers.removeAll(keepingCapacity: true)
    displayClosers.removeAll(keepingCapacity: true)
    bracketOpeners.removeAll(keepingCapacity: true)
    bracketClosers.removeAll(keepingCapacity: true)
    var cursor = 0
    while cursor < count {
      let byte = bytes[cursor]
      if byte == 10 || byte == 13 {
        cursor += 1
        continue
      }
      if byte == 92 {
        let start = cursor
        while cursor < count, bytes[cursor] == 92 { cursor += 1 }
        let backslashes = cursor - start
        if cursor < count, backslashes <= 2,
          [40, 41, 91, 93].contains(bytes[cursor])
        {
          let marker = bytes[cursor]
          let bracket = Bracket(backslashes: backslashes, display: marker == 91 || marker == 93)
          if marker == 40 || marker == 91 {
            bracketOpeners[start] = bracket
          } else {
            bracketClosers[bracket, default: []].append(start)
          }
          cursor += 1
        } else if backslashes % 2 == 1, cursor < count,
          bytes[cursor] != 10, bytes[cursor] != 13
        {
          // An odd final backslash escapes the following native character.
          cursor += 1
        }
        continue
      }
      guard byte == 36 else {
        cursor += 1
        continue
      }
      let start = cursor
      while cursor < count, bytes[cursor] == 36 { cursor += 1 }
      let width = cursor - start
      runs[start] = width
      if width == 2 { displayClosers.append(start) }
      if width == 1, start > 0, !Self.space(bytes[start - 1]),
        cursor == count || !(48...57).contains(bytes[cursor])
      {
        inlineClosers.append(start)
      }
    }
  }

  private static func first(after offset: Int, in values: [Int]) -> Int? {
    var low = 0
    var high = values.count
    while low < high {
      let middle = (low + high) / 2
      if values[middle] <= offset { low = middle + 1 } else { high = middle }
    }
    return low < values.count ? values[low] : nil
  }

  private func match(
    _ parser: OpaquePointer, parent: UnsafeMutablePointer<cmark_node>, character: UInt8
  ) -> UnsafeMutablePointer<cmark_node>? {
    // Image alt text stays literal. cmark renders it through a separate plain-text path.
    guard cmark_inline_parser_in_bracket(parser, 1) == 0,
      let chunk = cmark_inline_parser_get_chunk(parser), let bytes = chunk.pointee.data
    else { return nil }
    let count = Int(chunk.pointee.len)
    if preparedParent != parent {
      prepare(UnsafePointer(bytes), count: count)
      preparedParent = parent
    }
    let start = Int(cmark_inline_parser_get_offset(parser))
    if character == 92 {
      guard let bracket = bracketOpeners[start] else { return nil }
      let body = start + bracket.width
      guard let close = Self.first(after: body, in: bracketClosers[bracket] ?? []) else {
        return nil
      }
      let raw = UnsafeBufferPointer(start: bytes + body, count: close - body)
      let source =
        bracket.backslashes == 2
        ? Self.decodeLegacy(Array(raw)) : String(decoding: raw, as: UTF8.self)
      guard
        let node = makeInline(
          source, display: bracket.display, parser: parser,
          startColumn: cmark_inline_parser_get_column(parser), length: close + bracket.width - start
        )
      else { return nil }
      cmark_inline_parser_set_offset(parser, Int32(close + bracket.width))
      return node
    }
    guard let width = runs[start], width <= 2, width == 2 || inlineDollars else { return nil }
    let body = start + width
    guard body < count, width == 2 || !Self.space(bytes[body]),
      let end = Self.first(after: body, in: width == 2 ? displayClosers : inlineClosers)
    else { return nil }
    let source = String(
      decoding: UnsafeBufferPointer(start: bytes + body, count: end - body), as: UTF8.self)
    guard
      let node = makeInline(
        source, display: width == 2, parser: parser,
        startColumn: cmark_inline_parser_get_column(parser), length: end + width - start)
    else { return nil }
    cmark_inline_parser_set_offset(parser, Int32(end + width))
    return node
  }

  private func makeInline(
    _ source: String, display: Bool, parser: OpaquePointer,
    startColumn: Int32, length: Int
  ) -> UnsafeMutablePointer<cmark_node>? {
    guard let node = cmark_node_new_with_ext(CMARK_NODE_CODE, native) else { return nil }
    cmark_node_set_literal(node, source)
    let line = cmark_inline_parser_get_line(parser)
    // cmark deliberately exposes source fields for syntax extensions.
    node.pointee.start_line = line
    node.pointee.end_line = line
    node.pointee.start_column = startColumn
    node.pointee.end_column = startColumn + Int32(length) - 1
    cmark_node_set_user_data(
      node, Unmanaged.passRetained(Token(source: source, display: display)).toOpaque())
    cmark_node_set_user_data_free_func(node) { _, value in
      if let value { Unmanaged<Token>.fromOpaque(value).release() }
    }
    return node
  }

  private static func decodeLegacy(_ raw: [UInt8]) -> String {
    var decoded: [UInt8] = []
    var cursor = 0
    while cursor < raw.count {
      if raw[cursor] == 92, cursor + 1 < raw.count {
        let next = raw[cursor + 1]
        if (33...47).contains(next) || (58...64).contains(next)
          || (91...96).contains(next) || (123...126).contains(next)
        {
          cursor += 1
        }
      }
      decoded.append(raw[cursor])
      cursor += 1
    }
    return String(decoding: decoded, as: UTF8.self)
  }

  private static func space(_ byte: UInt8) -> Bool {
    byte == 32 || byte == 9 || byte == 10 || byte == 13
  }
  deinit { cmark_syntax_extension_free(cmark_get_default_mem_allocator(), native) }
}
