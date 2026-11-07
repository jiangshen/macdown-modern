import Foundation
import Testing

@testable import RenderingCore

@Suite("HTML template compatibility")
struct LegacyHTMLTemplateTests {
  @Test("The preserved Default template retains title, stylesheet, body and script ordering")
  func bundledContext() throws {
    let url = try #require(
      Bundle.module.url(
        forResource: "Default", withExtension: "handlebars", subdirectory: "Templates"))
    let template = try LegacyHTMLTemplate(data: Data(contentsOf: url))
    let output = try template.render(
      .init(
        title: "中文 & Ice", body: "<p>Body</p>",
        styleTags: ["<style>first</style>", "<style>second</style>"],
        scriptTags: ["<script>first()</script>", "<script>second()</script>"]))
    let expected = """
      <!DOCTYPE html>
      <html>

      <head>

      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
      <title>中文 &amp; Ice</title>


      <style>first</style>

      <style>second</style>


      </head>

      <body>

      <p>Body</p>


      <script>first()</script>

      <script>second()</script>


      </body>

      </html>

      """
    #expect(output.utf8.elementsEqual(expected.utf8))
    let empty = try template.render(.init(title: "", body: "<p>Only</p>"))
    #expect(!empty.contains("<title>") && !empty.contains("<style>") && !empty.contains("<script>"))
    #expect(empty.contains("<p>Only</p>"))
  }

  @Test("Escaped values and raw typed tags have separate boundaries")
  func escaping() throws {
    let template = try LegacyHTMLTemplate(
      data: Data(
        "{{title}}|{{{title}}}|{{titleTag}}|{{{titleTag}}}|{{body}}|{{{body}}}|{{#each styleTags}}{{this}}/{{{this}}}{{/each}}"
          .utf8))
    let context = LegacyHTMLTemplate.Context(
      title: "<>&\"'`=", body: "<p>中文</p>", styleTags: ["<&>"])
    let output = try template.render(context)
    #expect(output.hasPrefix("&lt;&gt;&amp;&quot;&#39;&#96;&#61;|<>&\"'`=|"))
    #expect(output.contains("&lt;title&gt;&amp;lt;"))
    #expect(output.contains("<title>&lt;&gt;&amp;&quot;&#39;&#96;&#61;</title>"))
    #expect(output.contains("&lt;p&gt;中文&lt;/p&gt;|<p>中文</p>"))
    #expect(output.hasSuffix("&lt;&amp;&gt;/<&>"))
  }

  @Test(
    "Unsupported helpers, paths, partials and scopes are explicit errors",
    arguments: [
      "{{unknown}}", "{{this}}", "{{title.name}}", "{{> partial}}", "{{helper title}}",
      "{{#if title}}yes{{/if}}", "{{#each unknown}}{{this}}{{/each}}",
      "{{#each styleTags}}{{title}}{{/each}}",
      "{{#each styleTags}}{{#each scriptTags}}{{this}}{{/each}}{{/each}}",
      "{{{#each styleTags}}}{{{this}}}{{{/each}}}",
    ])
  func unsupported(_ source: String) {
    #expect(throws: LegacyHTMLTemplate.Failure.unsupportedExpression) {
      try LegacyHTMLTemplate(data: Data(source.utf8))
    }
  }

  @Test("Malformed and excessive templates fail before rendering")
  func invalidSource() {
    for source in ["{{title", "{{/each}}", "{{#each styleTags}}{{{this}}}"] {
      #expect(throws: LegacyHTMLTemplate.Failure.malformedBlock) {
        try LegacyHTMLTemplate(data: Data(source.utf8))
      }
    }
    #expect(throws: LegacyHTMLTemplate.Failure.invalidEncoding) {
      try LegacyHTMLTemplate(data: Data([255]))
    }
    #expect(throws: LegacyHTMLTemplate.Failure.tooLarge) {
      try LegacyHTMLTemplate(
        data: Data(repeating: 65, count: LegacyHTMLTemplate.maximumSourceBytes + 1))
    }
    #expect(throws: LegacyHTMLTemplate.Failure.tooLarge) {
      try LegacyHTMLTemplate(data: Data(String(repeating: "{{title}}", count: 2049).utf8))
    }
  }

  @Test("Output limits count UTF-8 bytes including expanded collections and escaping")
  func outputLimits() throws {
    let template = try LegacyHTMLTemplate(
      data: Data("{{#each styleTags}}{{{this}}}{{/each}}{{body}}".utf8))
    let context = LegacyHTMLTemplate.Context(title: "", body: "<&", styleTags: ["😀", "中文"])
    let output = "😀中文&lt;&amp;"
    #expect(try template.render(context, maximumBytes: output.utf8.count) == output)
    #expect(throws: LegacyHTMLTemplate.Failure.outputTooLarge) {
      try template.render(context, maximumBytes: output.utf8.count - 1)
    }
    #expect(throws: LegacyHTMLTemplate.Failure.outputTooLarge) {
      try template.render(context, maximumBytes: -1)
    }
  }

  @Test("Cancelled rendering stops without publishing partial output")
  func cancellation() async throws {
    let template = try LegacyHTMLTemplate(data: Data("{{{body}}}".utf8))
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try template.render(.init(title: "", body: "cancelled"))
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
