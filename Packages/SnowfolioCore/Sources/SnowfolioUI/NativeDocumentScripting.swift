import AppKit

extension NativeMarkdownDocument {
  /// NSCreateCommand uses a coercion for its legacy ObjectData parameter.
  /// Register only text-to-document conversion; Cocoa still inserts the result
  /// into orderedDocuments and owns its windows, save options and specifier.
  public static func registerScriptingCoercions() {
    NSScriptCoercionHandler.shared().registerCoercer(
      self, selector: #selector(makeScriptingDocument(from:to:)),
      toConvertFrom: NSString.self, to: NativeMarkdownDocument.self)
  }

  @objc private static func makeScriptingDocument(from value: Any, to objectClass: AnyClass) -> Any?
  {
    guard objectClass === NativeMarkdownDocument.self, let source = value as? String else {
      return nil
    }
    do {
      let document = try NativeMarkdownDocument(type: "net.daringfireball.markdown")
      document.markdown = source
      return document
    } catch {
      NSScriptCommand.current()?.scriptErrorNumber = -10000
      NSScriptCommand.current()?.scriptErrorString = error.localizedDescription
      return nil
    }
  }

  /// Cocoa's Make-with-data command initializes the class's declared contents.
  /// Reuse source ownership so creation retains the same Undo and input guards.
  @objc public dynamic var scriptingContents: String {
    get { markdown }
    set { markdown = newValue }
  }

  /// Cocoa scripting keeps the historical text property and native document
  /// Undo ownership. Never replace an in-progress input-method composition.
  @objc public dynamic var markdown: String {
    get { markdownDocument.text }
    set {
      let model = markdownDocument
      guard !model.text.utf8.elementsEqual(newValue.utf8) else { return }
      guard !model.sourceEditorsHaveMarkedText else {
        NSScriptCommand.current()?.scriptErrorNumber = -10000
        NSScriptCommand.current()?.scriptErrorString = String(
          localized: "Finish the current text composition before replacing document text.")
        return
      }
      model.prepareSourceEditorsForSave()
      let manager = undoManager
      manager?.beginUndoGrouping()
      model.replaceText(with: newValue, undoManager: manager)
      manager?.setActionName(String(localized: "Set Markdown"))
      manager?.endUndoGrouping()
    }
  }

  /// Like the original app, return the last published fragment without starting
  /// a new render, blocking on WebKit, or changing manual-render behavior.
  @objc public dynamic var html: String { markdownDocument.lastRenderedHTML }
}
