import AppKit
import DocumentCore
import MarkdownCore
import SwiftUI
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native temporary syntax presentation", .serialized, NativeUIExclusive())
@MainActor
struct NativeSyntaxHighlighterTests {
  private func renderedColor(at offset: Int, in editor: NSTextView, layout: Bool = true) throws
    -> NSColor?
  {
    let manager = try #require(editor.textLayoutManager)
    let content = try #require(manager.textContentManager)
    if layout {
      editor.window?.contentView?.layoutSubtreeIfNeeded()
      manager.textViewportLayoutController.layoutViewport()
      manager.ensureLayout(for: content.documentRange)
      editor.displayIfNeeded()
    }
    var found: NSColor?
    manager.enumerateRenderingAttributes(from: content.documentRange.location, reverse: false) {
      _, attributes, range in
      let first = content.offset(from: content.documentRange.location, to: range.location)
      let last = content.offset(from: content.documentRange.location, to: range.endLocation)
      if offset >= first, offset < last {
        found = attributes[.foregroundColor] as? NSColor
        return false
      }
      return true
    }
    return found
  }

  @Test("Styling changes rendering but never storage, source, selection or native undo")
  func temporaryPresentation() async throws {
    let source = "# 中文 👩🏽‍💻\n\n**bold *italic*** and `code`; _underlined_"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let manager = UndoManager()
    manager.groupsByEvent = false
    coordinator.undoManager = manager
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .titled,
      backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    let selection = (source as NSString).range(of: "中文")
    editor.setSelectedRange(selection)
    let before = try #require(editor.textStorage).copy() as? NSAttributedString
    let processor = MarkdownProcessor()
    let parsed = try await processor.render(source, includeSyntax: true)
    let font = try #require(editor.font)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: document.revision, enabled: true, font: font,
      document: document)
    let italicOffset = (source as NSString).range(of: "italic").location
    let shown = try #require(try renderedColor(at: italicOffset, in: editor))
    #expect(shown == NSColor.systemPink)
    let underlineOffset = (source as NSString).range(of: "underlined").location
    #expect(try renderedColor(at: underlineOffset, in: editor) == NSColor.systemOrange)
    var options = MarkdownRenderingOptions()
    options.underline = true
    let optional = try await processor.render(source, options: options, includeSyntax: true)
    coordinator.highlighter.update(
      syntax: optional.syntax, revision: document.revision, enabled: true, font: font,
      document: document)
    #expect(try renderedColor(at: underlineOffset, in: editor) == NSColor.systemTeal)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: document.revision, enabled: true, font: font,
      document: document)
    #expect(try renderedColor(at: underlineOffset, in: editor) == NSColor.systemOrange)

    #expect(editor.font == font)
    #expect(editor.textStorage?.isEqual(to: try #require(before)) == true)
    #expect(editor.string.utf8.elementsEqual(source.utf8))
    #expect(document.revision == 0)
    #expect(editor.selectedRange() == selection)
    #expect(!manager.canUndo)
    #expect(editor.textLayoutManager != nil)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: false, font: font, document: document)
    #expect(try renderedColor(at: italicOffset, in: editor) == nil)
    withExtendedLifetime(scroll) {}
  }

  @Test("Workspace syntax repaints through inactive preference changes and native undo")
  func workspaceRefresh() async throws {
    _ = NSApplication.shared
    let domain = "SyntaxRefreshTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    let preferences = AppPreferences(defaults: defaults, domainName: domain, legacyValues: [:])
    let source = "# Syntax checkpoint\n\n_Underline checkpoint_ and *italic*; a_b_c.\n\n__中文__"
    let document = MarkdownDocument(contents: TextFileContents(text: source))
    final class UndoWindow: NSWindow {
      let manager = UndoManager()
      override var undoManager: UndoManager? { manager }
    }
    let host = NSHostingController(
      rootView: DocumentWorkspace(document: document, preferences: preferences))
    let window = UndoWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600),
      styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    let undo = window.manager
    undo.groupsByEvent = false
    window.appearance = NSAppearance(named: .aqua)
    window.contentViewController = host
    window.setContentSize(NSSize(width: 1100, height: 600))
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
      if let found = view as? T { return found }
      return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
    func waitFor(_ label: String, _ condition: () async throws -> Bool) async throws {
      for _ in 0..<200 {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(25))
      }
      Issue.record("Timed out: \(label)")
      throw NSError(domain: "SyntaxRefreshTests", code: 1)
    }
    try await waitFor("native surfaces") {
      descendant(MarkdownTextView.self, in: host.view) != nil
        && descendant(WKWebView.self, in: host.view) != nil
    }
    let editor = try #require(descendant(MarkdownTextView.self, in: host.view))
    let web = try #require(descendant(WKWebView.self, in: host.view))
    let textOffset = (source as NSString).range(of: "Underline checkpoint").location
    func previewUsesUnderline(_ enabled: Bool) async throws -> Bool {
      let script = "return String(document.querySelector('u') !== null);"
      let value =
        try await web.callAsyncJavaScript(
          script, arguments: [:], in: nil, contentWorld: .defaultClient) as? String
      return value == String(enabled)
    }
    func paintedPixels(_ name: String, color: NSColor) throws -> Int {
      editor.displayIfNeeded()
      let body = (editor.string as NSString).range(of: "Underline checkpoint")
      let screenRect = editor.firstRect(forCharacterRange: body, actualRange: nil)
      let rect = editor.convert(window.convertFromScreen(screenRect), from: nil)
        .intersection(editor.visibleRect)
      #expect(!rect.isEmpty)
      guard let bitmap = editor.bitmapImageRepForCachingDisplay(in: rect) else {
        throw NSError(domain: "SyntaxRefreshTests", code: 2)
      }
      editor.cacheDisplay(in: rect, to: bitmap)
      if let png = bitmap.representation(using: .png, properties: [:]) {
        try png.write(to: URL(filePath: "/private/tmp/snowfolio-syntax-\(name).png"))
      }
      var resolved: NSColor?
      window.effectiveAppearance.performAsCurrentDrawingAppearance {
        resolved = color.usingColorSpace(.sRGB)
      }
      let target = resolved ?? color
      var found = 0
      for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
          guard let actual = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
            continue
          }
          // HDR screenshots may tone-map RGB magnitudes. Hue still distinguishes
          // the previous orange emphasis from the requested teal underline.
          let distance = abs(actual.hueComponent - target.hueComponent)
          if actual.alphaComponent > 0.8, actual.saturationComponent > 0.2,
            min(distance, 1 - distance) < 0.05
          {
            found += 1
          }
        }
      }
      return found
    }
    try await waitFor("initial syntax") {
      try renderedColor(at: textOffset, in: editor, layout: false) == NSColor.systemOrange
    }
    let initialPixels = try paintedPixels("initial", color: .systemOrange)
    #expect(initialPixels > 20)
    let settings = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 740, height: 573),
      styleMask: .titled, backing: .buffered, defer: false)
    settings.animationBehavior = .none
    settings.isReleasedWhenClosed = false
    settings.makeKeyAndOrderFront(nil)
    defer { settings.close() }
    preferences.underline = true
    try await waitFor("underline preview") { try await previewUsesUnderline(true) }
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(editor)
    try await waitFor("underline syntax") {
      try renderedColor(at: textOffset, in: editor, layout: false) == NSColor.systemTeal
    }
    let enabledPixels = try paintedPixels("enabled", color: .systemTeal)
    #expect(enabledPixels > 20)
    #expect(document.text == source && document.revision == 0 && !undo.canUndo)
    editor.setSelectedRange((source as NSString).range(of: "中文"))
    let commands = try #require(editor.commandController)
    commands.perform(.underline)
    #expect(document.text.hasSuffix("**_中文_**"))
    undo.undo()
    #expect(document.text == source)
    undo.redo()
    #expect(document.text.hasSuffix("**_中文_**"))
    settings.makeKeyAndOrderFront(nil)
    preferences.underline = false
    try await waitFor("standard preview") { try await previewUsesUnderline(false) }
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(editor)
    try await waitFor("standard syntax after undo/redo") {
      try renderedColor(at: textOffset, in: editor, layout: false) == NSColor.systemOrange
    }
    let restoredPixels = try paintedPixels("restored", color: .systemOrange)
    #expect(restoredPixels > 20)
    #expect(!commands.allowsUnderline)
  }

  @Test("Stale snapshots and marked text cannot apply source styles")
  func staleAndComposition() async throws {
    let document = MarkdownDocument(contents: TextFileContents(text: "**bold**"))
    let coordinator = NativeMarkdownEditor.Coordinator(document: document)
    let scroll = NativeMarkdownEditor.makeScrollView(document: document, coordinator: coordinator)
    let editor = try #require(scroll.documentView as? MarkdownTextView)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: .titled,
      backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.contentView = scroll
    window.orderFront(nil)
    defer { window.orderOut(nil) }
    let parsed = try await MarkdownProcessor().render(document.text, includeSyntax: true)
    let font = try #require(editor.font)
    coordinator.highlighter.update(
      syntax: parsed.syntax, revision: 0, enabled: true, font: font, document: document)
    editor.setMarkedText(
      "にほん", selectedRange: NSRange(location: 3, length: 0),
      replacementRange: NSRange(location: 2, length: 4))
    let composing = editor.string
    #expect(editor.hasMarkedText())
    #expect(try renderedColor(at: 2, in: editor) == nil)
    #expect(editor.string == composing)
    #expect(editor.hasMarkedText())
    editor.unmarkText()
    #expect(try renderedColor(at: 2, in: editor) == nil)
    withExtendedLifetime(scroll) {}
  }
}
