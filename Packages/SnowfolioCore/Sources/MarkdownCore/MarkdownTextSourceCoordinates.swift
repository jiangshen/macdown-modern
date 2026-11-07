import Foundation
import cmark_gfm

/// Owned provenance for native decoded text. No native pointer survives a callback.
/// Grammar recognition and text partitioning remain in the native extension.
final class MarkdownTextSourceCoordinates {
  final class Row {
    let delta: Int
    let expandedTabPrefix: Int
    let tab: Int
    let escapes: [Int32]?
    let trim: Int
    let cellOffset: Int

    init(
      delta: Int, expandedTabPrefix: Int, tab: Int, escapes: [Int32]? = nil,
      trim: Int = 0, cellOffset: Int = 0
    ) {
      self.delta = delta
      self.expandedTabPrefix = expandedTabPrefix
      self.tab = tab
      self.escapes = escapes
      self.trim = trim
      self.cellOffset = cellOffset
    }

    func physical(_ offset: Int, end: Bool) -> Int {
      if let escapes {
        let target = offset + cellOffset + trim
        var lower = 0
        var upper = escapes.count
        while lower < upper {
          let middle = lower + (upper - lower) / 2
          let event = Int(escapes[middle])
          if event < target || (end && event == target) {
            lower = middle + 1
          } else {
            upper = middle
          }
        }
        return delta + target + lower
      }
      return offset < expandedTabPrefix ? tab : delta + offset
    }
  }

  struct Piece {
    enum Mapping {
      case bytes(line: Int, offset: Int, row: Row)
      case atom(MarkdownSourceRange)
    }
    let range: Range<Int>
    let mapping: Mapping

    func position(_ offset: Int, end: Bool) -> MarkdownSourcePosition {
      switch mapping {
      case .bytes(let line, let start, let row):
        return .init(
          line: line, column: row.physical(start + offset - range.lowerBound, end: end) + 1)
      case .atom(let source): return end ? source.end : source.start
      }
    }
  }

  struct Origin {
    let startLine: Int32
    let startColumn: Int32
    let endLine: Int32
    let endColumn: Int32

    func matches(_ node: UnsafeMutablePointer<cmark_node>) -> Bool {
      node.pointee.start_line == startLine && node.pointee.start_column == startColumn
        && node.pointee.end_line == endLine && node.pointee.end_column == endColumn
    }
  }

  struct Map {
    let origin: Origin
    let bytes: [UInt8]
    let pieces: [Piece]

    private func piece(_ offset: Int) -> Piece? {
      var lower = 0
      var upper = pieces.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if pieces[middle].range.upperBound <= offset { lower = middle + 1 } else { upper = middle }
      }
      guard lower < pieces.count, pieces[lower].range.contains(offset) else { return nil }
      return pieces[lower]
    }

    func source(_ range: Range<Int>) -> MarkdownSourceRange? {
      guard !range.isEmpty, range.lowerBound >= 0, range.upperBound <= bytes.count,
        let first = piece(range.lowerBound), let last = piece(range.upperBound - 1)
      else { return nil }
      let start = first.position(range.lowerBound, end: false)
      let end = last.position(range.upperBound - 1, end: true)
      guard start.line > 0, start.column > 0,
        end.line > start.line || (end.line == start.line && end.column >= start.column)
      else { return nil }
      return .init(start: start, end: end)
    }
  }

  private var pending: [UInt: Map] = [:]
  private var active: (identity: UInt, map: Map)?

  func remember(_ map: Map, for node: UnsafeMutablePointer<cmark_node>) {
    pending[UInt(bitPattern: node)] = map
  }

  func observe(_ event: cmark_text_source_event) {
    guard let origin = event.origin else { return }
    let identity = UInt(bitPattern: origin)
    switch event.phase {
    case CMARK_TEXT_SOURCE_BEGIN:
      active = nil
      guard !Task.isCancelled, let map = pending.removeValue(forKey: identity),
        map.origin.matches(origin), event.length == map.bytes.count, let data = event.literal,
        UnsafeBufferPointer(start: data, count: Int(event.length)).elementsEqual(map.bytes)
      else { return }
      // Validate once for the complete immutable native buffer. Subsequent
      // partitions use its recognized offsets, avoiding repeated suffix scans.
      active = (identity, map)
    case CMARK_TEXT_SOURCE_PARTITION:
      guard !Task.isCancelled, let active, active.identity == identity,
        event.start >= 0, event.lower >= event.start, event.upper >= event.lower,
        event.upper <= active.map.bytes.count
      else { return }
      let start = Int(event.start)
      let lower = Int(event.lower)
      let upper = Int(event.upper)
      set(event.prefix, source: active.map.source(start..<lower))
      let middle = active.map.source(lower..<upper)
      set(event.middle, source: middle)
      set(event.middle_text, source: middle)
      set(event.suffix, source: active.map.source(upper..<active.map.bytes.count))
    case CMARK_TEXT_SOURCE_END:
      if active?.identity == identity { active = nil }
    default: break
    }
  }

  private func set(_ node: UnsafeMutablePointer<cmark_node>?, source: MarkdownSourceRange?) {
    guard let node else { return }
    node.pointee.start_line = Int32(source?.start.line ?? 0)
    node.pointee.start_column = Int32(source?.start.column ?? 0)
    node.pointee.end_line = Int32(source?.end.line ?? 0)
    node.pointee.end_column = Int32(source?.end.column ?? 0)
  }

  func finish() {
    active = nil
    pending.removeAll()
  }
}
