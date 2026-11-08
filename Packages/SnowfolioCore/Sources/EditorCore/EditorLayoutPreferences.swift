import Foundation

/// Layout in native points, independent of document bytes and text magnification.
public struct EditorLayoutPreferences: Equatable, Sendable {
  public var horizontalInset: Double {
    didSet { horizontalInset = Self.bounded(horizontalInset, 0...35, fallback: 24) }
  }
  public var verticalInset: Double {
    didSet { verticalInset = Self.bounded(verticalInset, 0...35, fallback: 24) }
  }
  public var lineSpacing: Double {
    didSet { lineSpacing = Self.bounded(lineSpacing, 0...100, fallback: 0) }
  }
  public var scrollsPastEnd: Bool
  public var widthLimited: Bool
  public var maximumWidth: Double {
    didSet { maximumWidth = Self.bounded(maximumWidth, 300...10_000, fallback: 1000) }
  }

  public init(
    horizontalInset: Double = 24, verticalInset: Double = 24,
    widthLimited: Bool = false, maximumWidth: Double = 1000, lineSpacing: Double = 0,
    scrollsPastEnd: Bool = false
  ) {
    self.horizontalInset = Self.bounded(horizontalInset, 0...35, fallback: 24)
    self.verticalInset = Self.bounded(verticalInset, 0...35, fallback: 24)
    self.lineSpacing = Self.bounded(lineSpacing, 0...100, fallback: 0)
    self.scrollsPastEnd = scrollsPastEnd
    self.widthLimited = widthLimited
    self.maximumWidth = Self.bounded(maximumWidth, 300...10_000, fallback: 1000)
  }

  public func geometry(viewWidth: Double) -> Geometry {
    let width = viewWidth.isFinite ? max(1, viewWidth) : 1
    let margin = min(horizontalInset, max(0, (width - 1) / 2))
    let available = max(1, width - 2 * margin)
    let column = widthLimited ? min(available, maximumWidth) : available
    return Geometry(
      horizontalInset: (width - column) / 2, verticalInset: verticalInset, columnWidth: column)
  }

  public struct Geometry: Equatable, Sendable {
    public let horizontalInset: Double
    public let verticalInset: Double
    public let columnWidth: Double
  }

  private static func bounded(_ value: Double, _ range: ClosedRange<Double>, fallback: Double)
    -> Double
  {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
  }
}
