import Foundation
import cmark_gfm

/// Development-only core parser probe; the application does not link this target.
@main
struct ParserAudit {
  static func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.allSatisfy({ $0 == "--unsafe" }) else {
      FileHandle.standardError.write(Data("Usage: cmark-audit [--unsafe]\n".utf8))
      exit(64)
    }
    let input = try FileHandle.standardInput.readToEnd() ?? Data()
    let flags = Int32(arguments.contains("--unsafe") ? CMARK_OPT_UNSAFE : 0)
    guard let parser = cmark_parser_new(flags) else { exit(70) }
    defer { cmark_parser_free(parser) }
    input.withUnsafeBytes { bytes in
      if let pointer = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) {
        cmark_parser_feed(parser, pointer, input.count)
      }
    }
    guard let root = cmark_parser_finish(parser) else { exit(70) }
    defer { cmark_node_free(root) }
    guard let html = cmark_render_html(root, flags, nil) else { exit(70) }
    defer { free(html) }
    FileHandle.standardOutput.write(Data(String(cString: html).utf8))
  }
}
