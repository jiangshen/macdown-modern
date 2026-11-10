import Foundation
import Testing

@testable import MathCore

@Suite("Offline math enclosures")
struct MarkdownMathEnclosureTests {
  @Test(
    "Original enclosure notations retain portable MathML, visible SVG and exact source",
    arguments: [
      "box", "roundedbox", "circle", "left", "right", "top", "bottom", "actuarial", "longdiv",
      "radical", "updiagonalstrike", "downdiagonalstrike", "verticalstrike", "horizontalstrike",
      "updiagonalarrow", "southeastarrow", "phasorangle", "madruwb", "circle,box",
    ])
  func notation(_ notation: String) throws {
    let source = "\\require{enclose}\\enclose{" + notation + "}{x^2}"
    let result = try MathRenderer().render(source, display: true)
    #expect(result.issue == nil, "\(notation): \(result.html)")
    let document = try XMLDocument(xmlString: result.html)
    let nodes = try document.nodes(forXPath: "//*[local-name()='menclose']")
    let enclosure = try #require(nodes.first as? XMLElement)
    #expect(
      (enclosure.attribute(forName: "notation")?.stringValue ?? "longdiv")
        == notation.replacingOccurrences(of: ",", with: " "))
    #expect(try document.nodes(forXPath: "//*[local-name()='svg']").count == 1)
    let shape: String
    switch notation {
    case "circle", "circle,box": shape = "ellipse"
    case "box", "roundedbox": shape = "rect"
    case "longdiv", "phasorangle", "radical", "updiagonalarrow", "southeastarrow": shape = "path"
    default: shape = "line"
    }
    #expect(
      try !document.nodes(forXPath: "//*[local-name()='svg']//*[local-name()='\(shape)']").isEmpty)
    if notation == "roundedbox" {
      #expect(try !document.nodes(forXPath: "//*[local-name()='rect'][@rx]").isEmpty)
    }
    #expect(try document.nodes(forXPath: "//*[local-name()='msup']").count == 1)
    let annotation = try document.nodes(forXPath: "//*[local-name()='annotation']").first
    #expect(annotation?.stringValue?.utf8.elementsEqual(source.utf8) == true)
    #expect(!result.html.contains("<script") && !result.html.contains("https://"))
  }

  @Test(
    "Nested and colored enclosures retain options without introducing page scripts or resources")
  func options() throws {
    let source =
      #"\enclose{circle}[mathcolor=red,mathbackground=yellow]{\enclose{roundedbox}{\text{é}}}"#
    let renderer = MathRenderer()
    let result = try renderer.render(source, display: false)
    #expect(result.issue == nil, "\(result.html)")
    let document = try XMLDocument(xmlString: result.html)
    let enclosures = try document.nodes(forXPath: "//*[local-name()='menclose']")
    #expect(enclosures.count == 2)
    let outer = enclosures.first as? XMLElement
    #expect(outer?.attribute(forName: "mathcolor")?.stringValue == "red")
    #expect(outer?.attribute(forName: "mathbackground")?.stringValue == "yellow")
    #expect(try renderer.render(source, display: false).html == result.html)
    let annotation = try document.nodes(forXPath: "//*[local-name()='annotation']").first
    #expect(annotation?.stringValue?.utf8.elementsEqual(source.utf8) == true)
  }

  @Test("Enclosure resource attributes and excessive geometry fall back without losing source")
  func limits() throws {
    for source in [
      #"\enclose{circle}[mathcolor=url(https://example.com/x)]{x}"#,
      #"\enclose{box}[mathbackground=url(file:///tmp/x)]{x}"#,
      #"\enclose{box}[data-padding=1000000000em]{x}"#,
      #"\enclose{circle}[data-thickness=1000000000em]{x}"#,
    ] {
      let result = try MathRenderer().render(source, display: true)
      #expect(result.issue != nil, "\(source)")
      #expect(!result.html.contains("<svg") && !result.html.contains("<menclose"))
      #expect(result.html.contains("\\enclose"))
    }
    #expect(try MathRenderer().render("x^2", display: true).html.contains("class=\"katex\""))
  }

  @Test("Ellipse geometry and enclosure strokes retain finite bounded output")
  func geometryBoundary() throws {
    let math = #"<math xmlns="http://www.w3.org/1998/Math/MathML"><mi>x</mi></math>"#
    for shape in [
      #"<ellipse rx="1e999" ry="2" cx="1" cy="1"/>"#,
      #"<ellipse rx="2" ry="NaN" cx="1" cy="1"/>"#,
      #"<rect width="2" height="2" rx="1000000000"/>"#,
      #"<path d="M0 0L1 1" style="stroke-width:1e999"/>"#,
      #"<path d="M0 0L1 1" style="stroke-width:url(https://example.com/x)"/>"#,
    ] {
      let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">"# + shape + "</svg>"
      #expect(throws: (any Error).self) {
        try MathMarkup.html(svg: svg, mathml: math, source: "x", display: false, namespace: "test")
      }
    }
  }
}
