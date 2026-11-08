import Testing

@testable import EditorCore

@Suite("Source column geometry")
struct EditorLayoutPreferencesTests {
  @Test("A width limit centers the column and narrow panes keep their minimum margins")
  func columns() {
    var settings = EditorLayoutPreferences(
      horizontalInset: 20, verticalInset: 30, widthLimited: true, maximumWidth: 600)
    let wide = settings.geometry(viewWidth: 1000)
    #expect(wide.columnWidth == 600 && wide.horizontalInset == 200 && wide.verticalInset == 30)
    let narrow = settings.geometry(viewWidth: 500)
    #expect(narrow.columnWidth == 460 && narrow.horizontalInset == 20)
    settings.widthLimited = false
    #expect(settings.geometry(viewWidth: 1000).columnWidth == 960)
  }

  @Test(
    "Damaged preferences and tiny viewports cannot create nonfinite or negative geometry",
    arguments: [0.0, 1, 30, 240, 20_000, -.infinity, .infinity, .nan])
  func bounds(width: Double) {
    var settings = EditorLayoutPreferences(
      horizontalInset: -.infinity, verticalInset: 100, maximumWidth: .nan)
    settings.horizontalInset = -4
    settings.verticalInset = .nan
    settings.maximumWidth = 20_000
    #expect(
      settings.horizontalInset == 0 && settings.verticalInset == 24
        && settings.maximumWidth == 10_000)
    let geometry = settings.geometry(viewWidth: width)
    #expect(geometry.columnWidth.isFinite && geometry.columnWidth >= 1)
    #expect(geometry.horizontalInset.isFinite && geometry.horizontalInset >= 0)
  }
}
