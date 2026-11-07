import Foundation
import cmark_gfm

/// Owned coordinate projection for a normalization actually observed in native
/// input. Original bytes remain intact; only affected line bodies are expanded.
final class MarkdownInputSourceProjection {
  private struct Line {
    let bytes: [UInt8]
    let replacements: [Int]

    func column(_ column: Int) -> Int {
      guard column > 0 else { return column }
      let offset = column - 1
      var lower = 0
      var upper = replacements.count
      while lower < upper {
        let middle = lower + (upper - lower) / 2
        if replacements[middle] <= offset { lower = middle + 1 } else { upper = middle }
      }
      if lower > 0, offset < replacements[lower - 1] + 3 {
        return replacements[lower - 1] - 2 * (lower - 1) + 1
      }
      return column - 2 * lower
    }
  }

  private let affected: [Int: Line]

  init?(bytes: [UInt8], lines: [Range<Int>]) {
    var affected: [Int: Line] = [:]
    for (index, range) in lines.enumerated() {
      if Task.isCancelled { return nil }
      let raw = bytes[range]
      let hasNUL = raw.withUnsafeBufferPointer { buffer in
        buffer.baseAddress.map { memchr($0, 0, buffer.count) != nil } ?? false
      }
      guard hasNUL else { continue }
      var zeros: [Int] = []
      for offset in raw.indices {
        if offset.isMultiple(of: 4096), Task.isCancelled { return nil }
        if raw[offset] == 0 { zeros.append(offset) }
      }
      if Task.isCancelled { return nil }
      var normalized: [UInt8] = []
      normalized.reserveCapacity(raw.count + 2 * zeros.count)
      var replacements: [Int] = []
      replacements.reserveCapacity(zeros.count)
      var start = raw.startIndex
      for offset in zeros {
        if replacements.count.isMultiple(of: 4096), Task.isCancelled { return nil }
        normalized.append(contentsOf: raw[start..<offset])
        replacements.append(normalized.count)
        normalized.append(contentsOf: [239, 191, 189])
        start = offset + 1
      }
      normalized.append(contentsOf: raw[start...])
      affected[index + 1] = Line(bytes: normalized, replacements: replacements)
    }
    guard !affected.isEmpty else { return nil }
    self.affected = affected
  }

  func nativeLine(_ line: Int) -> ArraySlice<UInt8>? {
    affected[line].map { $0.bytes[...] }
  }

  func position(_ position: MarkdownSourcePosition) -> MarkdownSourcePosition {
    guard let line = affected[position.line] else { return position }
    return .init(line: position.line, column: line.column(position.column))
  }

  func range(_ range: MarkdownSourceRange) -> MarkdownSourceRange {
    .init(start: position(range.start), end: position(range.end))
  }

  /// Called in the existing AST traversal, after every native postprocessor.
  /// Native internal offsets are no longer consumed by parsing at this point.
  func project(_ node: UnsafeMutablePointer<cmark_node>) {
    if let line = affected[Int(node.pointee.start_line)] {
      node.pointee.start_column = Int32(line.column(Int(node.pointee.start_column)))
    }
    if let line = affected[Int(node.pointee.end_line)] {
      node.pointee.end_column = Int32(line.column(Int(node.pointee.end_column)))
    }
  }
}
