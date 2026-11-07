import Foundation

/// Immutable CSS data shared by preview and fresh export snapshots. File discovery,
/// external asset resolution and template compatibility are separate consumers.
public struct DocumentStylesheet: Hashable, Sendable {
  public enum Failure: Error, Equatable, Sendable { case tooLarge, invalidEncoding }
  public static let maximumBytes = 1_048_576
  public static let maximumResolvedBytes = 64 * 1_048_576
  public let css: String

  public init(data: Data) throws {
    guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
    guard var css = String(data: data, encoding: .utf8) else { throw Failure.invalidEncoding }
    css.makeContiguousUTF8()
    self.css = css
  }

  init(resolvedCSS: String) throws {
    guard resolvedCSS.utf8.count <= Self.maximumResolvedBytes else { throw Failure.tooLarge }
    var css = resolvedCSS
    css.makeContiguousUTF8()
    self.css = css
  }

  // CSS identifiers and string values do not use Swift's canonical Unicode
  // equality. Distinct authored scalar sequences must trigger a style update.
  public static func == (lhs: Self, rhs: Self) -> Bool {
    UTF8Text.equal(lhs.css, rhs.css)
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(css.utf8.count)
    for byte in css.utf8 { hasher.combine(byte) }
  }
}

public struct ReadingStyleEntry: Identifiable, Equatable, Sendable {
  public enum Origin: String, Sendable { case builtIn, local, legacy, imported }
  public let id: String
  public let title: String
  public let origin: Origin
  public init(id: String, title: String, origin: Origin = .builtIn) {
    self.id = id
    self.title = title
    self.origin = origin
  }
  public static let notebook = Self(id: "snowfolio", title: "Snowfolio")
  public static let unstyled = Self(id: "none", title: "None")
  public static let bundled = [
    "Clearness", "Clearness Dark", "GitHub", "GitHub2", "Solarized (Light)", "Solarized (Dark)",
  ].map { Self(id: "bundled:" + $0, title: $0) }
  public static let all = [notebook, unstyled] + bundled
}
