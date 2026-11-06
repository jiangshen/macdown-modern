public enum LineEnding: String, Sendable {
    case lineFeed = "\n"
    case crlf = "\r\n"
    case carriageReturn = "\r"
}

/// Source conventions for new editing operations. Existing line breaks stay untouched.
public struct LineEndingProfile: Equatable, Sendable {
    public private(set) var lineFeedCount = 0
    public private(set) var crlfCount = 0
    public private(set) var carriageReturnCount = 0
    public let preferred: LineEnding

    public var isMixed: Bool {
        [lineFeedCount, crlfCount, carriageReturnCount].filter { $0 > 0 }.count > 1
    }

    public init(text: String) {
        var first: LineEnding?
        var pendingCarriageReturn = false
        // Streaming UTF-8 traversal avoids a second document-sized array. CR/LF bytes
        // cannot occur inside multi-byte UTF-8 code points.
        for byte in text.utf8 {
            if pendingCarriageReturn {
                pendingCarriageReturn = false
                if byte == 0x0A {
                    crlfCount += 1
                    first = first ?? .crlf
                    continue
                }
                carriageReturnCount += 1
                first = first ?? .carriageReturn
            }
            if byte == 0x0D {
                pendingCarriageReturn = true
            } else if byte == 0x0A {
                lineFeedCount += 1
                first = first ?? .lineFeed
            }
        }
        if pendingCarriageReturn {
            carriageReturnCount += 1
            first = first ?? .carriageReturn
        }
        let counts: [(LineEnding, Int)] = [(.lineFeed, lineFeedCount), (.crlf, crlfCount),
                                           (.carriageReturn, carriageReturnCount)]
        let maximum = counts.map(\.1).max() ?? 0
        if let first, counts.contains(where: { $0.0 == first && $0.1 == maximum }) {
            preferred = first
        } else {
            preferred = counts.first(where: { $0.1 == maximum })?.0 ?? .lineFeed
        }
    }
}
