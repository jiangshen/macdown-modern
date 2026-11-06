import Foundation
import Testing

@testable import EditorCore

@Suite("Markdown editing semantics")
struct MarkdownEditingTests {
  private func apply(
    _ command: MarkdownCommand, _ source: String, _ selection: NSRange,
    behavior: EditorBehavior = .init()
  ) throws -> (String, NSRange) {
    let transaction = try #require(
      try MarkdownEditing.transaction(
        for: command, in: source, selection: selection, behavior: behavior))
    let result = try transaction.edit.applying(to: source)
    try TextEdit.validate(transaction.selection, in: result.text)
    #expect(try result.inverse.applying(to: result.text).text.utf8.elementsEqual(source.utf8))
    return (result.text, transaction.selection)
  }

  @Test("Inline commands wrap and unwrap exactly the selected Unicode content")
  func inlineToggles() throws {
    let content = "中文 👩‍💻 cafe\u{301}"
    for command in [MarkdownCommand.bold, .italic, .strikethrough, .comment, .inlineCode] {
      let first = try apply(command, content, NSRange(location: 0, length: content.utf16.count))
      #expect((first.0 as NSString).substring(with: first.1).utf8.elementsEqual(content.utf8))
      let second = try apply(command, first.0, first.1)
      #expect(second.0.utf8.elementsEqual(content.utf8))
      #expect(second.1 == NSRange(location: 0, length: content.utf16.count))
    }
  }

  @Test("Italic toggles distinguish bold from combined bold and italic")
  func emphasis() throws {
    let first = try apply(.italic, "**word**", NSRange(location: 2, length: 4))
    #expect(first.0 == "***word***")
    #expect(try apply(.italic, first.0, first.1).0 == "**word**")
    #expect(try apply(.bold, "**word**", NSRange(location: 0, length: 8)).0 == "word")
  }

  @Test("Inline code chooses safe delimiters for literal backticks")
  func codeSpans() throws {
    let first = try apply(.inlineCode, "`a`", NSRange(location: 0, length: 3))
    #expect(first.0 == "`` `a` ``")
    #expect(try apply(.inlineCode, first.0, first.1).0 == "`a`")
  }

  @Test("Headings replace existing levels and preserve mixed line endings and trailing newline")
  func headings() throws {
    let source = "# One\r\n## 中文\r\n\r\nLast\r"
    let result = try apply(.heading(3), source, NSRange(location: 0, length: source.utf16.count))
    #expect(result.0 == "### One\r\n### 中文\r\n\r\n### Last\r")
    #expect(
      try apply(.paragraph, result.0, NSRange(location: 0, length: result.0.utf16.count)).0
        == "One\r\n中文\r\n\r\nLast\r")
  }

  @Test("Indenting a selection ending at the next line start leaves that next line alone")
  func lineSelectionBoundaries() throws {
    var behavior = EditorBehavior()
    behavior.convertTabs = true
    let result = try apply(.indent, "a\nb", NSRange(location: 0, length: 2), behavior: behavior)
    #expect(result.0 == "    a\nb")
    #expect(result.1 == NSRange(location: 4, length: 2))
    #expect(try apply(.outdent, result.0, result.1, behavior: behavior).0 == "a\nb")
    #expect(try apply(.indent, "", NSRange(location: 0, length: 0)).0 == "\t")
    #expect(try apply(.outdent, "\t\r\n    \r", NSRange(location: 0, length: 8)).0 == "\r\n\r")
  }

  @Test("Lists convert marker styles and remove multi-digit prefixes safely")
  func listMarkers() throws {
    let source = "10. one\r\n11. two"
    #expect(
      try apply(.orderedList, source, NSRange(location: 0, length: source.utf16.count)).0
        == "one\r\ntwo")
    #expect(
      try apply(.unorderedList, source, NSRange(location: 0, length: source.utf16.count)).0
        == "* one\r\n* two")
    #expect(
      try apply(.orderedList, "- one\n- two", NSRange(location: 0, length: 11)).0
        == "1. one\n2. two")
    #expect(
      try apply(.blockquote, "> one\n>> two", NSRange(location: 0, length: 12)).0 == "one\n> two")
  }

  @Test("Task commands add unchecked tasks and then toggle checked state")
  func tasks() throws {
    let first = try apply(.toggleTask, "- work", NSRange(location: 6, length: 0))
    #expect(first.0 == "- [ ] work")
    let checked = try apply(.toggleTask, first.0, first.1)
    #expect(checked.0 == "- [x] work")
    #expect(try apply(.toggleTask, checked.0, checked.1).0 == "- [ ] work")
  }

  @Test("Links and images select an escaped destination for editing")
  func links() throws {
    let result = try apply(
      .link("https://example.com/a(b) c"), "中文", NSRange(location: 0, length: 2))
    #expect(result.0 == "[中文](https://example.com/a\\(b\\)%20c)")
    #expect((result.0 as NSString).substring(with: result.1) == "https://example.com/a\\(b\\)%20c")
    #expect(try apply(.image(nil), "alt", NSRange(location: 0, length: 3)).0 == "![alt]()")
  }

  @Test(
    "Return continues lists, resets task checks, exits empty items and preserves CRLF",
    arguments: [
      ("- item", "- item\n- "), ("- [x] done", "- [x] done\n- [ ] "),
      ("9. item", "9. item\n10. "), ("- ", "\n"),
      ("  > - item", "  > - item\n  > - "), (">> quote", ">> quote\n>> "),
      ("a\r\n- item", "a\r\n- item\r\n- "), ("    code", "    code\n    "),
    ])
  func newline(_ source: String, _ expected: String) throws {
    let transaction = try #require(
      try MarkdownEditing.input(
        .newline, in: source,
        selection: NSRange(location: source.utf16.count, length: 0)))
    let result = try transaction.edit.applying(to: source)
    #expect(result.text == expected)
    #expect(transaction.selection.location == expected.utf16.count)
  }

  @Test("Tab stops, paired delimiters and deletion use UTF-16-safe local edits")
  func inputAssistance() throws {
    var behavior = EditorBehavior()
    behavior.convertTabs = true
    behavior.pairDelimiters = true
    let tab = try #require(
      try MarkdownEditing.input(
        .tab, in: "abc", selection: NSRange(location: 3, length: 0), behavior: behavior))
    #expect(try tab.edit.applying(to: "abc").text == "abc ")
    let pair = try #require(
      try MarkdownEditing.matchingReplacement(
        "(", in: "", selection: NSRange(location: 0, length: 0)))
    #expect(try pair.edit.applying(to: "").text == "()")
    #expect(pair.selection == NSRange(location: 1, length: 0))
    let deletion = try #require(
      try MarkdownEditing.input(.backspace, in: "()", selection: pair.selection, behavior: behavior)
    )
    #expect(try deletion.edit.applying(to: "()").text == "")
    let skip = try #require(
      try MarkdownEditing.matchingReplacement(")", in: "()", selection: pair.selection))
    #expect(skip.selection.location == 2)
    #expect(try skip.edit.applying(to: "()").text == "()")
    #expect(
      try MarkdownEditing.matchingReplacement(
        "'", in: "dont", selection: NSRange(location: 3, length: 0)) == nil)
    #expect(throws: TextEditError.self) {
      try MarkdownEditing.transaction(
        for: .bold, in: "😀", selection: NSRange(location: 1, length: 0))
    }
  }
  @Test("Splitting before an existing list marker adds only the missing indentation")
  func existingMarker() throws {
    let source = "  - first- next"
    let transaction = try #require(
      try MarkdownEditing.input(
        .newline, in: source,
        selection: NSRange(location: 9, length: 0)))
    #expect(try transaction.edit.applying(to: source).text == "  - first\n  - next")
  }

}
