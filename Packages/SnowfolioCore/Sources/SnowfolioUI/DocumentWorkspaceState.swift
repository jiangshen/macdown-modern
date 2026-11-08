import Foundation
import Observation

/// UI state belongs to one document window. Document bytes and Undo stay with its host.
@MainActor
@Observable
final class DocumentWorkspaceState {
  var sourceViewport: Data?
  var previewViewport: Data?
  var editorSelection: Data?
  var zoomPercent = 100
  var mode = WorkspaceMode.split

  init() {}

  func encoded() throws -> Data {
    try JSONEncoder().encode(
      Snapshot(
        version: 1, sourceViewport: sourceViewport, previewViewport: previewViewport,
        editorSelection: editorSelection, zoomPercent: zoomPercent, mode: mode.rawValue))
  }

  /// Decode completely before changing live state. A failed restore leaves it intact.
  @discardableResult
  func restore(from data: Data) -> Bool {
    guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
      snapshot.version == 1
    else { return false }
    sourceViewport = snapshot.sourceViewport
    previewViewport = snapshot.previewViewport
    editorSelection = snapshot.editorSelection
    zoomPercent = snapshot.zoomPercent
    mode = WorkspaceMode(rawValue: snapshot.mode) ?? .split
    return true
  }

  private struct Snapshot: Codable {
    let version: Int
    let sourceViewport: Data?
    let previewViewport: Data?
    let editorSelection: Data?
    let zoomPercent: Int
    let mode: String
  }
}
