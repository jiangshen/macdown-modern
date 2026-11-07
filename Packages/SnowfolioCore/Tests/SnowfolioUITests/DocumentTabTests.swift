import AppKit
import DocumentCore
import Testing

@testable import SnowfolioUI

@Suite("Native document tabs", .serialized, NativeUIExclusive())
@MainActor
struct DocumentTabTests {
  @Test("Native tab switching and closing preserve separate editors and undo histories")
  func independentTabState() throws {
    _ = NSApplication.shared
    let first = MarkdownDocument(contents: TextFileContents(text: "first document"))
    let second = MarkdownDocument(contents: TextFileContents(text: "second document"))
    let firstManager = UndoManager()
    let secondManager = UndoManager()
    firstManager.groupsByEvent = false
    secondManager.groupsByEvent = false
    let firstCoordinator = NativeMarkdownEditor.Coordinator(document: first)
    let secondCoordinator = NativeMarkdownEditor.Coordinator(document: second)
    firstCoordinator.undoManager = firstManager
    secondCoordinator.undoManager = secondManager
    let firstScroll = NativeMarkdownEditor.makeScrollView(
      document: first, coordinator: firstCoordinator)
    let secondScroll = NativeMarkdownEditor.makeScrollView(
      document: second, coordinator: secondCoordinator)
    let firstEditor = try #require(firstScroll.documentView as? NSTextView)
    let secondEditor = try #require(secondScroll.documentView as? NSTextView)
    let firstWindow = NSWindow()
    firstWindow.animationBehavior = .none
    let secondWindow = NSWindow()
    secondWindow.animationBehavior = .none
    firstWindow.isReleasedWhenClosed = false
    secondWindow.isReleasedWhenClosed = false
    defer {
      secondWindow.close()
      firstWindow.close()
    }
    firstWindow.contentView = firstScroll
    secondWindow.contentView = secondScroll
    let originalIdentifier = NSUserInterfaceItemIdentifier("host-owned-document")
    firstWindow.identifier = originalIdentifier
    DocumentWindowPolicy.configure(firstWindow, preferTabs: true)
    DocumentWindowPolicy.configure(secondWindow, preferTabs: true)
    #expect(firstWindow.identifier == originalIdentifier)
    firstWindow.addTabbedWindow(secondWindow, ordered: .above)
    let group = try #require(firstWindow.tabGroup)
    #expect(group.windows.count == 2)
    #expect(secondWindow.tabGroup === group)

    firstEditor.setSelectedRange(NSRange(location: 1, length: 3))
    group.selectedWindow = secondWindow
    secondEditor.setSelectedRange(NSRange(location: 0, length: 6))
    secondManager.beginUndoGrouping()
    secondEditor.insertText("changed", replacementRange: secondEditor.selectedRange())
    secondManager.endUndoGrouping()
    #expect(second.text == "changed document")
    #expect(first.text == "first document")
    #expect(firstEditor.selectedRange() == NSRange(location: 1, length: 3))
    #expect(!firstManager.canUndo)
    secondManager.undo()
    #expect(second.text == "second document")
    group.selectedWindow = firstWindow
    #expect(firstEditor.string == "first document")
    #expect(firstEditor.selectedRange() == NSRange(location: 1, length: 3))
    secondWindow.close()
    #expect(firstEditor.string == "first document")
    #expect(firstWindow.tabGroup?.windows.count == 1)
  }
  @Test("Explicit tab placement ignores existing and utility windows and expires safely")
  func explicitTabPlacement() throws {
    _ = NSApplication.shared
    let anchor = NSWindow()
    anchor.animationBehavior = .none
    let existing = NSWindow()
    existing.animationBehavior = .none
    let created = NSWindow()
    created.animationBehavior = .none
    let utility = NSWindow()
    utility.animationBehavior = .none
    for window in [anchor, existing, created, utility] { window.isReleasedWhenClosed = false }
    defer { for window in [created, existing, utility, anchor] { window.close() } }
    for window in [anchor, existing, created] {
      DocumentWindowPolicy.configure(window, preferTabs: false)
    }
    let placement = DocumentTabPlacement()
    let now = ContinuousClock.now
    placement.request(from: anchor, existingWindows: [anchor, existing], now: now)
    #expect(!placement.place(existing, now: now))
    #expect(!placement.place(utility, now: now))
    #expect(placement.place(created, now: now))
    #expect(created.tabGroup === anchor.tabGroup)
    #expect(anchor.tabGroup?.selectedWindow === created)
    #expect(!placement.place(existing, now: now))

    let expired = DocumentTabPlacement()
    expired.request(from: anchor, existingWindows: [anchor], now: now)
    #expect(!expired.place(existing, now: now.advanced(by: .seconds(6))))
    #expect(existing.tabGroup !== anchor.tabGroup)
  }

  @Test("A pending tab request cannot reopen a closed anchor")
  func closingAnchorCancelsPlacement() {
    _ = NSApplication.shared
    let anchor = NSWindow()
    anchor.animationBehavior = .none
    let created = NSWindow()
    created.animationBehavior = .none
    anchor.isReleasedWhenClosed = false
    created.isReleasedWhenClosed = false
    defer { created.close() }
    DocumentWindowPolicy.configure(anchor, preferTabs: true)
    DocumentWindowPolicy.configure(created, preferTabs: true)
    let placement = DocumentTabPlacement()
    placement.request(from: anchor, existingWindows: [anchor])
    anchor.close()
    #expect(!placement.place(created))
  }

}
