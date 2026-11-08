import AppKit
import CodeHighlightCore
import ExportCore
import MarkdownCore
import PDFKit
import RenderingCore
import Testing
import WebKit

@testable import SnowfolioUI

@Suite("Native portable code presentation", .serialized, NativeUIExclusive())
@MainActor
struct NativeCodePresentationTests {
  private let body = "a = \"中文 👩‍💻<&>\";\n/* comment\nmore */\n\n// &nbsp; &#10; \n"

  @Test("Numbering every pinned grammar preserves exact WebKit code text and selected text")
  func allGrammars() async throws {
    _ = NSApplication.shared
    let languages = try CodeHighlighter().supportedLanguages
    let processor = MarkdownProcessor()
    var options = MarkdownRenderingOptions()
    options.codeLineNumbers = true
    var html = ""
    for language in languages {
      html += try await processor.render("```" + language + "\n" + body + "```", options: options)
        .html
    }
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: PreviewHTML.document(body: html, includeHighlighting: true))
    let result = try await surface.view.callAsyncJavaScript(
      """
      return [...document.querySelectorAll('pre > code')].map(code=>{
        const range=document.createRange(); range.selectNodeContents(code);
        const selection=window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
        return {text:code.textContent, selected:selection.toString(),
          numbers:code.querySelectorAll('.md-code-number[aria-hidden=true]').length};
      });
      """, arguments: [:], in: nil, contentWorld: .defaultClient)
    let values = try #require(result as? [[String: Any]])
    #expect(values.count == languages.count)
    for (index, value) in values.enumerated() {
      let text = try #require(value["text"] as? String)
      let selected = try #require(value["selected"] as? String)
      #expect(text.utf8.elementsEqual(body.utf8), "\(languages[index])")
      #expect(
        selected.utf8.elementsEqual(body.utf8), "\(languages[index]): \(selected.debugDescription)")
      #expect(value["numbers"] as? Int == 5, "\(languages[index])")
    }
  }

  @Test(
    "Number gutters align with wrapped logical lines and preserve custom labels",
    arguments: [false, true], [300, 650])
  func wrapping(dark: Bool, width: Int) async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.codeLineNumbers = true
    options.codeBlockAccessory = .custom
    let code =
      "/* " + String(repeating: "wrapping comment ", count: 35)
      + "\nend */\nlet value = 42\n\nlast()\n"
    let css = "pre,pre>code{white-space:pre-wrap;font:14px/21px monospace;} pre{margin:0;}"
    let sheet = try DocumentStylesheet(data: Data(css.utf8))
    let style = DocumentStyle(presentation: .stylesheet(sheet))
    let export = try await MarkdownExport.build(
      source: "```swift:File 中文.swift\n" + code + "```",
      options: options, title: "Code", directory: nil, style: style)
    let surface = NativeWebOutput()
    defer { surface.close() }
    surface.view.setFrameSize(.init(width: width, height: 900))
    surface.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    try await surface.prepare(html: export.document)
    let result = try await surface.view.callAsyncJavaScript(
      """
      const code=document.querySelector('pre>code'), lines=[...code.querySelectorAll('.md-code-line')];
      const rect=e=>{const r=e.getBoundingClientRect(); return {top:r.top,left:r.left,height:r.height,width:r.width}};
      return {text:code.textContent, label:document.querySelector('.md-code-label').textContent,
        lineHeight:parseFloat(getComputedStyle(code).lineHeight),
        rows:lines.map(line=>{const marker=line.querySelector('.md-code-number');
          const walker=document.createTreeWalker(line,NodeFilter.SHOW_TEXT); const text=walker.nextNode();
          let textLeft=null; if(text && text.length){const r=document.createRange();r.setStart(text,0);r.setEnd(text,1);textLeft=r.getBoundingClientRect().left;}
          return {line:rect(line),marker:rect(marker),number:marker.dataset.line,textLeft};})};
      """, arguments: [:], in: nil, contentWorld: .defaultClient)
    let value = try #require(result as? [String: Any])
    #expect((value["text"] as? String)?.utf8.elementsEqual(code.utf8) == true)
    #expect(value["label"] as? String == "File 中文.swift")
    let rows = try #require(value["rows"] as? [[String: Any]])
    let lineHeight = try #require(value["lineHeight"] as? Double)
    #expect(rows.count == 5)
    var expectedTop: Double?
    var firstLeft: Double?
    for (index, row) in rows.enumerated() {
      let line = try #require(row["line"] as? [String: Double])
      let marker = try #require(row["marker"] as? [String: Double])
      let top = try #require(line["top"])
      let height = try #require(line["height"])
      #expect(row["number"] as? String == String(index + 1))
      #expect(abs(try #require(marker["top"]) - top) < 1)
      if let expectedTop { #expect(abs(top - expectedTop) < 1) }
      expectedTop = top + height
      #expect(height >= lineHeight - 1)
      if let textLeft = row["textLeft"] as? Double {
        if let firstLeft { #expect(abs(textLeft - firstLeft) < 1) } else { firstLeft = textLeft }
      }
      if index == 0 { #expect(height > lineHeight * 2) }
    }
  }

  @Test(
    "Changing code presentation retains both directions of an existing code selection",
    arguments: [false, true])
  func presentationSelection(backward: Bool) async throws {
    _ = NSApplication.shared
    let processor = MarkdownProcessor()
    let source = "```swift:Selection.swift\n" + body + "```"
    let first = try await processor.render(source)
    let coordinator = NativeMarkdownPreview.Coordinator()
    let view = WKWebView(
      frame: .init(x: 0, y: 0, width: 600, height: 450),
      configuration: NativeMarkdownPreview.configuration(handler: coordinator.resources))
    view.navigationDelegate = coordinator
    let window = NSWindow(
      contentRect: view.frame, styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderFront(nil)
    defer {
      view.stopLoading()
      view.navigationDelegate = nil
      coordinator.resources.cancelAll()
      window.close()
    }
    func evaluate(_ script: String, arguments: [String: Any] = [:]) async throws -> String {
      try #require(
        try await view.callAsyncJavaScript(
          script, arguments: arguments, in: nil, contentWorld: .defaultClient) as? String)
    }
    func waitFor(_ condition: () async throws -> Bool) async throws {
      for _ in 0..<200 {
        if try await condition() { return }
        try await Task.sleep(for: .milliseconds(25))
      }
      throw CocoaError(.coderReadCorrupt)
    }
    coordinator.update(view, html: first.html, directory: nil, remoteImages: false)
    try await waitFor {
      try await evaluate("return String(document.querySelector('pre>code')!==null);") == "true"
    }
    let selected = try await evaluate(
      """
      const code=document.querySelector('pre>code'),node=code.firstChild;
      const start=4,end=node.length-1, selection=window.getSelection();
      selection.setBaseAndExtent(node,backward?end:start,node,backward?start:end);
      return selection.toString();
      """, arguments: ["backward": backward])
    for (numbers, accessory) in [
      (true, CodeBlockAccessory.custom), (false, .custom), (true, .none), (true, .language),
      (false, .none),
    ] {
      var options = MarkdownRenderingOptions()
      options.codeLineNumbers = numbers
      options.codeBlockAccessory = accessory
      let output = try await processor.render(source, options: options)
      coordinator.update(view, html: output.html, directory: nil, remoteImages: false)
      try await waitFor {
        try await evaluate(
          "return String(document.querySelector('pre').hasAttribute('data-code-numbered')===numbered && (document.querySelector('.md-code-label')!==null)===labelled);",
          arguments: ["numbered": numbers, "labelled": accessory != .none]) == "true"
      }
      #expect(try await evaluate("return window.getSelection().toString();") == selected)
      #expect(
        try await evaluate(
          """
          const code=document.querySelector('pre>code'),selection=window.getSelection();
          const offset=(node,n)=>{const r=document.createRange();r.selectNodeContents(code);r.setEnd(node,n);return r.toString().length;};
          return String(offset(selection.anchorNode,selection.anchorOffset)=== (backward?code.textContent.length-1:4)
            && offset(selection.focusNode,selection.focusOffset)=== (backward?4:code.textContent.length-1));
          """, arguments: ["backward": backward]) == "true")
    }
  }

  @Test(
    "Reading styles and every code theme keep numbered code selectable", arguments: [false, true])
  func stylesAndThemes(dark: Bool) async throws {
    _ = NSApplication.shared
    let repository = ReadingStyleRepository()
    var styles: [DocumentStyle] = []
    for entry in ReadingStyleEntry.all {
      styles.append(DocumentStyle(presentation: try await repository.load(entry.id)))
    }
    for theme in CodeHighlightTheme.allCases where theme != .adaptive {
      styles.append(DocumentStyle(codeTheme: theme))
    }
    let code = "let value = 42\n\nprint(value)\n"
    var options = MarkdownRenderingOptions()
    options.codeLineNumbers = true
    options.codeBlockAccessory = .language
    for style in styles {
      let output = try await MarkdownExport.build(
        source: "```swift\n" + code + "```", options: options,
        title: "Style", directory: nil, style: style)
      let surface = NativeWebOutput()
      defer { surface.close() }
      surface.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
      try await surface.prepare(html: output.document)
      let result = try await surface.view.callAsyncJavaScript(
        """
        const code=document.querySelector('pre>code'), lines=[...code.querySelectorAll('.md-code-line')];
        const range=document.createRange();range.selectNodeContents(code);
        const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);
        return {text:code.textContent,selected:selection.toString(),label:document.querySelector('.md-code-label').textContent,
          rows:lines.map(line=>{const marker=line.querySelector('.md-code-number');
            const rect=line.getBoundingClientRect(), number=marker.getBoundingClientRect();
            return Math.abs(rect.top-number.top)<1 && rect.height>0 && number.width>0;})};
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
      let value = try #require(result as? [String: Any])
      #expect((value["text"] as? String)?.utf8.elementsEqual(code.utf8) == true)
      #expect((value["selected"] as? String)?.utf8.elementsEqual(code.utf8) == true)
      #expect(value["label"] as? String == "Swift")
      #expect(value["rows"] as? [Bool] == [true, true, true])
    }
  }

  @Test(
    "Code presentation remains portable through native PDF without document styles or highlighting")
  func portablePDF() async throws {
    _ = NSApplication.shared
    var options = MarkdownRenderingOptions()
    options.codeHighlighting = false
    options.codeLineNumbers = true
    options.codeBlockAccessory = .custom
    let export = try await MarkdownExport.build(
      source: "```text:Portable.swift\nFirst checkpoint\nSecond checkpoint\n```",
      options: options, title: "Code", directory: nil, includeStyles: false)
    #expect(!export.document.contains("id=\"document-style\""))
    #expect(export.document.contains("id=\"code-style\""))
    #expect(!export.document.contains("token keyword") && !export.document.contains("<script"))
    let surface = NativeWebOutput()
    defer { surface.close() }
    try await surface.prepare(html: export.document)
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: path) }
    let info = NativeWebOutput.printInfo(allPages: true)
    info.paperSize = .init(width: 612, height: 792)
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
    let window = NSWindow(
      contentRect: .init(x: 0, y: 0, width: 720, height: 900),
      styleMask: .titled, backing: .buffered, defer: false)
    window.animationBehavior = .none
    window.isReleasedWhenClosed = false
    defer { window.close() }
    #expect(await surface.printDocument(info: info, for: window, showPanel: false))
    let pdf = try #require(PDFDocument(url: path))
    let text = try #require(pdf.string)
    #expect(
      text.contains("Portable.swift") && text.contains("First checkpoint")
        && text.contains("Second checkpoint"))
    #expect(pdf.pageCount == 1)
  }
}
