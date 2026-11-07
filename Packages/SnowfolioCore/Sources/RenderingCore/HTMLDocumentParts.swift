import Foundation
import MathCore

/// Shared typed markup for native preview and exported template contexts. Body,
/// CSS and title have distinct escaping boundaries; data never becomes code.
public struct HTMLDocumentParts: Sendable {
  public let policy: String
  public let titleTag: String
  public let styleTags: [String]
  public let body: String
  public let bodyAttributes: String

  public init(
    body: String, title: String, style: DocumentStyle, includeStyles: Bool,
    includeHighlighting: Bool, includeMath: Bool, remoteImages: Bool
  ) {
    policy = Self.policyMeta(remoteImages: remoteImages)
    titleTag = LegacyHTMLTemplate.Context(title: title, body: "").titleTag
    var tags: [String] = []
    if includeStyles { tags.append(Self.css(style.css, id: "document-style")) }
    if includeHighlighting { tags.append(Self.css(style.codeCSS, id: "code-style")) }
    if includeMath { tags.append(Self.css(MathStyle.css, id: "math-style")) }
    styleTags = tags
    self.body = style.usesBodyRoot ? body : "<main id=\"preview-content\">" + body + "</main>"
    bodyAttributes = style.usesBodyRoot ? " id=\"preview-content\"" : ""
  }

  static func policyMeta(remoteImages: Bool) -> String {
    let imageSources = remoteImages ? "mdasset: data: https:" : "mdasset: data:"
    return
      "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src \(imageSources); style-src 'unsafe-inline' mdasset: data:; font-src mdasset: data:; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\">"
  }

  private static func css(_ css: String, id: String) -> String {
    "<style id=\"" + id + "\">" + css.replacingOccurrences(of: "<", with: "\\3c ") + "</style>"
  }
}
