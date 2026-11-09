import AppKit

extension NativeMarkdownDocument {
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
