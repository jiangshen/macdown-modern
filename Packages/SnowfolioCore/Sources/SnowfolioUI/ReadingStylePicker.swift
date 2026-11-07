import RenderingCore
import SwiftUI

struct ReadingStylePicker: View {
  let library: ReadingStyleLibrary
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Picker(
          "Document style",
          selection: Binding(
            get: { library.selection }, set: { id in Task { await library.select(id) } }
          )
        ) {
          ForEach(library.entries.filter { $0.origin == .builtIn }) { Text($0.title).tag($0.id) }
          ForEach([ReadingStyleEntry.Origin.local, .legacy, .imported], id: \.self) { origin in
            let choices = library.entries.filter { $0.origin == origin }
            if !choices.isEmpty {
              Section(title(origin)) {
                ForEach(choices) { Text($0.title).tag($0.id) }
              }
            }
          }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("readingStyle")
        Button("Reload", systemImage: "arrow.clockwise") { Task { await library.refresh() } }
          .labelStyle(.iconOnly).help("Reload document style")
          .disabled(library.isLoading).accessibilityIdentifier("reloadReadingStyle")
      }
      if let message = library.message {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(
            "readingStyleStatus")
      }
    }
    .task { await library.loadIfNeeded() }
  }
  private func title(_ origin: ReadingStyleEntry.Origin) -> LocalizedStringKey {
    switch origin {
    case .builtIn: "Built-in Styles"
    case .local: "Styles Folder"
    case .legacy: "From MacDown"
    case .imported: "Imported Styles"
    }
  }

}
