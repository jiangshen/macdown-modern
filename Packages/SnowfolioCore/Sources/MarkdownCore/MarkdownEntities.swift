import cmark_gfm

/// Reuses the native entity decoder only within AST-confirmed text. Code, HTML,
/// destinations and other opaque native tokens never reach this scanner.
enum MarkdownEntities {
  static func ranges(in bytes: [UInt8], within range: Range<Int>) throws -> [Range<Int>] {
    guard bytes[range].contains(38) else { return [] }
    var buffer = cmark_strbuf()
    cmark_strbuf_init(cmark_get_default_mem_allocator(), &buffer, 0)
    defer { cmark_strbuf_free(&buffer) }
    return try bytes.withUnsafeBufferPointer { source in
      guard let base = source.baseAddress else { return [] }
      var result: [Range<Int>] = []
      var cursor = range.lowerBound
      var backslashes = 0
      // Native text may begin after a separately emitted escape node.
      var prefix = cursor
      while prefix > 0, bytes[prefix - 1] == 92 {
        prefix -= 1
        backslashes += 1
      }
      while cursor < range.upperBound {
        if cursor.isMultiple(of: 4096) { try Task.checkCancellation() }
        let byte = bytes[cursor]
        if byte == 38, backslashes.isMultiple(of: 2) {
          cmark_strbuf_clear(&buffer)
          // Native named entities have a maximum of 32 bytes after '&'. This
          // window also bounds failed numeric scans and includes every valid
          // decimal (7 digits) or hexadecimal (6 digits) entity.
          let length = min(32, range.upperBound - cursor - 1)
          let consumed = Int(houdini_unescape_ent(&buffer, base + cursor + 1, Int32(length)))
          if consumed > 0 {
            result.append(cursor..<(cursor + consumed + 1))
            cursor += consumed + 1
            backslashes = 0
            continue
          }
        }
        backslashes = byte == 92 ? backslashes + 1 : 0
        cursor += 1
      }
      return result
    }
  }
}
