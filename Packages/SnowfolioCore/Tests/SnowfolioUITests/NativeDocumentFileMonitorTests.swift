import Foundation
import Testing

@testable import SnowfolioUI

// Callback deadlines share the main actor with window/layout fixtures. Keep
// those workloads separate without extending waits or changing event assertions.
@Suite("Native document directory events", .serialized, NativeUIExclusive())
@MainActor
struct NativeDocumentFileMonitorTests {
  enum Failure: Error { case timeout }

  private func waitFor(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while ContinuousClock.now < deadline {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(20))
    }
    throw Failure.timeout
  }

  @Test("Atomic replacement is detected without notifying for unrelated sibling writes")
  func atomicReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioFileMonitor-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("document.md")
    let sibling = root.appendingPathComponent("unrelated.txt")
    try Data("original".utf8).write(to: file)
    let monitor = NativeDocumentFileMonitor()
    defer {
      monitor.stop()
      try? FileManager.default.removeItem(at: root)
    }
    var events: [URL] = []
    monitor.didChange = { events.append($0) }
    monitor.observe(file)
    try await waitFor { events.count == 1 }
    let replacement = Data("externally replaced 中文 👩‍💻".utf8)
    try replacement.write(to: file, options: .atomic)
    try await waitFor { events.count == 2 }
    #expect(events == [file, file])
    #expect(try Data(contentsOf: file) == replacement)
    try Data("sibling".utf8).write(to: sibling, options: .atomic)
    try await Task.sleep(for: .milliseconds(200))
    #expect(events.count == 2)
  }

  @Test("Changing file location detaches the old directory and stopping cancels pending events")
  func rebindAndStop() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnowfolioFileMonitor-\(UUID().uuidString)", isDirectory: true)
    let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
    let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
    for directory in [firstDirectory, secondDirectory] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let first = firstDirectory.appendingPathComponent("document.md")
    let second = secondDirectory.appendingPathComponent("document.md")
    for file in [first, second] { try Data("original".utf8).write(to: file) }
    let monitor = NativeDocumentFileMonitor()
    defer {
      monitor.stop()
      try? FileManager.default.removeItem(at: root)
    }
    var events: [URL] = []
    monitor.didChange = { events.append($0) }
    monitor.observe(first)
    try await waitFor { events.count == 1 }
    monitor.observe(second)
    try await waitFor { events.count == 2 }
    try Data("retired location".utf8).write(to: first, options: .atomic)
    try await Task.sleep(for: .milliseconds(200))
    #expect(events == [first, second])
    try Data("active location".utf8).write(to: second, options: .atomic)
    try await waitFor { events.count == 3 }
    #expect(events == [first, second, second])
    monitor.stop()
    try Data("after stop".utf8).write(to: second, options: .atomic)
    try await Task.sleep(for: .milliseconds(200))
    #expect(events.count == 3)
  }
}
