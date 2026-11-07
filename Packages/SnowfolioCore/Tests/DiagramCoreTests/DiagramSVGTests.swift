import Foundation
import Testing

@testable import DiagramCore

@Suite("Diagram SVG boundaries")
struct DiagramSVGTests {
  @Test("Variants receive separate IDs without rewriting paint colors or external links")
  func identifiers() async throws {
    let source =
      #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><style>#graph .node{fill:#abc;clip-path:url(#clip)}</style><defs><clipPath id="clip"><rect width="200" height="100"/></clipPath></defs><g id="graph"><a href="https://example.com/guide" target="_blank"><text id="abc">Hello 中文</text></a></g></svg>"#
    let output = try await DiagramSVG.sanitize(source, variant: "light")
    #expect(output.contains("id=\"light-graph\""))
    #expect(output.contains("#light-graph .node"))
    #expect(output.contains("fill:#abc"))
    #expect(output.contains("url(#light-clip)"))
    #expect(output.contains("https://example.com/guide"))
    #expect(output.contains("target=\"_self\""))
    #expect(output.contains("Hello 中文"))
  }

  @Test(
    "Engine output cannot introduce active code, resource loads or entity expansion",
    arguments: [
      #"<script>alert(1)</script>"#,
      #"<g xml:base="https://example.com/"/>"#,
      #"<g onload="alert(1)"></g>"#,
      #"<image href="https://example.com/private.png"/>"#,
      #"<use href="https://example.com/image.svg#x"/>"#,
      #"<a href="javascript:alert(1)"><text>click</text></a>"#,
      #"<style>svg{fill:url(https://example.com/secret)}</style>"#,
      #"<style>svg{background-image:image-set('https://example.com/private.png' 1x)}</style>"#,
      #"<style>@import 'https://example.com/style.css';</style>"#,
      #"<style>svg{fill:u\72l(https://example.com/a)}</style>"#,
      #"<foreignObject><iframe xmlns="http://www.w3.org/1999/xhtml" src="https://example.com"/></foreignObject>"#,
    ])
  func unsafe(_ body: String) async {
    await #expect(throws: DiagramSVGError.self) {
      try await DiagramSVG.sanitize(
        "<svg xmlns=\"http://www.w3.org/2000/svg\">" + body + "</svg>", variant: "dark")
    }
  }

  @Test("DTD subsets, duplicate IDs and excessive geometry are rejected")
  func bounds() async {
    for source in [
      "<!DOCTYPE svg [<!ENTITY e SYSTEM 'file:///etc/passwd'>]><svg xmlns='http://www.w3.org/2000/svg'>&e;</svg>",
      "<svg xmlns='http://www.w3.org/2000/svg'><g id='same'/><g id='same'/></svg>",
      "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1e100 100'/>",
    ] {
      await #expect(throws: DiagramSVGError.self) {
        try await DiagramSVG.sanitize(source, variant: "light")
      }
    }
    let graphviz =
      "<!DOCTYPE svg PUBLIC '-//W3C//DTD SVG 1.1//EN' 'http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd'><svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'><rect width='10' height='10'/></svg>"
    let normalized = try? await DiagramSVG.sanitize(graphviz, variant: "light")
    #expect(normalized?.contains("DOCTYPE") == false)
  }

  @Test("Portable instances keep animation definitions and references separate")
  func animations() async throws {
    let source =
      #"<svg xmlns="http://www.w3.org/2000/svg" id="graph"><style>#graph .edge{animation:flow 2s linear infinite;animation-name:flow}@keyframes flow{to{stroke-dashoffset:0}}</style><path style="animation-name:flow"/></svg>"#
    let output = try await DiagramSVG.sanitize(source, variant: "instance-a")
    #expect(output.contains("@keyframes instance-a-flow"))
    #expect(output.contains("animation-name:instance-a-flow"))
    #expect(output.contains("#instance-a-graph .edge"))
  }

  @Test("Legacy engine fences resolve to native diagram options")
  func fences() {
    for kind in DiagramKind.allCases { #expect(DiagramKind.fence(kind.rawValue) == kind) }
    for alias in ["graphviz", "gv", "viz", "DOT extra-info"] {
      #expect(DiagramKind.fence(alias) == .dot)
    }
    #expect(DiagramKind.fence("swift") == nil)
    #expect(DiagramKind.fence("") == nil)
  }
}
