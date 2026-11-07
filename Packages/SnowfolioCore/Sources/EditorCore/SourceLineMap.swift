import Foundation

/// One-based source lines and UTF-16 offsets; CR, LF and CRLF each end one line.
public struct SourceLineMap: Sendable {
  public let lineStarts: [Int]
  public let utf16Length: Int

  public init(_ source: String) {
    var starts = [0]
    var offset = 0
    var previousCR = false
    for unit in source.utf16 {
      if unit == 10, previousCR {
        starts[starts.count - 1] = offset + 1
      } else if unit == 10 || unit == 13 {
        starts.append(offset + 1)
      }
      previousCR = unit == 13
      offset += 1
    }
    lineStarts = starts
    utf16Length = offset
  }

  /// A fractional line expresses progress within a logical source line.
  public func linePosition(atUTF16Offset offset: Int) -> Double {
    let offset = min(utf16Length, max(0, offset))
    var low = 0
    var high = lineStarts.count
    while low < high {
      let middle = (low + high) / 2
      if lineStarts[middle] <= offset { low = middle + 1 } else { high = middle }
    }
    let index = max(0, low - 1)
    let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : utf16Length
    let span = max(1, end - lineStarts[index])
    return Double(index + 1) + Double(offset - lineStarts[index]) / Double(span)
  }

  /// Returns a UTF-16 coordinate, not a selection. UI callers normalize surrogate
  /// boundaries before asking the text system to reveal the resulting position.
  public func utf16Offset(atLinePosition position: Double) -> Int {
    guard position.isFinite else { return 0 }
    let value = min(Double(lineStarts.count + 1), max(1, position))
    let index = min(lineStarts.count - 1, Int(value.rounded(.down)) - 1)
    let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : utf16Length
    let fraction = min(1, max(0, value - Double(index + 1)))
    return lineStarts[index] + Int((Double(end - lineStarts[index]) * fraction).rounded(.down))
  }
}

public struct MarkdownScrollPosition: Codable, Equatable, Sendable {
  public let line: Double
  public let atTop: Bool
  public let atBottom: Bool

  public init(line: Double, atTop: Bool = false, atBottom: Bool = false) {
    self.line = line
    self.atTop = atTop
    self.atBottom = atBottom
  }

  public var isValid: Bool { line.isFinite && line >= 1 }
}
