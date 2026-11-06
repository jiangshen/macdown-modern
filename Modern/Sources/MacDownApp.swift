import MacDownUI
import SwiftUI

@main
struct MacDownModernApp: App {
  var body: some Scene {
    DocumentGroup { (document: MarkdownDocument) in
      NativeMarkdownEditor(document: document)
        .frame(minWidth: 560, idealWidth: 880, minHeight: 360, idealHeight: 640)
    } makeDocument: { _, _ in
      MarkdownDocument()
    }
    .commands {
      TextEditingCommands()
    }
  }
}
