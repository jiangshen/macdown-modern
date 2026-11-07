import Testing

/// NSApplication's windows, focus and print services are process-wide. Different
/// native suites must not change them simultaneously across suspension points.
struct NativeUIExclusive: SuiteTrait, TestScoping {
  var isRecursive: Bool { false }

  func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    await NativeUITestGate.shared.acquire()
    do {
      try await function()
      await NativeUITestGate.shared.release()
    } catch {
      await NativeUITestGate.shared.release()
      throw error
    }
  }
}

private actor NativeUITestGate {
  static let shared = NativeUITestGate()
  private var held = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func acquire() async {
    if held {
      await withCheckedContinuation { waiters.append($0) }
    } else {
      held = true
    }
  }

  func release() {
    if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
  }
}
