import Foundation

/// Only Default is bundled by the original app. Its audited literal structure
/// receives the native root and policy before compatibility expressions render.
/// Unknown saved names remain explicit errors, rather than a silent substitution.
public enum HTMLExportTemplate {
  public enum Failure: Error, Equatable, Sendable { case unavailable, invalidBundledTemplate }
  public static let defaultName = "Default"

  public static func document(
    body: String, title: String, style: DocumentStyle,
    includeStyles: Bool, includeHighlighting: Bool, includeMath: Bool,
    remoteImages: Bool, templateName: String = defaultName
  ) throws -> String {
    guard templateName == defaultName else { throw Failure.unavailable }
    let parts = HTMLDocumentParts(
      body: body, title: title, style: style,
      includeStyles: includeStyles, includeHighlighting: includeHighlighting,
      includeMath: includeMath, remoteImages: remoteImages)
    let program: LegacyHTMLTemplate
    switch (style.usesBodyRoot, remoteImages) {
    case (false, false): program = try notebookLocal.get()
    case (false, true): program = try notebookRemote.get()
    case (true, false): program = try authoredLocal.get()
    case (true, true): program = try authoredRemote.get()
    }
    // Scripts are already rendered offline. The compatibility field is empty in
    // production; this adapter never revives executable legacy page resources.
    return try program.render(.init(title: title, body: parts.body, styleTags: parts.styleTags))
  }

  private static let notebookLocal = compile(bodyRoot: false, remoteImages: false)
  private static let notebookRemote = compile(bodyRoot: false, remoteImages: true)
  private static let authoredLocal = compile(bodyRoot: true, remoteImages: false)
  private static let authoredRemote = compile(bodyRoot: true, remoteImages: true)

  private static func compile(bodyRoot: Bool, remoteImages: Bool) -> Result<
    LegacyHTMLTemplate, Error
  > {
    Result {
      guard
        let url = Bundle.module.url(
          forResource: "Default", withExtension: "handlebars", subdirectory: "Templates")
      else { throw Failure.invalidBundledTemplate }
      var source = try String(contentsOf: url, encoding: .utf8)
      let charset = "<meta charset=\"utf-8\">"
      guard source.components(separatedBy: charset).count == 2,
        source.components(separatedBy: "<body>").count == 2
      else { throw Failure.invalidBundledTemplate }
      // Modify only the audited literal resource, before inserting any context.
      // This also avoids scanning/copying a potentially large rendered document.
      source = source.replacingOccurrences(
        of: charset, with: charset + HTMLDocumentParts.policyMeta(remoteImages: remoteImages))
      if bodyRoot {
        source = source.replacingOccurrences(of: "<body>", with: "<body id=\"preview-content\">")
      }
      return try LegacyHTMLTemplate(data: Data(source.utf8))
    }
  }
}
