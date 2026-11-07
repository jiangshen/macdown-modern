import Foundation
import Testing

@testable import MarkdownCore

@Suite("Portable callout emoji")
struct CalloutMarkerTests {
  @Test(
    "A chosen emoji remains source metadata and exports without editing links",
    arguments: ["🎯", "👩🏽‍💻", "🇯🇵", "🏳️‍🌈", "1️⃣"])
  func customEmoji(_ emoji: String) async throws {
    let result = try await MarkdownProcessor().render(
      "> [!NOTE] \(emoji)\n> Keep **中文** and `code`.\n")
    #expect(result.nodes.first(where: { $0.callout != nil })?.calloutEmoji == emoji)
    #expect(result.html.contains(emoji))
    #expect(result.html.contains("<strong>中文</strong>"))
    #expect(!result.html.contains("mdcallout://"))
    let interactive = try await MarkdownProcessor().render(
      "> [!NOTE] \(emoji)\n> Body", interactiveCallouts: true)
    #expect(interactive.html.contains("href=\"mdcallout://icon/1\""))
    #expect(interactive.html.contains("aria-label=\"Change Note callout emoji\""))
  }

  @Test(
    "Titles, ASCII, multiple emoji, and HTML cannot become icon metadata",
    arguments: ["title", "1", "#", "1\u{FE0F}", "🎯💡", "<img>", "\"", "", "a\u{FE0F}"])
  func invalidEmoji(_ value: String) {
    #expect(!CalloutMarker.isEmoji(value))
    if !value.isEmpty { #expect(CalloutMarker.parse("> [!NOTE] " + value) == nil) }
  }

  @Test(
    "Icon edits preserve Unicode, indentation, trailing whitespace and all newline forms",
    arguments: ["\n", "\r\n", "\r"])
  func minimalEdit(_ newline: String) throws {
    let original = "# 👩‍💻 中文" + newline + "  >  [!IMPORTANT]  " + newline + "> Body" + newline
    let edit = try #require(CalloutMarker.iconReplacement(in: original, line: 2, emoji: "👩🏽‍💻"))
    let changed = (original as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    #expect(changed == "# 👩‍💻 中文" + newline + "  >  [!IMPORTANT] 👩🏽‍💻  " + newline + "> Body" + newline)
    let reset = try #require(CalloutMarker.iconReplacement(in: changed, line: 2, emoji: nil))
    #expect(
      (changed as NSString).replacingCharacters(in: reset.range, with: reset.replacement)
        == original)
    #expect(CalloutMarker.iconReplacement(in: original, line: 99, emoji: "🎯") == nil)
    #expect(CalloutMarker.iconReplacement(in: original, line: 0, emoji: "🎯") == nil)
    #expect(CalloutMarker.iconReplacement(in: original, line: 1, emoji: "🎯") == nil)
  }
}
