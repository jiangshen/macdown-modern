import Foundation
import Testing

@testable import MarkdownCore
@testable import MathCore

@Suite("Document math compatibility")
struct MarkdownMathCompatibilityTests {
  @Test(
    "Custom environments retain ordered definitions, reset between documents and cache whole batches"
  )
  func environments() throws {
    let renderer = MathRenderer()
    let sources = [
      #"\newenvironment{snowcase}[1]{\left\{#1}{\right.}"#,
      #"\begin{snowcase}{x}y\end{snowcase}"#,
      #"\renewenvironment{snowcase}[1]{\left[#1}{\right]}"#,
      #"\begin{snowcase}{a}b\end{snowcase}"#,
      #"\bbox[red,2px]{x^2}"#,
    ]
    let expressions = sources.map { MathExpression($0, display: true) }
    let values = try renderer.renderDocument(expressions)
    #expect(values.count == 5 && values.allSatisfy { $0.issue == nil })
    #expect(values[0].html.contains("md-mathjax-empty"))
    #expect(values[1].html.contains("<svg") && values[1].html.contains("<math"))
    #expect(values[1].html.contains("application/x-tex"))
    #expect(values[1].html.contains("{</mo>"))
    #expect(values[3].html.contains("[</mo>"))
    #expect(try renderer.renderDocument(expressions).map(\.html) == values.map(\.html))
    #expect(try renderer.render(sources[1], display: true).issue != nil)
    #expect(try renderer.renderDocument([expressions[1]]).first?.issue != nil)
    let ordinary = try renderer.render("x^2", display: true)
    #expect(ordinary.issue == nil && ordinary.html.contains("class=\"katex\""))
  }

  @Test(
    "A compatibility document retains ordinary fractions, matrices, text, font styles and cancellation"
  )
  func mixedSyntax() throws {
    let sources = [
      #"\newenvironment{snowcase}{[}{]}"#,
      #"\frac{a_b}{c^2}"#, #"\sum_{n=1}^{\infty}\frac{1}{n^2}=\frac{\pi^2}{6}"#,
      #"\begin{pmatrix}a&b\\c&d\end{pmatrix}"#, #"\int_0^1 x^2\,dx=\frac13"#,
      #"\cancelto{0}{x}+\cancel{y}"#, #"\large\mathbb{R}+\boldsymbol{x}"#,
      #"\text{中文 é}+\textbf{bold}"#, #"\Braket{a|b}"#, #"\verb|a_b|"#,
      #"a\xrightarrow{n\to\infty} b"#,
    ]
    let results = try MathRenderer().renderDocument(
      sources.map { MathExpression($0, display: true) })
    for (source, result) in zip(sources, results) {
      #expect(result.issue == nil, "\(source): \(result.html)")
    }
  }

  @Test("Forward and backward tagged references target unique portable SVG identifiers")
  func references() throws {
    let sources = [
      #"\eqref{later}"#, #"x^2\tag{A}\label{first}"#, #"\eqref{first}"#,
      #"y^2\tag{B}\label{later}"#,
    ]
    let values = try MathRenderer().renderDocument(
      sources.map { MathExpression($0, display: true) })
    #expect(values.allSatisfy { $0.issue == nil })
    #expect(values[0].html.contains("(B)"))
    #expect(values[2].html.contains("(A)"))
    var ids: [String] = []
    var destinations: [String] = []
    for value in values {
      let document = try XMLDocument(xmlString: value.html)
      ids += try document.nodes(forXPath: "//*[@id]").compactMap {
        ($0 as? XMLElement)?.attribute(forName: "id")?.stringValue
      }
      destinations += try document.nodes(forXPath: "//*[@href]").compactMap {
        ($0 as? XMLElement)?.attribute(forName: "href")?.stringValue
      }
    }
    #expect(ids.count >= 2 && Set(ids).count == ids.count)
    #expect(!destinations.isEmpty)
    #expect(
      destinations.allSatisfy { $0.hasPrefix("#sfmath-") && ids.contains(String($0.dropFirst())) })
  }

  @Test(
    "Compatibility errors, recursive macros and oversized geometry leave other equations intact")
  func constraints() throws {
    let sources = [
      #"\newenvironment{snowcase}{\left[}{\right]}"#, "x^2",
      #"\href{javascript:alert(1)}{click}"#, #"\def\loop{\loop}\loop"#,
      #"\rule{1000000000em}{1000000000em}"#, "y^2", #"\unsupportedLastCommand"#,
    ]
    let values = try MathRenderer().renderDocument(
      sources.map { MathExpression($0, display: true) })
    #expect(values[0].issue == nil && values[1].issue == nil && values[5].issue == nil)
    #expect(values[2].issue != nil && values[3].issue != nil && values[4].issue != nil)
    #expect(
      values.allSatisfy { !$0.html.contains("<script") && !$0.html.contains("href=\"javascript:") })
    let renderer = MathRenderer()
    struct Stop: Error {}
    var indices: [Int] = []
    #expect(throws: Stop.self) {
      try renderer.renderDocument(sources.prefix(2).map { MathExpression($0, display: true) }) {
        index, _ in
        indices.append(index)
        throw Stop()
      }
    }
    #expect(indices == [0])
    #expect(try renderer.render(#"\begin{snowcase}x\end{snowcase}"#, display: true).issue != nil)
  }

  @Test(
    "Portable annotations retain exact Unicode bytes and incomplete source never changes definitions"
  )
  func sourceFidelity() throws {
    let renderer = MathRenderer()
    for text in ["é", "e\u{301}"] {
      let source = "\\bbox{\\text{" + text + "}}"
      let value = try renderer.render(source, display: false)
      #expect(value.issue == nil)
      let document = try XMLDocument(xmlString: value.html)
      let annotations = try document.nodes(forXPath: "//*[local-name()='annotation']")
      #expect(annotations.first?.stringValue?.utf8.elementsEqual(source.utf8) == true)
    }
    let expressions = [
      MathExpression(#"\newenvironment{privatecase}{[}{]}"#, display: true, isComplete: false),
      MathExpression(#"\begin{privatecase}x\end{privatecase}"#, display: true),
      MathExpression("x", display: false),
    ]
    let values = try renderer.renderDocument(expressions)
    #expect(values[0].issue != nil && values[1].issue != nil && values[2].issue == nil)
    #expect(
      try renderer.renderDocument([MathExpression("x", display: false, isComplete: false)]).first?
        .issue != nil)
    #expect(try renderer.render("x", display: false).issue == nil)
  }

  @Test("Compatibility output streams beyond the cache budget without dropping equations")
  func streaming() throws {
    let renderer = MathRenderer()
    var expressions = [MathExpression(#"\newenvironment{snowcase}{[}{]}"#, display: true)]
    expressions += Array(
      repeating: MathExpression(
        "\\text{" + String(repeating: "x", count: 100) + "}", display: true), count: 80)
    var bytes = 0
    var count = 0
    try renderer.renderDocument(expressions) { index, result in
      #expect(index == count && result.issue == nil)
      count += 1
      bytes += result.html.utf8.count
    }
    #expect(count == expressions.count && bytes > 2_097_152)
  }

  @Test(
    "Markup boundary rejects active content, resource CSS, external links and unbounded geometry")
  func markupBoundary() throws {
    let math = #"<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>"#
    for body in [
      #"<script>alert(1)</script>"#, #"<image href="https://example.com/private.png"/>"#,
      #"<a href="javascript:alert(1)"><path d="M0 0"/></a>"#,
      #"<g style="color:url(https://example.com/x)"><path d="M0 0"/></g>"#,
      #"<g style="color:u\72l(https://example.com/x)"><path d="M0 0"/></g>"#,
      #"<g onload="alert(1)"><path d="M0 0"/></g>"#,
      #"<path d="M0 0" transform="translate(1e999 0)"/>"#,
    ] {
      let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">"# + body + "</svg>"
      #expect(throws: (any Error).self) {
        try MathMarkup.html(svg: svg, mathml: math, source: "x", display: false, namespace: "test")
      }
    }
    let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><path d="M0 0"/></svg>"#
    #expect(throws: (any Error).self) {
      try MathMarkup.html(
        svg: svg, mathml: #"<!DOCTYPE math [<!ENTITY x SYSTEM "file:///etc/passwd">]>"# + math,
        source: "x", display: false, namespace: "test")
    }
  }
}
