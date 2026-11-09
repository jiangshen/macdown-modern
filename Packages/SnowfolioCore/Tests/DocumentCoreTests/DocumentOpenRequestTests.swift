import Foundation
import Testing

@testable import DocumentCore

@Suite("Document link requests")
struct DocumentOpenRequestTests {
  @Test(
    "Branded and explicitly targeted old links preserve encoded local paths",
    arguments: ["snowfolio", "x-snowfolio", "x-macdown", "SNOWFOLIO"])
  func roundTrip(scheme: String) throws {
    let file = URL(fileURLWithPath: "/tmp/Snowfolio links/中文 #%.md")
    let location = try #require(DocumentSourceLocation(line: 12, column: 45))
    let request = try DocumentOpenRequest(fileURL: file, location: location)
    var parts = try #require(
      URLComponents(url: try request.linkURL(), resolvingAgainstBaseURL: false))
    parts.scheme = scheme
    parts.queryItems?.append(URLQueryItem(name: "future-option", value: "ignored"))
    let decoded = try DocumentOpenRequest(link: #require(parts.url))
    #expect(decoded == request)
    #expect(decoded.fileURL.absoluteString.utf8.elementsEqual(file.absoluteString.utf8))
    #expect(DocumentOpenRequest.registeredSchemes == ["snowfolio", "x-snowfolio", "x-macdown"])
  }

  private func link(_ items: [URLQueryItem]) throws -> URL {
    var parts = URLComponents()
    parts.scheme = "snowfolio"
    parts.host = "open"
    parts.queryItems = items
    return try #require(parts.url)
  }

  @Test(
    "Optional coordinates preserve open-only requests and default a provided line to column one")
  func optionalLocation() throws {
    let file = URL(fileURLWithPath: "/tmp/Document.md")
    #expect(
      try DocumentOpenRequest(link: DocumentOpenRequest(fileURL: file).linkURL()).location == nil)
    let url = try link([
      .init(name: "url", value: file.absoluteString), .init(name: "line", value: "3"),
    ])
    #expect(try DocumentOpenRequest(link: url).location == DocumentSourceLocation(line: 3))
  }

  @Test("Ambiguous known parameters are rejected, including repeated empty values")
  func repeatedParameters() throws {
    for name in ["url", "line", "column"] {
      let url = try link([
        .init(name: "url", value: "file:///tmp/a.md"),
        .init(name: name, value: ""), .init(name: name, value: ""),
      ])
      #expect(throws: DocumentOpenRequestError.repeatedParameter) {
        try DocumentOpenRequest(link: url)
      }
    }
  }

  @Test(
    "Only local absolute file URLs can become document requests",
    arguments: [
      "https://example.com/file.md", "file://remote-server/tmp/a.md", "file:relative.md",
      "file:///tmp/a.md?query=1", "file:///tmp/a.md#fragment", "file:///tmp/a%00b.md",
      "file://user@localhost/tmp/a.md",
    ])
  func nonLocalFiles(target: String) throws {
    let url = try link([.init(name: "url", value: target)])
    #expect(throws: DocumentOpenRequestError.nonLocalFile) { try DocumentOpenRequest(link: url) }
  }

  @Test(
    "Unsupported envelopes never become file-open operations",
    arguments: [
      "https://open?url=file:///tmp/a.md", "snowfolio://other?url=file:///tmp/a.md",
      "snowfolio://user@open?url=file:///tmp/a.md", "snowfolio://open:99?url=file:///tmp/a.md",
      "snowfolio://open/path?url=file:///tmp/a.md", "snowfolio://open?url=file:///tmp/a.md#bad",
    ])
  func unsupportedLinks(value: String) throws {
    let url = try #require(URL(string: value))
    #expect(throws: DocumentOpenRequestError.unsupportedLink) { try DocumentOpenRequest(link: url) }
  }

  @Test(
    "Zero, signed, fractional, empty and overflowing positions are rejected",
    arguments: [
      "0", "-1", "+1", "1.5", " 2", "", String(repeating: "9", count: 80),
    ])
  func invalidPositions(value: String) throws {
    for key in ["line", "column"] {
      var items = [URLQueryItem(name: "url", value: "file:///tmp/a.md")]
      if key == "column" { items.append(.init(name: "line", value: "2")) }
      items.append(.init(name: key, value: value))
      let url = try link(items)
      #expect(throws: DocumentOpenRequestError.invalidLocation) {
        try DocumentOpenRequest(link: url)
      }
    }
  }

  @Test("A column needs a line; a missing target does not open or create a document")
  func missingFields() throws {
    #expect(throws: DocumentOpenRequestError.invalidLocation) {
      try DocumentOpenRequest(
        link: link([
          .init(name: "url", value: "file:///tmp/a.md"), .init(name: "column", value: "2"),
        ]))
    }
    #expect(throws: DocumentOpenRequestError.missingFile) {
      try DocumentOpenRequest(link: link([]))
    }
    #expect(throws: DocumentOpenRequestError.missingFile) {
      try DocumentOpenRequest(link: link([.init(name: "url", value: "")]))
    }
  }

  @Test(
    "Navigation clamps at line ends without splitting CRLF or composed Unicode",
    arguments: [
      (1, 1, 0), (1, 2, 1), (2, 1, 3), (2, 2, 3), (2, 3, 5), (2, 4, 5),
      (2, 5, 7), (2, 6, 8), (2, 9, 11), (2, Int.max, 11), (3, 2, 14),
      (4, 1, 18), (Int.max, 1, 18),
    ])
  func coordinates(line: Int, column: Int, expected: Int) async throws {
    let source = "A\r\n🧊e\u{301} xyz\r\nLast\n"
    let position = try #require(DocumentSourceLocation(line: line, column: column))
    #expect(try await position.utf16Offset(in: source) == expected)
  }

  @Test("Empty text, system newline classes and cancellation retain valid boundaries")
  func boundaryAndCancellation() async throws {
    let position = try #require(DocumentSourceLocation(line: 2))
    #expect(try await position.utf16Offset(in: "") == 0)
    #expect(try await position.utf16Offset(in: "A\u{2028}B") == 2)
    #expect(DocumentSourceLocation(line: 0) == nil)
    #expect(DocumentSourceLocation(line: 1, column: 0) == nil)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await position.utf16Offset(in: "A\nB")
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
