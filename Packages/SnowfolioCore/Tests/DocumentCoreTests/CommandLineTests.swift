import Carbon
import Foundation
import Testing

@testable import DocumentCore

@Suite("Command-line requests")
struct CommandLineTests {
  private let directory = URL(fileURLWithPath: "/tmp/cli folder", isDirectory: true)

  @Test(
    "Help and version preserve the original precedence",
    arguments: [
      ["-h"], ["--help"], ["-v", "-h"], ["--help", "--version"],
    ])
  func help(arguments: [String]) throws {
    #expect(try CommandLineInvocation(arguments: arguments, directory: directory) == .help)
  }

  @Test(
    "Version exits before any document input",
    arguments: [["-v"], ["--version"], ["--no-help", "--version"]])
  func version(arguments: [String]) throws {
    #expect(try CommandLineInvocation(arguments: arguments, directory: directory) == .version)
  }

  @Test("Files resolve relative paths, preserve literal Unicode and deduplicate in order")
  func files() throws {
    let args = ["notes/../🧊 #%.md", "./🧊 #%.md", "/tmp/other.md", "--help"]
    let expected = [
      directory.appendingPathComponent("🧊 #%.md"), URL(fileURLWithPath: "/tmp/other.md"),
      directory.appendingPathComponent("--help"),
    ]
    #expect(try CommandLineInvocation(arguments: args, directory: directory) == .open(expected))
  }

  @Test("A delimiter supports leading-dash filenames without silently discarding input")
  func delimiter() throws {
    #expect(
      try CommandLineInvocation(arguments: ["--", "-leading.md", "--help"], directory: directory)
        == .open([
          directory.appendingPathComponent("-leading.md"),
          directory.appendingPathComponent("--help"),
        ]))
  }

  @Test("Unknown leading options fail explicitly", arguments: ["--wat", "-hv", "--help=x=1"])
  func unknown(option: String) {
    #expect(throws: CommandLineInvocationError.unknownOption(option)) {
      try CommandLineInvocation(arguments: [option, "keep.md"], directory: directory)
    }
  }

  @Test("Original boolean values and independent negative keys remain compatible")
  func booleans() throws {
    #expect(
      try CommandLineInvocation(arguments: ["--help=false", "file.md"], directory: directory)
        == .open([directory.appendingPathComponent("file.md")]))
    #expect(
      try CommandLineInvocation(arguments: ["--help=1", "--no-help"], directory: directory) == .help
    )
    #expect(try CommandLineInvocation(arguments: ["--help=Y"], directory: directory) == .help)
  }

  @Test("Invalid filenames are rejected before any launch", arguments: ["", "bad\0name"])
  func invalidPath(path: String) {
    #expect(throws: CommandLineInvocationError.invalidPath) {
      try CommandLineInvocation(arguments: ["--", path], directory: directory)
    }
  }

  @Test("In-memory launch messages preserve BOM, CRLF, Unicode and absent versus empty stdin")
  func roundTrip() async throws {
    let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("# 中文 🧊 e\u{301}\r\n$(literal)\r\n".utf8)
    for input in [nil, Data(), bytes] {
      let request = try CommandLineLaunchRequest(
        files: [directory.appendingPathComponent("% #.md")], pipedData: input)
      let event = try CommandLineLaunchEvent.encode(request)
      #expect(event.eventClass == CommandLineLaunchEvent.eventClass)
      #expect(event.eventID == CommandLineLaunchEvent.eventID)
      #expect(try CommandLineLaunchEvent.decode(event) == request)
      #expect(
        try await CommandLineLaunchEvent.decodePayload(CommandLineLaunchEvent.payload(from: event))
          == request)
      #expect(try request.pipedContents?.encoded() == input)
      #expect(
        try JSONDecoder().decode(CommandLineLaunchRequest.self, from: JSONEncoder().encode(request))
          == request)
    }
  }

  @Test("Decoded external messages validate their version and local file targets")
  func untrustedMessages() throws {
    for json in [
      #"{"version":2,"files":[]}"#,
      #"{"version":1,"files":["https://example.com/a.md"]}"#,
      #"{"version":1,"files":["file://remote/tmp/a.md"]}"#,
      #"{"version":1,"files":["file:///tmp/a%00.md"]}"#,
    ] {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(CommandLineLaunchRequest.self, from: Data(json.utf8))
      }
    }
    #expect(throws: CommandLineInvocationError.unsupportedMessage) {
      try CommandLineLaunchEvent.decode(NSAppleEventDescriptor(string: "not a launch"))
    }
  }

  @Test(
    "Invalid or non-UTF8 piped text is never silently repaired",
    arguments: [
      Data([0xFF]), Data([0xC0, 0xAF]), Data([0xFF, 0xFE, 0x41, 0]),
    ])
  func invalidInput(data: Data) {
    #expect(throws: CommandLineInvocationError.invalidPipedText) {
      try CommandLineLaunchRequest(files: [], pipedData: data)
    }
  }

  @Test("Repeated launch paths preserve first-seen ordering")
  func launchOrder() throws {
    let a = directory.appendingPathComponent("a.md")
    let b = directory.appendingPathComponent("b.md")
    #expect(try CommandLineLaunchRequest(files: [a, b, a]).files == [a, b])
  }

  @Test("Large piped text stays intact in the event envelope")
  func largeInput() throws {
    let bytes = Data(String(repeating: "中文 🧊 e\u{301}\r\n", count: 150_000).utf8)
    let request = try CommandLineLaunchRequest(files: [], pipedData: bytes)
    #expect(
      try CommandLineLaunchEvent.decode(CommandLineLaunchEvent.encode(request)).pipedData == bytes)
  }
}
