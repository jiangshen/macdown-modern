import Testing

@testable import MarkdownCore

@Suite("CommonMark conformance integration")
struct MarkdownConformanceTests {
  @Test("Nested strong nodes survive both AST and HTML rendering")
  func strongNesting() async throws {
    let result = try await MarkdownProcessor().render("****word**** and __outer __inner__ tail__")
    #expect(result.html.contains("<strong><strong>word</strong></strong>"))
    #expect(result.html.contains("<strong>outer <strong>inner</strong> tail</strong>"))
    #expect(result.nodes.filter { $0.kind == .strong }.count == 4)
    #expect(result.notices.isEmpty)
  }

  @Test("Numeric references use the standard decimal and hexadecimal digit limits")
  func numericReferences() async throws {
    let result = try await MarkdownProcessor().render(
      "a&#0000065; b&#00000065; c&#x000041; d&#x0000041;")
    #expect(result.html.contains("aA b&amp;#00000065; cA d&amp;#x0000041;"))
    let code = try await MarkdownProcessor().render("`&#00000065;` and `&#x0000041;`")
    #expect(code.html.contains("<code>&amp;#00000065;</code>"))
    #expect(code.html.contains("<code>&amp;#x0000041;</code>"))
  }

  @Test("Currency and other Unicode symbols participate in native emphasis flanking")
  func unicodeFlanking() async throws {
    let result = try await MarkdownProcessor().render(
      "*£*after *€*word *©*tail *😀*next and *中文*after")
    #expect(result.html.contains("*£*after *€*word *©*tail *😀*next"))
    #expect(result.html.contains("<em>中文</em>after"))
    let spaced = try await MarkdownProcessor().render("*£* after and *€*")
    #expect(spaced.html.contains("<em>£</em> after"))
    #expect(spaced.html.contains("<em>€</em>"))
  }
}
