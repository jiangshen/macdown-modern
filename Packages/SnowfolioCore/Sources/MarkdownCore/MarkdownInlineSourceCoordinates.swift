import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Maps native normalized inline buffers back to their physical source lines.
/// Native parsing owns the grammar. We require byte identity before using a map;
/// container prefixes, tabs and recursive inline contexts never need reparsing.
final class MarkdownInlineSourceCoordinates {
  private unowned let source: MarkdownSourceMetadata
  private struct Row {
    let delta: Int
    var expandedTabPrefix = 0
    var tab = 0
    var cell: UnsafeMutablePointer<cmark_node>?
    var cellOffset = 0

    func physical(_ offset: Int, end: Bool) -> Int? {
      if let cell {
        let physical = cmark_gfm_extensions_get_table_cell_source_offset(
          cell, Int32(offset + cellOffset), end)
        return physical >= 0 ? delta + Int(physical) : nil
      }
      return offset < expandedTabPrefix ? tab : delta + offset
    }

    func translated(by offset: Int) -> Self {
      Self(
        delta: cell == nil ? delta + offset : delta,
        expandedTabPrefix: max(0, expandedTabPrefix - offset), tab: tab,
        cell: cell, cellOffset: cellOffset + offset)
    }
  }
  private struct Context {
    let identity: UInt
    let line: Int
    let base: Int
    let input: UnsafeBufferPointer<UInt8>
    let lines: [Range<Int>]
    let rows: [Row?]
    var changesPositions: Bool {
      rows.contains { row in
        row.map { $0.cell != nil || $0.delta != base || $0.expandedTabPrefix > 0 } ?? false
      }
    }

    func physical(line: Int, column: Int, end: Bool = false) -> Int? {
      let row = line - self.line
      let offset = column - base - 1
      guard row >= 0, row < rows.count, offset >= 0, offset < lines[row].count,
        let mapping = rows[row]
      else { return nil }
      return mapping.physical(offset, end: end).map { $0 + 1 }
    }
  }
  // Native buffers are borrowed only within these balanced parse callbacks.
  private var contexts: [Context] = []
  private var parsedContexts = Set<UInt>()

  init(source: MarkdownSourceMetadata) { self.source = source }

  func observe(_ parent: UnsafeMutablePointer<cmark_node>, entering: Bool) {
    if entering {
      contexts.append(context(parent))
      return
    }
    guard let context = contexts.popLast(), context.identity == UInt(bitPattern: parent) else {
      return
    }
    defer {
      if contexts.isEmpty {
        parsedContexts.removeAll(keepingCapacity: true)
      } else {
        parsedContexts.insert(context.identity)
      }
    }
    guard context.changesPositions else { return }
    var current = parent.pointee.first_child
    while let node = current {
      if Task.isCancelled { return }
      if let column = context.physical(
        line: Int(node.pointee.start_line), column: Int(node.pointee.start_column))
      {
        node.pointee.start_column = Int32(column)
      }
      if let column = context.physical(
        line: Int(node.pointee.end_line), column: Int(node.pointee.end_column), end: true)
      {
        node.pointee.end_column = Int32(column)
      }
      // Recursive contexts have already mapped their descendants. Their wrapper
      // itself still belongs to this outer context and is reconciled above.
      if !parsedContexts.contains(UInt(bitPattern: node)), let child = node.pointee.first_child {
        current = child
      } else {
        var cursor = node
        while cursor.pointee.next == nil, let ancestor = cursor.pointee.parent,
          ancestor != parent
        { cursor = ancestor }
        current = cursor.pointee.next
      }
    }
  }

  private func context(_ parent: UnsafeMutablePointer<cmark_node>) -> Context {
    let content = parent.pointee.content
    let input = UnsafeBufferPointer(start: content.ptr, count: Int(content.size))
    let lines: [Range<Int>]
    if contexts.isEmpty, parent.pointee.start_line == parent.pointee.end_line {
      // Native finalized line bounds prove this is a single source line. Avoid
      // rescanning its bytes solely to rediscover the terminal line ending.
      var end = input.count
      while end > 0, input[end - 1] == 10 || input[end - 1] == 13 { end -= 1 }
      lines = [0..<end]
    } else {
      lines = MarkdownSourceMetadata.lineRanges(input)
    }
    let line = Int(parent.pointee.start_line)
    let base = Int(parent.pointee.start_column - 1 + parent.pointee.internal_offset)
    var rows: [Row?] = []
    rows.reserveCapacity(lines.count)
    for (index, range) in lines.enumerated() {
      guard !Task.isCancelled else {
        rows.append(nil)
        continue
      }
      let bytes = UnsafeBufferPointer(
        start: input.baseAddress.map { $0.advanced(by: range.lowerBound) }, count: range.count)
      if let outer = contexts.last {
        let outerRow = line + index - outer.line
        let offset = index == 0 ? base - outer.base : 0
        if outerRow >= 0, outerRow < outer.lines.count, offset >= 0,
          offset <= outer.lines[outerRow].count,
          bytes.count <= outer.lines[outerRow].count - offset,
          let mapping = outer.rows[outerRow]
        {
          let start = outer.lines[outerRow].lowerBound + offset
          if bytes.elementsEqual(outer.input[start..<(start + bytes.count)]) {
            rows.append(mapping.translated(by: offset))
            continue
          }
        }
        rows.append(nil)
      } else if index == 0,
        cmark_gfm_extensions_get_table_cell_source_offset(parent, 0, false) >= 0
      {
        rows.append(tableRow(bytes, parent: parent))
      } else {
        rows.append(rootRow(bytes, line: line + index, seed: index == 0 ? base : nil))
      }
    }
    return Context(
      identity: UInt(bitPattern: parent), line: line, base: base, input: input,
      lines: lines, rows: rows)
  }

  private func tableRow(
    _ normalized: UnsafeBufferPointer<UInt8>, parent: UnsafeMutablePointer<cmark_node>
  ) -> Row? {
    let line = Int(parent.pointee.start_line)
    let base = Int(parent.pointee.start_column - 1 + parent.pointee.internal_offset)
    guard line > 0, line <= source.lines.count, base >= 0, !normalized.isEmpty else { return nil }
    let physical = source.bytes[source.lines[line - 1]]
    let first = Int(cmark_gfm_extensions_get_table_cell_source_offset(parent, 0, false))
    let firstEnd = Int(cmark_gfm_extensions_get_table_cell_source_offset(parent, 0, true))
    let last = Int(
      cmark_gfm_extensions_get_table_cell_source_offset(
        parent, Int32(normalized.count - 1), true))
    // Trim-only cells remain a constant translation. Keep a borrowed native
    // sparse map only when recognized escaping made the translation nonlinear.
    if first == firstEnd, last - first == normalized.count - 1 {
      guard first >= 0, base + first <= physical.count,
        normalized.count <= physical.count - base - first,
        normalized.elementsEqual(physical.dropFirst(base + first).prefix(normalized.count))
      else { return nil }
      return Row(delta: base + first)
    }
    var count: Int32 = 0
    var trim: Int32 = 0
    let events = cmark_gfm_extensions_get_table_cell_source_escapes(parent, &count, &trim)
    let removed = UnsafeBufferPointer(start: events, count: Int(count))
    var consumed = 0
    for offset in normalized.indices {
      if offset.isMultiple(of: 4096), Task.isCancelled { return nil }
      let target = offset + Int(trim)
      while consumed < removed.count, Int(removed[consumed]) <= target { consumed += 1 }
      let mapped = base + target + consumed
      guard mapped >= 0, mapped < physical.count,
        normalized[offset] == physical[physical.startIndex + mapped]
      else { return nil }
    }
    return Row(delta: base, cell: parent)
  }

  private func rootRow(_ normalized: UnsafeBufferPointer<UInt8>, line: Int, seed: Int?) -> Row? {
    guard line > 0, line <= source.lines.count, !normalized.isEmpty else { return nil }
    let physical = source.bytes[source.lines[line - 1]]
    var leading = 0
    while leading < normalized.count, normalized[leading] == 32 || normalized[leading] == 9 {
      leading += 1
    }
    let body = normalized[leading...]
    guard !body.isEmpty else { return nil }
    let start: Int
    if body.count <= physical.count, physical.suffix(body.count).elementsEqual(body) {
      start = physical.count - body.count
    } else if let seed, seed >= 0, seed + leading <= physical.count,
      body.count <= physical.count - seed - leading,
      physical.dropFirst(seed + leading).prefix(body.count).elementsEqual(body)
    {
      // ATX headings and table cells can end before the physical line does.
      // Use their native origin only when the complete fragment agrees there.
      start = seed + leading
    } else {
      return nil
    }
    let linear = start - leading
    if linear >= 0,
      physical.dropFirst(linear).prefix(leading).elementsEqual(normalized[..<leading])
    {
      return Row(delta: linear)
    }
    // add_line can replace the unconsumed part of one leading tab with 1–3
    // spaces. The remaining bytes must match exactly; all synthetic spaces
    // point at that single physical tab byte.
    for expanded in 1...3 where expanded <= leading {
      let tab = start - (leading - expanded) - 1
      guard tab >= 0, physical[physical.startIndex + tab] == 9,
        normalized[..<expanded].allSatisfy({ $0 == 32 }),
        physical.dropFirst(tab + 1).prefix(leading - expanded)
          .elementsEqual(normalized[expanded..<leading])
      else { continue }
      return Row(delta: linear, expandedTabPrefix: expanded, tab: tab)
    }
    return nil
  }
}
