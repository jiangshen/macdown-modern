import Foundation
import cmark_gfm

/// Observes bytes already recognized by the native block parser. No source is
/// rewritten and no reference-definition grammar is duplicated in Swift.
final class MarkdownSourceMetadata {
  struct Definition {
    enum Kind { case reference, note }
    let kind: Kind
    let range: MarkdownSourceRange
    let quoted: Bool
    let inNote: Bool
  }

  let native: UnsafeMutablePointer<cmark_syntax_extension>
  private let source: String
  private(set) lazy var bytes = Array(source.utf8)
  private(set) lazy var lines = Self.lineRanges(bytes)
  private lazy var inlineCoordinates = MarkdownInlineSourceCoordinates(source: self)
  private(set) var inputProjection: MarkdownInputSourceProjection?
  private let collectDefinitions: Bool
  private(set) var definitions: [Definition] = []

  init(source: String, collectDefinitions: Bool) throws {
    self.collectDefinitions = collectDefinitions
    self.source = source
    guard let extensionPointer = cmark_syntax_extension_new("snowfolio_source_metadata") else {
      throw MarkdownRenderingError.allocationFailure
    }
    native = extensionPointer
    cmark_syntax_extension_set_private(native, Unmanaged.passUnretained(self).toOpaque(), nil)
    cmark_syntax_extension_set_inline_source_func(native) { extensionPointer, parent, entering in
      guard let extensionPointer, let parent,
        let pointer = cmark_syntax_extension_get_private(extensionPointer)
      else { return }
      Unmanaged<MarkdownSourceMetadata>.fromOpaque(pointer).takeUnretainedValue()
        .inlineCoordinates.observe(parent, entering: entering != 0)
    }
    cmark_syntax_extension_set_block_split_func(native) {
      extensionPointer, node, prefix, consumed in
      guard let extensionPointer, let node, let prefix,
        let pointer = cmark_syntax_extension_get_private(extensionPointer)
      else { return }
      Unmanaged<MarkdownSourceMetadata>.fromOpaque(pointer).takeUnretainedValue()
        .inlineCoordinates.split(node, prefix: prefix, consumed: Int(consumed))
    }
    cmark_syntax_extension_set_text_source_func(native) { extensionPointer, event in
      guard let extensionPointer, let event,
        let pointer = cmark_syntax_extension_get_private(extensionPointer)
      else { return }
      Unmanaged<MarkdownSourceMetadata>.fromOpaque(pointer).takeUnretainedValue()
        .inlineCoordinates.textSources.observe(event.pointee)
    }
    cmark_syntax_extension_set_input_source_func(native) {
      extensionPointer, original, originalSize, normalized, normalizedSize in
      guard let extensionPointer, let original, let normalized,
        originalSize == 1, original[0] == 0, normalizedSize == 3,
        normalized[0] == 239, normalized[1] == 191, normalized[2] == 189,
        let pointer = cmark_syntax_extension_get_private(extensionPointer)
      else { return }
      let owner = Unmanaged<MarkdownSourceMetadata>.fromOpaque(pointer).takeUnretainedValue()
      if owner.inputProjection == nil {
        owner.inputProjection = MarkdownInputSourceProjection(
          bytes: owner.bytes, lines: owner.lines)
      }
    }
    if collectDefinitions {
      cmark_syntax_extension_set_block_source_func(native) { extensionPointer, node in
        guard let extensionPointer, let node,
          let pointer = cmark_syntax_extension_get_private(extensionPointer)
        else { return }
        Unmanaged<MarkdownSourceMetadata>.fromOpaque(pointer).takeUnretainedValue().observe(node)
      }
    }
    cmark_syntax_extension_set_source_prefix_func(native) {
      extensionPointer, parser, node, consumed in
      guard let extensionPointer, let parser, let node,
        let pointer = cmark_syntax_extension_get_private(extensionPointer)
      else { return }
      Unmanaged<MarkdownSourceMetadata>.fromOpaque(pointer).takeUnretainedValue()
        .consume(node, count: Int(consumed), parser: parser)
    }
  }

  deinit { cmark_syntax_extension_free(cmark_get_default_mem_allocator(), native) }

  func nativeLine(_ line: Int) -> ArraySlice<UInt8> {
    if let projected = inputProjection?.nativeLine(line) { return projected }
    guard line > 0, line <= lines.count else { return bytes[0..<0] }
    return bytes[lines[line - 1]]
  }

  func finishParsing() {
    inlineCoordinates.textSources.finish()
    if let inputProjection {
      definitions = definitions.map {
        .init(
          kind: $0.kind, range: inputProjection.range($0.range), quoted: $0.quoted,
          inNote: $0.inNote)
      }
    }
  }

  private func observe(_ node: UnsafeMutablePointer<cmark_node>) {
    guard cmark_node_get_type(node) == CMARK_NODE_FOOTNOTE_DEFINITION else { return }
    let firstLine = Int(node.pointee.start_line)
    let lastLine = Int(node.pointee.end_line)
    let firstColumn = Int(node.pointee.start_column - node.pointee.internal_offset)
    let first = nativeLine(firstLine)
    guard firstLine > 0, lastLine >= firstLine, lastLine <= lines.count,
      firstColumn > 0, firstColumn + 1 <= first.count
    else { return }
    let marker = first.startIndex + firstColumn - 1
    // Prefix length comes from the native scanner, not a second note grammar.
    guard first[marker] == 91, first[marker + 1] == 94 else { return }
    var quoted = false
    var parent = cmark_node_parent(node)
    while let current = parent {
      if cmark_node_get_type(current) == CMARK_NODE_BLOCK_QUOTE { quoted = true }
      parent = cmark_node_parent(current)
    }
    definitions.append(
      .init(
        kind: .note,
        range: .init(
          start: .init(line: firstLine, column: firstColumn),
          end: .init(line: lastLine, column: Int(node.pointee.end_column))),
        quoted: quoted, inNote: true))
  }

  private func consume(
    _ node: UnsafeMutablePointer<cmark_node>, count: Int,
    parser: UnsafeMutablePointer<cmark_parser>
  ) {
    let buffer = node.pointee.content
    guard let data = buffer.ptr, count > 0, count <= Int(buffer.size) else { return }
    let content = UnsafeBufferPointer(start: data, count: Int(buffer.size))
    let firstLine = Int(node.pointee.start_line)
    guard firstLine > 0, firstLine <= lines.count else { return }
    var removedLines = 0
    var cursor = 0
    while cursor < count {
      if content[cursor] == 13 {
        removedLines += 1
        if cursor + 1 < count, content[cursor + 1] == 10 { cursor += 1 }
      } else if content[cursor] == 10 {
        removedLines += 1
      }
      cursor += 1
    }
    if collectDefinitions {
      let lastLine = min(lines.count, firstLine + max(1, removedLines) - 1)
      var quoted = false
      var inNote = false
      var parent = cmark_node_parent(node)
      while let current = parent {
        if cmark_node_get_type(current) == CMARK_NODE_BLOCK_QUOTE { quoted = true }
        if cmark_node_get_type(current) == CMARK_NODE_FOOTNOTE_DEFINITION { inNote = true }
        parent = cmark_node_parent(current)
      }
      definitions.append(
        .init(
          kind: .reference,
          range: .init(
            start: .init(line: firstLine, column: Int(node.pointee.start_column)),
            end: .init(line: lastLine, column: nativeLine(lastLine).count)), quoted: quoted,
          inNote: inNote))
    }
    guard removedLines > 0 else { return }
    let bodyLine = firstLine + removedLines
    guard bodyLine > 0, bodyLine <= lines.count else { return }
    let physical = nativeLine(bodyLine)
    let column: Int
    if count == content.count {
      // Resolving references while testing a setext line can consume the entire
      // buffered paragraph, which remains open for that current line. Rebase
      // only when native line identity and the complete physical bytes agree.
      let current = parser.pointee.curline
      guard Int(parser.pointee.line_number) == bodyLine, let data = current.ptr else { return }
      let nativeLine = UnsafeBufferPointer(start: data, count: Int(current.size))
      var end = nativeLine.count
      while end > 0, nativeLine[end - 1] == 10 || nativeLine[end - 1] == 13 { end -= 1 }
      guard physical.elementsEqual(nativeLine[..<end]) else { return }
      column = Int(parser.pointee.first_nonspace) + 1
      guard column > 0, column <= physical.count else { return }
    } else {
      // Native add_line has already removed container prefixes and indentation.
      // Its first remaining content line must be the physical source line's suffix.
      var end = count
      while end < content.count, content[end] != 10, content[end] != 13 { end += 1 }
      let body = content[count..<end]
      guard !body.isEmpty, body.count <= physical.count,
        physical.suffix(body.count).elementsEqual(body)
      else { return }
      column = physical.count - body.count + 1
    }
    node.pointee.start_line = Int32(bodyLine)
    node.pointee.start_column = Int32(column)
  }

  static func lineRanges<C: RandomAccessCollection>(_ bytes: C) -> [Range<Int>]
  where C.Element == UInt8, C.Index == Int {
    var result: [Range<Int>] = []
    var start = bytes.startIndex
    var cursor = start
    while cursor < bytes.endIndex {
      if bytes[cursor] == 10 || bytes[cursor] == 13 {
        result.append(start..<cursor)
        if bytes[cursor] == 13, cursor + 1 < bytes.endIndex, bytes[cursor + 1] == 10 { cursor += 1 }
        start = cursor + 1
      }
      cursor += 1
    }
    result.append(start..<bytes.endIndex)
    return result
  }
}
