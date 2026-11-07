import EmojiCore
import Foundation
import MarkdownCore
import SwiftUI

struct EmojiPicker: View {
  let choose: @MainActor (String?) -> Bool
  @State private var entries: [EmojiEntry] = []
  @State private var search = ""
  @State private var category = "All"
  @State private var error: String?
  @FocusState private var searchFocused: Bool
  @AppStorage("recentCalloutEmoji") private var recentData = ""
  private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 9)
  private let suggested = [
    "💡", "👉", "☝️", "👌", "🔑", "🚧", "⚠️", "🔥", "📌", "✂️", "❓", "🚫", "⛔️", "⏰", "☎️", "🚨", "♻️", "✅", "🔒",
    "📎", "📖", "🗣️", "➡️", "📢", "🛠️", "⚙️", "🎯",
  ]

  private var filtered: [EmojiEntry] {
    let terms = search.lowercased().split(whereSeparator: \.isWhitespace)
    return entries.filter { entry in
      (category == "All" || entry.group == category)
        && (terms.isEmpty
          || terms.allSatisfy {
            entry.name.localizedCaseInsensitiveContains(String($0)) || entry.glyph.contains($0)
          })
    }
  }

  private var recent: [String] { recentData.split(separator: " ").map(String.init) }
  private var categories: [String] { Array(Set(entries.map(\.group))).sorted() }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Emoji").font(.headline)
        Spacer()
        Button("Reset") { select(nil) }.buttonStyle(.borderless)
          .help("Restore the callout’s default icon")
          .accessibilityIdentifier("resetCalloutEmoji")
      }
      HStack(spacing: 8) {
        TextField("Search emoji", text: $search).textFieldStyle(.roundedBorder)
          .focused($searchFocused).accessibilityIdentifier("emojiSearch")
          .onSubmit { if let entry = filtered.first { select(entry.glyph) } }
        Button {
          if let entry = entries.randomElement() { select(entry.glyph) }
        } label: {
          Image(systemName: "shuffle")
        }.help("Choose a random emoji").accessibilityLabel("Random emoji")
          .accessibilityIdentifier("randomCalloutEmoji").disabled(entries.isEmpty)
      }
      Picker("Category", selection: $category) {
        Text("All emoji").tag("All")
        ForEach(categories, id: \.self) { group in
          Text(group).tag(group)
        }
      }.accessibilityIdentifier("emojiCategory")
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if search.isEmpty, category == "All" {
            if !recent.isEmpty { section("Recent", glyphs: recent, identifier: "recent") }
            section("Callout", glyphs: suggested, identifier: "suggested")
            Text("All emoji").font(.caption).foregroundStyle(.secondary)
          }
          LazyVGrid(columns: columns, spacing: 4) {
            ForEach(filtered) { entry in emojiButton(entry.glyph, name: entry.name) }
          }
          if !entries.isEmpty, filtered.isEmpty {
            ContentUnavailableView.search(text: search)
          }
        }.padding(.vertical, 4)
      }.accessibilityIdentifier("emojiGrid")
      if let error {
        Text(error).font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("emojiPickerError")
      }
    }
    .padding(16).frame(width: 388, height: 470)
    .task {
      searchFocused = true
      do {
        let loaded = try await EmojiDisplayCatalog.load()
        try Task.checkCancellation()
        entries = loaded
      } catch is CancellationError {
      } catch {
        self.error = String(localized: "Emoji could not load. Close the picker and try again.")
      }
    }
  }

  private func section(_ title: LocalizedStringKey, glyphs: [String], identifier: String)
    -> some View
  {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      LazyVGrid(columns: columns, spacing: 4) {
        ForEach(glyphs, id: \.self) { glyph in
          emojiButton(
            glyph, name: entries.first(where: { $0.glyph == glyph })?.name ?? glyph,
            namespace: identifier)
        }
      }
    }
  }

  private func emojiButton(_ glyph: String, name: String, namespace: String = "catalog")
    -> some View
  {
    Button {
      select(glyph)
    } label: {
      Text(glyph).font(.system(size: 25)).frame(width: 34, height: 34)
        .contentShape(.rect)
    }.buttonStyle(.plain).help(name).accessibilityLabel(name)
      .accessibilityIdentifier("emoji-" + namespace + "-" + glyph)
  }

  private func select(_ emoji: String?) {
    guard choose(emoji) else {
      error = String(localized: "The callout changed. Close this picker and choose its icon again.")
      return
    }
    if let emoji, CalloutMarker.isEmoji(emoji) {
      var recent = recentData.split(separator: " ").map(String.init).filter { $0 != emoji }
      recent.insert(emoji, at: 0)
      recentData = recent.prefix(24).joined(separator: " ")
    }
  }
}
