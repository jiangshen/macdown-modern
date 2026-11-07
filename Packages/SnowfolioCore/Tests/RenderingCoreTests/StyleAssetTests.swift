import Foundation
import Testing

@testable import RenderingCore

@Suite("Frozen custom CSS assets")
struct StyleAssetTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test(
    "Escaped and quoted URLs, nested import conditions and custom properties retain authored CSS")
  func resources() throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root.appending(path: "parts"), withIntermediateDirectories: true)
    let image = Data([1, 2, 3, 4])
    try image.write(to: root.appending(path: "ice 雪.png"))
    try image.write(to: root.appending(path: "alternate.png"))
    let child = "/* keep */ p { background: url('../ice 雪.png#symbol'); color: purple; }"
    try Data(child.utf8).write(to: root.appending(path: "parts/base.css"))
    let source = #"""
      /* url(not-a-resource.png) */
      @import "parts/base.css" layer(ice) supports(display: grid) screen;
      @import "parts/base.css" supports(background: url(not-fetched.png));
      @namespace svg url(http://www.w3.org/2000/svg);
      @supports (background: url(not-a-fetch.png)) { p { display: block; } }
      .café { --ice: u\72l("ice \96ea.png"); background: image-set("alternate.png" 1x, url(alternate.png) 2x); mask: url("alternate.png#snow%22ice"); content: "url(not-an-asset.png)"; }
      """#
    try Data(source.utf8).write(to: root.appending(path: "main.css"))
    let result = try StyleAssetSnapshot.build(
      main: "main.css", directory: root, parser: CSSResourceParser())
    #expect(result.files.count == 4)
    #expect(result.files["main.css"] == Data(source.utf8))
    #expect(result.files["parts/base.css"] == Data(child.utf8))
    let css = result.stylesheet.css
    #expect(css.contains("/* url(not-a-resource.png) */"))
    #expect(css.contains("@namespace svg url(http://www.w3.org/2000/svg);"))
    #expect(css.contains("layer(ice) supports(display: grid) screen;"))
    #expect(css.contains(#"content: "url(not-an-asset.png)""#))
    #expect(css.contains(".café"))
    #expect(css.contains("data:image/png;base64,AQIDBA=="))
    #expect(css.contains("#snow%22ice"))
    let importStart = try #require(css.range(of: "data:text/css;base64,"))
    let importEnd = try #require(css[importStart.upperBound...].firstIndex(of: "\""))
    let decoded = try #require(Data(base64Encoded: String(css[importStart.upperBound..<importEnd])))
    #expect(
      String(decoding: decoded, as: UTF8.self).contains("data:image/png;base64,AQIDBA==#symbol"))
    try Data("changed".utf8).write(to: root.appending(path: "alternate.png"))
    #expect(result.files["alternate.png"] == image)
  }

  @Test("Imports cannot loop, escape their folder, follow symlinks or load remote CSS/fonts")
  func boundaries() throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let parser = CSSResourceParser()
    func build(_ css: String) throws -> DocumentStylesheet {
      try Data(css.utf8).write(to: root.appending(path: "main.css"))
      return try StyleAssetSnapshot.build(main: "main.css", directory: root, parser: parser)
        .stylesheet
    }
    #expect(throws: StyleAssetFailure.importCycle) { try build("@import 'main.css';") }
    #expect(throws: LocalPreviewResourceError.forbiddenURL) {
      try build("p{background:url('../outside.png')}")
    }
    let external = root.deletingLastPathComponent().appendingPathComponent(
      UUID().uuidString + ".png")
    try Data([1]).write(to: external)
    defer { try? FileManager.default.removeItem(at: external) }
    try FileManager.default.createSymbolicLink(
      at: root.appending(path: "link.png"), withDestinationURL: external)
    #expect(throws: LocalPreviewResourceError.outsideDocumentDirectory) {
      try build("p{background:url(link.png)}")
    }
    #expect(throws: StyleAssetFailure.remoteStylesheetOrFont) {
      try build("@import 'https://example.com/x.css';")
    }
    #expect(throws: StyleAssetFailure.remoteStylesheetOrFont) {
      try build("@font-face{font-family:x;src:url(https://example.com/x.woff2)}")
    }
    let remote = "p { background: url(https://example.com/ice.png) }"
    #expect(try build(remote).css == remote)
    let fragments = "p { filter: url(#filter); background: url(data:image/png;base64,AAAA); }"
    #expect(try build(fragments).css == fragments)
  }
  @Test("Style font/image fallbacks are embedded without widening document resource access")
  func fallbackTypes() throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["old.eot", "collection.ttc", "vector.svg", "tile.tiff"] {
      try Data([1, 2, 3]).write(to: root.appending(path: name))
    }
    let css =
      "@font-face{font-family:x;src:url(old.eot) format('embedded-opentype'),url(collection.ttc),url(vector.svg#face) format('svg')}p{background:url(tile.tiff)}"
    try Data(css.utf8).write(to: root.appending(path: "main.css"))
    let snapshot = try StyleAssetSnapshot.build(
      main: "main.css", directory: root, parser: CSSResourceParser())
    #expect(snapshot.files.count == 5 && snapshot.stylesheet.css.contains("#face"))
    #expect(!snapshot.stylesheet.css.contains("url(old.eot)"))
    #expect(throws: LocalPreviewResourceError.unsupportedType) {
      try LocalPreviewResource.read(StyleAssetSnapshot.request("tile.tiff"), relativeTo: root)
    }
    #expect(throws: LocalPreviewResourceError.unsupportedType) {
      try LocalPreviewResource.read(StyleAssetSnapshot.request("old.eot"), relativeTo: root)
    }
  }

  @Test(
    "Embedded CSS imports are parsed recursively and cannot hide unresolved or remote resources")
  func embeddedImports() throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    func build(_ css: String) throws -> String {
      let url = "data:text/css;base64," + Data(css.utf8).base64EncodedString()
      try Data(("@import url('" + url + "');").utf8).write(to: root.appending(path: "main.css"))
      return try StyleAssetSnapshot.build(
        main: "main.css", directory: root, parser: CSSResourceParser()
      ).stylesheet.css
    }
    #expect(try build("p{color:purple}").contains("data:text/css;base64,"))
    #expect(throws: StyleAssetFailure.invalidURL) { try build("p{background:url(relative.png)}") }
    #expect(throws: StyleAssetFailure.remoteStylesheetOrFont) {
      try build("@import 'https://example.com/style.css';")
    }
    #expect(throws: StyleAssetFailure.remoteStylesheetOrFont) {
      try build("@font-face{font-family:x;src:url(https://example.com/font.woff2)}")
    }
  }

}
