import Foundation
import MarkdownCore
import MathCore
import RenderingCore
import Synchronization

public struct MarkdownExport: Sendable {
  public enum Failure: Error, Equatable, Sendable { case assetFolderUnavailable }
  public let fragment: String
  public let document: String

  /// Exports a fresh source snapshot. It never reads a possibly stale live preview.
  @concurrent
  public static func build(
    source: String, options: MarkdownRenderingOptions = .init(),
    title: String, directory: URL?, includeStyles: Bool = true,
    remoteImages: Bool = false, embedLocalImages: Bool = true,
    localImagesUnavailable: Bool = false, style: DocumentStyle = .init(),
    templateName: String = HTMLExportTemplate.defaultName
  ) async throws -> Self {
    let assets = Mutex<[String: String]>([:])
    let result = try await MarkdownProcessor().render(source, options: options) {
      kind, destination in
      guard embedLocalImages, kind == .image,
        let base = URL(string: "mdasset://document/"),
        let url = URL(string: destination, relativeTo: base)?.absoluteURL,
        url.scheme == "mdasset", url.host == "document"
      else { return destination }
      if localImagesUnavailable { throw Failure.assetFolderUnavailable }
      guard let directory else { return destination }
      let resource = try LocalPreviewResource.read(url, relativeTo: directory)
      // Keep the native engine's normal raw HTML and dangerous-URL filtering.
      // A generated marker lets us embed SVG/HEIC too, which cmark's data-URL whitelist
      // would otherwise discard. Only allowlisted bytes from our file reader enter
      // this table; base64 and known MIME types cannot terminate an HTML attribute.
      let marker = "mdexportasset://image/" + UUID().uuidString
      let value = "data:\(resource.mimeType);base64,\(resource.data.base64EncodedString())"
      assets.withLock { $0[marker] = value }
      return marker
    }
    try Task.checkCancellation()
    let replacements = assets.withLock { $0 }
    let body = Self.embedAssets(in: result.html, replacements: replacements)
    // A copied fragment has no document head. Math needs its font/layout rules
    // there too, otherwise its visual and MathML alternatives both become visible.
    let fragment =
      (result.mathExpressions > 0 || result.diagramUsesMath
        ? "<style data-snowfolio-math=\"true\">" + MathStyle.css + "</style>" : "") + body
    return Self(
      fragment: fragment,
      document: try HTMLExportTemplate.document(
        body: body, title: title, style: style, includeStyles: includeStyles,
        includeHighlighting: result.highlightedCodeBlocks > 0 || result.decoratedCodeBlocks > 0,
        includeMath: result.mathExpressions > 0 || result.diagramUsesMath,
        remoteImages: remoteImages, templateName: templateName))
  }

  private static func embedAssets(in html: String, replacements: [String: String]) -> String {
    var remaining = html[...]
    var output = ""
    let prefix = "src=\"mdexportasset://image/"
    while let start = remaining.range(of: prefix),
      let end = remaining[start.upperBound...].firstIndex(of: "\"")
    {
      let markerStart = remaining.index(start.lowerBound, offsetBy: 5)
      let marker = String(remaining[markerStart..<end])
      output += remaining[..<markerStart]
      output += replacements[marker] ?? marker
      remaining = remaining[end...]
    }
    output += remaining
    return output
  }

  @concurrent
  public func writeHTML(to url: URL) async throws {
    try Task.checkCancellation()
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    try Data(document.utf8).write(to: url, options: .atomic)
  }
}
