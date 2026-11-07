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
          ForEach(ReadingStyleEntry.all) { Text($0.title).tag($0.id) }
          if !ReadingStyleEntry.all.contains(where: { $0.id == library.selection }) {
            Text("Previous style").tag(library.selection)
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
      }
    }
    .task { await library.loadIfNeeded() }
  }
}
