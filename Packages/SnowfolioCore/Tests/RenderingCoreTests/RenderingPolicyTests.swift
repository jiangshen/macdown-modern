import Foundation
import Testing

@testable import RenderingCore

@Suite("Preview resource boundaries")
struct RenderingPolicyTests {
  @Test("Document HTML is enclosed by a restrictive content policy")
  func contentPolicy() {
    let html = PreviewHTML.document(body: "<h1>Document</h1>")
    #expect(html.contains("script-src 'none'"))
    #expect(html.contains("connect-src 'none'"))
    #expect(html.contains("frame-src 'none'"))
    #expect(html.contains("form-action 'none'"))
    #expect(html.contains("img-src mdasset: data:;"))
    #expect(!html.contains("img-src mdasset: data: https:"))
    #expect(PreviewHTML.document(remoteImages: true).contains("img-src mdasset: data: https:"))
  }

  @Test("A local image can be loaded without arbitrary file access")
  func localImage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = Data([0x89, 0x50, 0x4E, 0x47])
    try bytes.write(to: root.appendingPathComponent("image.png"))
    let request = try #require(URL(string: "mdasset://document/image.png"))
    let resource = try await LocalPreviewResource.load(request, relativeTo: root)
    #expect(resource.data == bytes)
    #expect(resource.mimeType == "image/png")
  }

  @Test("Traversal, foreign hosts, active HTML files and symlink escapes are rejected")
  func resourceEscapes() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("escape"),
      withDestinationURL: root.deletingLastPathComponent())
    for value in [
      "mdasset://document/../outside.png", "mdasset://document/%2e%2e/outside.png",
      "mdasset://other/image.png", "https://example.com/image.png",
      "mdasset://document/content.html", "mdasset://document/escape/outside.png",
    ] {
      let request = try #require(URL(string: value))
      #expect(throws: LocalPreviewResourceError.self) {
        try LocalPreviewResource.resolve(request, relativeTo: root)
      }
    }
  }
}
