import Darwin
import Foundation
import MarkdownCore

/// Development-only full-render measurements; never linked into the GUI application.
@main
struct PerformanceAudit {
  static func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
  }

  static func main() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 3, let bytes = Int(arguments[1]),
      (1_000...10_000_000).contains(bytes), let iterations = Int(arguments[2]),
      (1...100).contains(iterations),
      ["prose", "mixed", "long-line", "escaped-cell"].contains(arguments[0])
    else {
      throw NSError(
        domain: "PerformanceAudit", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Usage: PerformanceAudit prose|mixed|long-line|escaped-cell BYTES ITERATIONS"
        ])
    }
    let workload = arguments[0]
    let unit: String
    switch workload {
    case "mixed":
      unit = """
        ## A notebook section

        Local **Markdown** with _emphasis_, [a link](https://example.invalid), Unicode 中文 👩‍💻 and `inline code`.

        1. First item
        2. Second item

        > [!NOTE]
        > An offline callout with text.

        | Column | Value |
        | --- | --- |
        | One | Two |

        ```swift
        let title = "Snowfolio"
        print(title)
        ```

        """ + "\n"
    case "escaped-cell": unit = "a\\|"
    case "long-line": unit = "Unicode 中文 👩‍💻 **bold** and `code` in a long paragraph. "
    default: unit = "A calm paragraph of plain text for writing and reading, with Unicode 中文 👩‍💻.\n\n"
    }
    let unitBytes = unit.utf8.count
    var source: String
    if workload == "escaped-cell" {
      let header = "| Header | Other |\n|---|---|\n|"
      let trailer = " **target** | value |\n"
      let payload = bytes - header.utf8.count - trailer.utf8.count
      source =
        header + String(repeating: unit, count: payload / unitBytes)
        + String(repeating: "x", count: payload % unitBytes) + trailer
    } else {
      source = String(repeating: unit, count: bytes / unitBytes)
      source += String(repeating: "x", count: bytes - source.utf8.count)
    }
    let processor = MarkdownProcessor()
    let clock = ContinuousClock()
    var timings: [Double] = []
    var nodeCount = 0
    var syntaxRunCount = 0
    var htmlBytes = 0
    for index in 0...iterations {
      // Each measured warm pass is a full rerender after a small source edit.
      let input = source + "\n\nCheckpoint \(index)"
      let start = clock.now
      let result = try await processor.render(input, includeSyntax: true)
      timings.append(milliseconds(start.duration(to: clock.now)))
      guard !result.html.isEmpty, let syntax = result.syntax else {
        throw NSError(domain: "PerformanceAudit", code: 2)
      }
      nodeCount = result.nodes.count
      syntaxRunCount = syntax.runs.count
      htmlBytes = result.html.utf8.count
    }
    let warm = Array(timings.dropFirst()).sorted()
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else {
      throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let record: [String: Any] = [
      "workload": workload, "fixtureBytes": source.utf8.count,
      "iterations": iterations, "coldMilliseconds": timings[0],
      "warmMilliseconds": Array(timings.dropFirst()),
      "warmMedianMilliseconds": warm[warm.count / 2],
      "warmMaxMilliseconds": warm.last ?? 0,
      "processPeakResidentBytes": usage.ru_maxrss,
      "nodes": nodeCount, "syntaxRuns": syntaxRunCount, "htmlBytes": htmlBytes,
      "scope":
        "Release arm64 full MarkdownProcessor render with source syntax; excludes UI layout, WebKit publication, file IO, math and diagrams",
      "os": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    let data = try JSONSerialization.data(
      withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
  }
}
