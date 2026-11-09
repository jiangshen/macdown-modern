import Foundation

/// One-based UTF16 columns match macOS text coordinates. Positions outside a line
/// clamp to its end; positions inside a composed character move to its beginning.
public struct DocumentSourceLocation: Equatable, Sendable {
  public let line: Int
  public let column: Int

  public init?(line: Int, column: Int = 1) {
    guard line > 0, column > 0 else { return nil }
    self.line = line
    self.column = column
  }

  @concurrent public func utf16Offset(in source: String) async throws -> Int {
    try Task.checkCancellation()
    let text = source as NSString
    var start = 0
    for index in 1..<line {
      if index.isMultiple(of: 4096) { try Task.checkCancellation() }
      if start >= text.length { return text.length }
      let range = NSRange(location: start, length: 0)
      text.getLineStart(nil, end: &start, contentsEnd: nil, for: range)
    }
    try Task.checkCancellation()
    guard start < text.length else { return text.length }
    var end = start
    text.getLineStart(
      nil, end: nil, contentsEnd: &end,
      for: NSRange(location: start, length: 0))
    let offset = start + min(column - 1, end - start)
    guard offset < text.length else { return text.length }
    return max(start, text.rangeOfComposedCharacterSequence(at: offset).location)
  }
}

public enum DocumentOpenRequestError: Error, LocalizedError, Sendable {
  case unsupportedLink, missingFile, nonLocalFile, repeatedParameter, invalidLocation

  public var errorDescription: String? {
    switch self {
    case .unsupportedLink: String(localized: "This is not a Snowfolio document link.")
    case .missingFile: String(localized: "The link does not include a file to open.")
    case .nonLocalFile: String(localized: "Snowfolio document links can open local files only.")
    case .repeatedParameter: String(localized: "The link repeats a file or location parameter.")
    case .invalidLocation:
      String(
        localized:
          "Line and column numbers must be positive whole numbers. A column requires a line.")
    }
  }
}

/// File contents and paths stay data; decoding never evaluates a command or script.
public struct DocumentOpenRequest: Equatable, Sendable {
  public static let registeredSchemes = ["snowfolio", "x-snowfolio", "x-macdown"]
  public let fileURL: URL
  public let location: DocumentSourceLocation?

  public init(fileURL: URL, location: DocumentSourceLocation? = nil) throws {
    // URL.path can preserve an encoded NUL. Validate one decoded path before I/O.
    guard
      let path = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)?
        .percentEncodedPath.removingPercentEncoding,
      fileURL.isFileURL, path.hasPrefix("/"), !path.utf8.contains(0),
      fileURL.user == nil, fileURL.password == nil,
      fileURL.port == nil, fileURL.query == nil, fileURL.fragment == nil,
      fileURL.host == nil || fileURL.host == "" || fileURL.host?.lowercased() == "localhost"
    else { throw DocumentOpenRequestError.nonLocalFile }
    self.fileURL = fileURL
    self.location = location
  }

  public init(link: URL) throws {
    // Keep the original external link format as an alias for existing integrations.
    let schemes = Set(Self.registeredSchemes)
    guard let parts = URLComponents(url: link, resolvingAgainstBaseURL: false),
      let scheme = parts.scheme?.lowercased(), schemes.contains(scheme),
      parts.host?.lowercased() == "open", parts.path.isEmpty || parts.path == "/",
      parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil
    else { throw DocumentOpenRequestError.unsupportedLink }
    var values: [String: String] = [:]
    for item in parts.queryItems ?? [] where ["url", "line", "column"].contains(item.name) {
      guard values[item.name] == nil else { throw DocumentOpenRequestError.repeatedParameter }
      values[item.name] = item.value ?? ""
    }
    guard let target = values["url"], !target.isEmpty, let file = URL(string: target) else {
      throw DocumentOpenRequestError.missingFile
    }
    func positive(_ value: String) -> Int? {
      guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(value), number > 0
      else { return nil }
      return number
    }
    let position: DocumentSourceLocation?
    if let rawLine = values["line"] {
      guard let line = positive(rawLine),
        let column = positive(values["column"] ?? "1"),
        let location = DocumentSourceLocation(line: line, column: column)
      else { throw DocumentOpenRequestError.invalidLocation }
      position = location
    } else {
      guard values["column"] == nil else { throw DocumentOpenRequestError.invalidLocation }
      position = nil
    }
    try self.init(fileURL: file, location: position)
  }

  public func linkURL() throws -> URL {
    var parts = URLComponents()
    parts.scheme = Self.registeredSchemes[0]
    parts.host = "open"
    parts.queryItems = [URLQueryItem(name: "url", value: fileURL.absoluteString)]
    if let location {
      parts.queryItems?.append(URLQueryItem(name: "line", value: String(location.line)))
      parts.queryItems?.append(URLQueryItem(name: "column", value: String(location.column)))
    }
    guard let link = parts.url else { throw DocumentOpenRequestError.unsupportedLink }
    return link
  }
}
