import Foundation

public enum StyleAssetFailure: Error, Equatable, Sendable {
  case parserUnavailable, unsupportedSyntax, invalidURL, remoteStylesheetOrFont
  case importCycle, tooComplex, tooLarge, unsupportedResource
}

/// Resolves every local CSS resource while its explicitly granted folder is open.
/// Original CSS/files remain available for editing/import; only URL token ranges
/// change in the portable presentation. Imports retain layer/supports/media syntax.
struct StyleAssetSnapshot {
  let stylesheet: DocumentStylesheet
  let files: [String: Data]

  static func build(main: String, directory: URL, parser: CSSResourceParser, mainData: Data? = nil)
    throws -> Self
  {
    var builder = Builder(directory: directory, parser: parser)
    let url = try request(main)
    if let mainData {
      _ = try DocumentStylesheet(data: mainData)
      builder.seededPath = url.path
      builder.files[url.path] = mainData
      builder.mimes[url.path] = "text/css"
      builder.totalBytes = mainData.count
    }
    let css = try builder.sheet(url, depth: 0)
    return Self(
      stylesheet: try DocumentStylesheet(resolvedCSS: css),
      files: Dictionary(
        uniqueKeysWithValues: builder.files.map { (String($0.key.dropFirst()), $0.value) }))
  }

  static func request(_ path: String) throws -> URL {
    var components = URLComponents()
    components.scheme = "mdasset"
    components.host = "document"
    components.path = "/" + path
    guard let url = components.url else { throw StyleAssetFailure.invalidURL }
    return url
  }

  private struct Builder {
    let directory: URL
    let parser: CSSResourceParser
    var files: [String: Data] = [:]
    var seededPath: String?
    var mimes: [String: String] = [:]
    var totalBytes = 0
    var active: Set<String> = []
    var sheets: [String: String] = [:]
    var assets: [String: String] = [:]

    func resourcePath(_ url: URL) throws -> String {
      if url.path == seededPath { return url.path }
      let file = try LocalPreviewResource.resolveStyle(url, relativeTo: directory)
      let root = directory.standardizedFileURL.resolvingSymlinksInPath()
      return "/" + file.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
    }

    mutating func read(_ url: URL) throws -> (Data, String) {
      let key = try resourcePath(url)
      if let saved = files[key], let mime = mimes[key] { return (saved, mime) }
      guard files.count < 128 else { throw StyleAssetFailure.tooComplex }
      let loaded = try LocalPreviewResource.readStyle(url, relativeTo: directory)
      guard loaded.data.count <= 32 * 1_048_576 - totalBytes else {
        throw StyleAssetFailure.tooLarge
      }
      totalBytes += loaded.data.count
      files[key] = loaded.data
      mimes[key] = loaded.mimeType
      return (loaded.data, loaded.mimeType)
    }

    mutating func sheet(_ url: URL, depth: Int) throws -> String {
      try Task.checkCancellation()
      let key = try resourcePath(url)
      guard depth < 16, !active.contains(key) else {
        throw active.contains(key) ? StyleAssetFailure.importCycle : .tooComplex
      }
      if let saved = sheets[key] { return saved }
      guard url.pathExtension.lowercased() == "css" else {
        throw StyleAssetFailure.unsupportedResource
      }
      active.insert(key)
      defer { active.remove(key) }
      let (data, _) = try read(url)
      let source = try DocumentStylesheet(data: data).css
      let output = try rewrite(source, base: url, depth: depth)
      sheets[key] = output
      return output
    }

    mutating func rewrite(_ source: String, base: URL?, depth: Int) throws -> String {
      guard depth < 16 else { throw StyleAssetFailure.tooComplex }
      let references = try parser.references(in: source)
      let text = source as NSString
      var output = ""
      var position = 0
      for reference in references {
        try Task.checkCancellation()
        guard reference.start >= position, reference.end >= reference.start,
          reference.end <= text.length
        else { throw StyleAssetFailure.unsupportedSyntax }
        let replacement = try destination(reference, from: base, depth: depth)
        let original = text.substring(
          with: NSRange(location: reference.start, length: reference.end - reference.start))
        let token =
          replacement.map { reference.string ? "\"" + $0 + "\"" : "url(\"" + $0 + "\")" }
          ?? original
        output += text.substring(
          with: NSRange(location: position, length: reference.start - position))
        output += token
        guard output.utf8.count <= DocumentStylesheet.maximumResolvedBytes else {
          throw StyleAssetFailure.tooLarge
        }
        position = reference.end
      }
      output += text.substring(from: position)
      guard output.utf8.count <= DocumentStylesheet.maximumResolvedBytes else {
        throw StyleAssetFailure.tooLarge
      }
      return output
    }

    func dataStylesheet(_ value: String) throws -> String {
      let withoutFragment = value.split(
        separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
      guard let comma = withoutFragment.firstIndex(of: ",") else {
        throw StyleAssetFailure.invalidURL
      }
      let header = withoutFragment[..<comma].lowercased().split(separator: ";")
      guard header.first == "data:text/css",
        let payload = String(withoutFragment[withoutFragment.index(after: comma)...])
          .removingPercentEncoding
      else {
        throw StyleAssetFailure.unsupportedResource
      }
      let data: Data
      if header.contains("base64") {
        let encoded = payload.filter { ![" ", "\t", "\r", "\n", "\u{0C}"].contains($0) }
        guard let decoded = Data(base64Encoded: encoded) else { throw StyleAssetFailure.invalidURL }
        data = decoded
      } else {
        data = Data(payload.utf8)
      }
      return try DocumentStylesheet(data: data).css
    }

    mutating func destination(_ reference: CSSResourceParser.Reference, from base: URL?, depth: Int)
      throws -> String?
    {
      let value = reference.value
      if value.isEmpty || value.hasPrefix("#") { return nil }
      if value.lowercased().hasPrefix("data:") {
        guard reference.role == "import" else { return nil }
        let source = try dataStylesheet(value)
        let css = try rewrite(source, base: nil, depth: depth + 1)
        return "data:text/css;base64," + Data(css.utf8).base64EncodedString()
      }
      guard !value.contains("\0"), let url = URL(string: value, relativeTo: base)?.absoluteURL
      else {
        throw StyleAssetFailure.invalidURL
      }
      if url.scheme == "https", reference.role == "image" { return nil }
      guard url.scheme == "mdasset", url.host == "document", url.user == nil,
        url.password == nil, url.port == nil
      else {
        if reference.role != "image" { throw StyleAssetFailure.remoteStylesheetOrFont }
        throw StyleAssetFailure.invalidURL
      }
      if reference.role == "import" {
        let css = try sheet(url, depth: depth + 1)
        return "data:text/css;base64," + Data(css.utf8).base64EncodedString()
      }
      let suffix = url.pathExtension.lowercased()
      let fonts = ["woff", "woff2", "ttf", "otf", "ttc", "otc", "eot"]
      guard
        reference.role == "font"
          ? fonts.contains(suffix) || suffix == "svg" : !fonts.contains(suffix) && suffix != "css"
      else { throw StyleAssetFailure.unsupportedResource }
      let embedded: String
      if let saved = assets[try resourcePath(url)] {
        embedded = saved
      } else {
        let (data, mime) = try read(url)
        embedded = "data:" + mime + ";base64," + data.base64EncodedString()
        assets[try resourcePath(url)] = embedded
      }
      // SVG fragment identifiers still select the authored symbol/view.
      let fragment = URLComponents(url: url, resolvingAgainstBaseURL: true)?.percentEncodedFragment
      return embedded + (fragment.map { "#" + $0 } ?? "")
    }
  }
}
