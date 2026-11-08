import Foundation
import Testing

@testable import SnowfolioUI

@Suite("Per-window workspace restoration")
@MainActor
struct DocumentWorkspaceStateTests {
  @Test("Documents restore independent layout, zoom, selection and both viewports")
  func independentState() throws {
    let first = DocumentWorkspaceState()
    first.sourceViewport = Data("source viewport".utf8)
    first.previewViewport = Data("preview viewport".utf8)
    first.editorSelection = Data("selection".utf8)
    first.zoomPercent = 125
    first.mode = .editor
    let second = DocumentWorkspaceState()
    second.mode = .preview
    second.zoomPercent = 80
    let restored = DocumentWorkspaceState()
    #expect(restored.restore(from: try first.encoded()))
    #expect(restored.sourceViewport == first.sourceViewport)
    #expect(restored.previewViewport == first.previewViewport)
    #expect(restored.editorSelection == first.editorSelection)
    #expect(restored.zoomPercent == 125)
    #expect(restored.mode == .editor)
    restored.mode = .split
    #expect(first.mode == .editor)
    #expect(second.mode == .preview)
    #expect(second.zoomPercent == 80)
    #expect(second.editorSelection == nil)
  }

  @Test("Invalid or unsupported saved state leaves the live window state intact")
  func invalidRestore() throws {
    let state = DocumentWorkspaceState()
    state.mode = .preview
    state.zoomPercent = 150
    state.editorSelection = Data([1, 2, 3])
    #expect(!state.restore(from: Data("invalid".utf8)))
    var object = try #require(
      JSONSerialization.jsonObject(with: state.encoded()) as? [String: Any])
    object["version"] = 2
    object["zoomPercent"] = 50
    #expect(!state.restore(from: try JSONSerialization.data(withJSONObject: object)))
    #expect(state.mode == .preview)
    #expect(state.zoomPercent == 150)
    #expect(state.editorSelection == Data([1, 2, 3]))
  }

  @Test("A retired workspace mode falls back to split while retaining valid UI state")
  func unknownMode() throws {
    let state = DocumentWorkspaceState()
    state.zoomPercent = 125
    var object = try #require(
      JSONSerialization.jsonObject(with: state.encoded()) as? [String: Any])
    object["mode"] = "retired"
    #expect(state.restore(from: try JSONSerialization.data(withJSONObject: object)))
    #expect(state.mode == .split)
    #expect(state.zoomPercent == 125)
  }
}
