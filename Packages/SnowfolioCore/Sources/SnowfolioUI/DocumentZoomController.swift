import Observation
import SwiftUI

/// Per-document reading magnification. Base font preferences and exports are separate.
@MainActor
@Observable
public final class DocumentZoomController {
  private static let steps = [50, 67, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300]
  public private(set) var percent = 100
  @ObservationIgnored private var userAdjusted = false

  public init() {}
  public var scale: Double { Double(percent) / 100 }
  public var canZoomIn: Bool { percent < 300 }
  public var canZoomOut: Bool { percent > 50 }
  public var canReset: Bool { percent != 100 }

  func restore(percent: Int) {
    guard !userAdjusted else { return }
    self.percent = min(300, max(50, percent))
  }

  /// File state takes precedence over scene restoration; user intent wins over both.
  func configure(fileURL: URL?, scenePercent: Int, store: DocumentReadingStore = .shared) {
    if !userAdjusted {
      restore(percent: fileURL.flatMap { store.entry(for: $0)?.zoomPercent } ?? scenePercent)
    } else if let fileURL {
      store.save(zoomPercent: percent, for: fileURL)
    }
  }

  func persist(fileURL: URL?, store: DocumentReadingStore = .shared) {
    if let fileURL { store.save(zoomPercent: percent, for: fileURL) }
  }

  public func zoomIn() {
    userAdjusted = true
    percent = Self.steps.first(where: { $0 > percent }) ?? 300
  }

  public func zoomOut() {
    userAdjusted = true
    percent = Self.steps.last(where: { $0 < percent }) ?? 50
  }

  public func reset() {
    userAdjusted = true
    percent = 100
  }

  static func normalizedScale(_ scale: Double) -> Double {
    scale.isFinite ? min(3, max(0.5, scale)) : 1
  }

  static func sourceFontSize(base: Double, scale: Double) -> Double {
    let base = base.isFinite ? min(72, max(8, base)) : 14
    return base * normalizedScale(scale)
  }

  static func previewScale(workspace: Double, baseFontSize: Double, followsEditor: Bool) -> Double {
    let base = baseFontSize.isFinite ? min(72, max(8, baseFontSize)) : 14
    return normalizedScale(workspace) * (followsEditor ? base / 14 : 1)
  }
}

extension FocusedValues {
  @Entry public var documentZoom: DocumentZoomController?
}

public struct DocumentZoomCommands: Commands {
  @FocusedValue(\.documentZoom) private var zoom
  public init() {}

  public var body: some Commands {
    CommandGroup(before: .sidebar) {
      DocumentZoomMenuContent(zoom: zoom)
    }
  }
}

struct DocumentZoomMenuContent: View {
  let zoom: DocumentZoomController?

  var body: some View {
    Group {
      Button("Zoom In") { zoom?.zoomIn() }
        .keyboardShortcut("+", modifiers: [.command, .option])
        .disabled(zoom?.canZoomIn != true)
        .accessibilityIdentifier("zoomInCommand")
      Button("Zoom Out") { zoom?.zoomOut() }
        .keyboardShortcut("-", modifiers: [.command, .option])
        .disabled(zoom?.canZoomOut != true)
        .accessibilityIdentifier("zoomOutCommand")
      Button("Actual Size") { zoom?.reset() }
        .keyboardShortcut("0", modifiers: [.command, .option])
        .disabled(zoom?.canReset != true)
        .accessibilityIdentifier("resetZoomCommand")
    }
  }
}
