import AppKit
import Observation
import RenderingCore
import SwiftUI

@MainActor
@Observable
public final class DocumentWritingStatistics {
  public internal(set) var value: WritingStatistics?
  public internal(set) var revision: UInt64?

  public init() {}

  func clear() {
    value = nil
    revision = nil
  }
}

/// A native popup preserves the editor's selection and offers all three old modes.
struct WritingStatisticsControl: NSViewRepresentable {
  let statistics: WritingStatistics?
  @Bindable var preferences: AppPreferences

  func makeCoordinator() -> Coordinator { Coordinator(preferences: preferences) }

  func makeNSView(context: Context) -> NSPopUpButton {
    let control = NSPopUpButton(frame: .zero, pullsDown: false)
    control.controlSize = .small
    control.isBordered = false
    control.isEnabled = false
    control.setAccessibilityIdentifier("writingStatistics")
    control.setAccessibilityLabel(String(localized: "Writing statistics"))
    control.target = context.coordinator
    control.action = #selector(Coordinator.changed(_:))
    return control
  }

  func updateNSView(_ control: NSPopUpButton, context: Context) {
    context.coordinator.preferences = preferences
    let titles = WritingStatisticsMode.allCases.map { mode in
      statistics.map { mode.title(for: $0) } ?? mode.title
    }
    if control.itemTitles != titles {
      control.removeAllItems()
      control.addItems(withTitles: titles)
    }
    control.selectItem(at: preferences.writingStatisticsMode.rawValue)
    control.isEnabled = statistics != nil
    control.toolTip = String(localized: "Counts the rendered preview. Choose a counting mode.")
  }

  @MainActor final class Coordinator: NSObject {
    var preferences: AppPreferences
    init(preferences: AppPreferences) { self.preferences = preferences }
    @objc func changed(_ sender: NSPopUpButton) {
      if let mode = WritingStatisticsMode(rawValue: sender.indexOfSelectedItem) {
        preferences.writingStatisticsMode = mode
      }
    }
  }
}
