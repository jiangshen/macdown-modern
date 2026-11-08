import CryptoKit
import Darwin
import Foundation
import MarkdownCore
import cmark_gfm
import cmark_gfm_extensions

/// Development-only comparison. MD4C is loaded from an explicitly supplied local
/// library and is never a production package dependency or application resource.
@main
struct EngineComparisonAudit {
  typealias OutputCallback =
    @convention(c) (
      UnsafePointer<CChar>?, UInt32, UnsafeMutableRawPointer?
    ) -> Void
  typealias MDHTML =
    @convention(c) (
      UnsafePointer<CChar>?, UInt32, OutputCallback?, UnsafeMutableRawPointer?, UInt32, UInt32
    ) -> Int32

  private final class Output {
    var bytes = Data()
  }

  private final class CandidateLibrary {
    let handle: UnsafeMutableRawPointer
    let html: MDHTML
    init(path: String) throws {
      guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
        throw failure("Cannot load candidate library")
      }
      guard let symbol = dlsym(handle, "md_html") else {
        dlclose(handle)
        throw failure("Candidate has no md_html entry point")
      }
      self.handle = handle
      html = unsafeBitCast(symbol, to: MDHTML.self)
    }
    deinit { dlclose(handle) }
  }

  static func failure(_ message: String) -> NSError {
    NSError(
      domain: "EngineComparisonAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  static func cmarkHTML(_ input: Data, gfm: Bool) throws -> Data {
    let flags = CMARK_OPT_UNSAFE | CMARK_OPT_VALIDATE_UTF8 | (gfm ? CMARK_OPT_FOOTNOTES : 0)
    guard let parser = cmark_parser_new(flags) else { throw failure("Parser allocation") }
    defer { cmark_parser_free(parser) }
    if gfm {
      for name in ["table", "strikethrough", "tasklist", "autolink"] {
        guard let ext = cmark_find_syntax_extension(name) else {
          throw failure("Missing core extension")
        }
        cmark_parser_attach_syntax_extension(parser, ext)
      }
    }
    input.withUnsafeBytes { bytes in
      if let base = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) {
        cmark_parser_feed(parser, base, input.count)
      }
    }
    guard let root = cmark_parser_finish(parser) else { throw failure("Parser finish") }
    defer { cmark_node_free(root) }
    guard let html = cmark_render_html(root, flags, cmark_parser_get_syntax_extensions(parser))
    else {
      throw failure("HTML allocation")
    }
    defer { free(html) }
    return Data(bytes: html, count: strlen(html))
  }

  private static func candidateHTML(_ input: Data, library: CandidateLibrary, gfm: Bool) throws
    -> Data
  {
    guard input.count <= UInt32.max else { throw failure("Candidate input size") }
    let output = Output()
    let callback: OutputCallback = { text, count, context in
      guard let text, let context else { return }
      let output = Unmanaged<Output>.fromOpaque(context).takeUnretainedValue()
      output.bytes.append(
        UnsafeRawPointer(text).assumingMemoryBound(to: UInt8.self), count: Int(count))
    }
    let context = Unmanaged.passUnretained(output).toOpaque()
    // Match tables/strike/tasks/autolinks/footnotes. Admonitions stay disabled in
    // both bare-engine modes. XHTML formatting matches cmark's core HTML style.
    let parserFlags: UInt32 = gfm ? 0x100F0C : 0
    let status = input.withUnsafeBytes { bytes in
      library.html(
        bytes.baseAddress?.assumingMemoryBound(to: CChar.self), UInt32(input.count),
        callback, context, parserFlags, 0x0008)
    }
    guard status == 0 else { throw failure("Candidate parser status \(status)") }
    return output.bytes
  }

  static func milliseconds(_ duration: Duration) -> Double {
    let value = duration.components
    return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
  }

  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 3, ["cmark", "md4c", "snowfolio"].contains(args[0]),
      ["commonmark", "gfm"].contains(args[1])
    else {
      throw failure(
        "Usage: EngineComparisonAudit ENGINE DIALECT --html | FILE ITERATIONS; MD4C_LIBRARY supplies the optional candidate path"
      )
    }
    let engine = args[0]
    let gfm = args[1] == "gfm"
    let candidate =
      try engine == "md4c"
      ? CandidateLibrary(path: ProcessInfo.processInfo.environment["MD4C_LIBRARY"] ?? "") : nil
    cmark_gfm_core_extensions_ensure_registered()
    let processor = MarkdownProcessor()
    if args[2] == "--html" {
      let input = try FileHandle.standardInput.readToEnd() ?? Data()
      let html: Data
      if let candidate {
        html = try candidateHTML(input, library: candidate, gfm: gfm)
      } else if engine == "cmark" {
        html = try cmarkHTML(input, gfm: gfm)
      } else {
        throw failure("Snowfolio full mode is measured separately from core conformance")
      }
      FileHandle.standardOutput.write(html)
      return
    }
    guard args.count == 4, let iterations = Int(args[3]), (1...100).contains(iterations) else {
      throw failure("Expected FILE ITERATIONS")
    }
    let sourceBytes = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    guard let source = String(data: sourceBytes, encoding: .utf8) else {
      throw failure("Expected UTF-8 benchmark input")
    }
    let clock = ContinuousClock()
    var timings: [Double] = []
    var outputBytes = 0
    var digest = ""
    var nodes = 0
    var parentDigest = ""
    for index in 0...iterations {
      let text = source + "\n\nCheckpoint \(index)"
      let input = Data(text.utf8)
      let start = clock.now
      let html: Data
      if let candidate {
        html = try candidateHTML(input, library: candidate, gfm: gfm)
      } else if engine == "cmark" {
        html = try cmarkHTML(input, gfm: gfm)
      } else {
        let result = try await processor.render(text, includeSyntax: true)
        html = Data(result.html.utf8)
        nodes = result.nodes.count
        let duration = milliseconds(start.duration(to: clock.now))
        timings.append(duration)
        if index == iterations {
          var hash = SHA256()
          for node in result.nodes {
            var id = Int64(node.id).littleEndian
            var parent = Int64(node.parentID ?? -1).littleEndian
            withUnsafeBytes(of: &id) { hash.update(bufferPointer: $0) }
            withUnsafeBytes(of: &parent) { hash.update(bufferPointer: $0) }
          }
          parentDigest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        outputBytes = html.count
        digest = SHA256.hash(data: html).map { String(format: "%02x", $0) }.joined()
        continue
      }
      timings.append(milliseconds(start.duration(to: clock.now)))
      outputBytes = html.count
      digest = SHA256.hash(data: html).map { String(format: "%02x", $0) }.joined()
    }
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw failure("getrusage") }
    let warm = Array(timings.dropFirst()).sorted()
    let record: [String: Any] = [
      "engine": engine, "dialect": args[1], "inputBytes": sourceBytes.count,
      "iterations": iterations, "coldMilliseconds": timings[0],
      "warmMilliseconds": Array(timings.dropFirst()),
      "warmMedianMilliseconds": warm[warm.count / 2],
      "processPeakResidentBytes": usage.ru_maxrss,
      "htmlBytes": outputBytes, "htmlSHA256": digest, "nodes": nodes,
      "parentIDsSHA256": parentDigest,
      "scope": engine == "snowfolio"
        ? "Full current Swift pipeline including syntax, AST, feature decoration and highlighting; excludes WebKit/UI/file IO"
        : "Bare parse plus HTML/output buffer; no source ranges, AST transfer, app features, highlighting or UI"
        ,
    ]
    let encoded = try JSONSerialization.data(
      withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: encoded, as: UTF8.self))
  }
}
