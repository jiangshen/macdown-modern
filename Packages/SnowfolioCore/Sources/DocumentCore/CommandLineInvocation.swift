import Foundation

public enum CommandLineInvocationError: Error, Equatable, LocalizedError, Sendable {
  case unknownOption(String)
  case invalidPath, unsupportedMessage, invalidPipedText

  public var errorDescription: String? {
    switch self {
    case .unknownOption(let option): "Unknown option \(option). Use --help for usage."
    case .invalidPath: "A filename is empty or contains a null character."
    case .unsupportedMessage:
      "This command-line request is not supported by this version of Snowfolio."
    case .invalidPipedText: "Piped Markdown must use UTF-8 text."
    }
  }
}

/// Options precede positional paths, matching the original command. A conventional
/// -- delimiter also permits leading-dash filenames; unknown options now fail
/// instead of silently dropping requested input and reporting success.
public enum CommandLineInvocation: Equatable, Sendable {
  case help, version
  case open([URL])

  public init(arguments: [String], directory: URL) throws {
    var help = false
    var version = false
    var paths: [String] = []
    var options = true
    for argument in arguments {
      if options, argument == "--" {
        options = false
        continue
      }
      if options, argument.hasPrefix("-") {
        let split = argument.lastIndex(of: "=")
        let name = split.map { String(argument[..<$0]) } ?? argument
        let enabled =
          split.map { (String(argument[argument.index(after: $0)...]) as NSString).boolValue }
          ?? true
        switch name {
        case "-h", "--help": help = enabled
        case "-v", "--version": version = enabled
        // Original parser stores these as independent keys, not resets.
        case "--no-help", "--no-version": break
        default: throw CommandLineInvocationError.unknownOption(argument)
        }
      } else {
        options = false
        paths.append(argument)
      }
    }
    if help {
      self = .help
      return
    }
    if version {
      self = .version
      return
    }
    var seen = Set<URL>()
    var files: [URL] = []
    for path in paths {
      guard !path.isEmpty, !path.utf8.contains(0) else {
        throw CommandLineInvocationError.invalidPath
      }
      let file = URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
      _ = try DocumentOpenRequest(fileURL: file)
      if seen.insert(file).inserted { files.append(file) }
    }
    self = .open(files)
  }
}

/// Versioned data only: neither paths nor Markdown are interpreted as commands.
/// Validation also runs when decoding external launch events.
public struct CommandLineLaunchRequest: Codable, Equatable, Sendable {
  public let files: [URL]
  public let pipedData: Data?
  public let pipedContents: TextFileContents?
  private enum CodingKeys: String, CodingKey { case version, files, pipedData }

  public init(files: [URL], pipedData: Data? = nil) throws {
    for file in files { _ = try DocumentOpenRequest(fileURL: file) }
    if let pipedData {
      guard let contents = try? TextFileContents(decoding: pipedData), contents.encoding == .utf8
      else {
        throw CommandLineInvocationError.invalidPipedText
      }
      pipedContents = contents
    } else {
      pipedContents = nil
    }
    var seen = Set<URL>()
    self.files = files.filter { seen.insert($0.standardizedFileURL).inserted }
    self.pipedData = pipedData
  }

  @concurrent public static func decodePayload(_ data: Data) async throws -> Self {
    try Task.checkCancellation()
    let request = try JSONDecoder().decode(Self.self, from: data)
    try Task.checkCancellation()
    return request
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.files == rhs.files && lhs.pipedData == rhs.pipedData
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(Int.self, forKey: .version) == 1 else {
      throw CommandLineInvocationError.unsupportedMessage
    }
    try self.init(
      files: container.decode([URL].self, forKey: .files),
      pipedData: container.decodeIfPresent(Data.self, forKey: .pipedData))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(files, forKey: .files)
    try container.encodeIfPresent(pipedData, forKey: .pipedData)
  }
}
