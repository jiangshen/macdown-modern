import Darwin
import Foundation
import Testing

@testable import DocumentCore

@Suite("Acknowledged command-line connection", .serialized)
@MainActor
struct CommandLineConnectionTests {
  @Test("The receiver acknowledges queued bytes and preserves large payloads after the callback")
  func loopback() async throws {
    var received: [Data] = []
    let server = CommandLineMessageServer { received.append($0) }
    try server.start()
    defer { server.stop() }
    let small = Data("# 中文 🧊 e\u{301}\r\n".utf8)
    let large = Data(String(repeating: "中文 🧊 e\u{301}\r\n", count: 150_000).utf8)
    try await CommandLineConnection.send(small, to: getpid())
    try await CommandLineConnection.send(large, to: getpid())
    await Task.yield()
    #expect(received == [small, large])
  }

  @Test("A duplicate receiver never replaces or invalidates the first owner")
  func duplicate() async throws {
    var received: [Data] = []
    let first = CommandLineMessageServer { received.append($0) }
    try first.start()
    defer { first.stop() }
    let second = CommandLineMessageServer { _ in Issue.record("Duplicate owner received data") }
    #expect(throws: CommandLineConnectionError.unavailable) { try second.start() }
    second.stop()
    let bytes = Data("Keep original receiver".utf8)
    try await CommandLineConnection.send(bytes, to: getpid())
    #expect(received == [bytes])
  }

  @Test("Unsupported protocol versions and empty payloads are rejected without queueing")
  func rejected() throws {
    var received = false
    let server = CommandLineMessageServer { _ in received = true }
    for (version, data) in [(Int32(2), Data("future".utf8)), (Int32(1), Data())] {
      let reply = try #require(server.accept(version: version, data: data))
      let object = try #require(JSONSerialization.jsonObject(with: reply) as? [String: Any])
      #expect(object["accepted"] as? Bool == false)
      #expect(object["processID"] as? Int32 == getpid())
    }
    #expect(!received)
  }

  @Test("The CF context does not retain its owner and stopped connections fail")
  func lifetime() async throws {
    var server: CommandLineMessageServer? = CommandLineMessageServer { _ in }
    weak let observed = server
    try server?.start()
    server?.stop()
    server = nil
    #expect(observed == nil)
    await #expect(throws: (any Error).self) {
      try await CommandLineConnection.send(
        Data("closed".utf8), to: getpid(), timeout: .milliseconds(100))
    }
  }

  @Test("Cancellation and invalid process identities never report delivery")
  func cancellation() async throws {
    await #expect(throws: CommandLineConnectionError.unavailable) {
      try await CommandLineConnection.send(Data("invalid".utf8), to: 0)
    }
    let pending = Task {
      try await CommandLineConnection.send(Data("cancelled".utf8), to: Int32.max)
    }
    pending.cancel()
    await #expect(throws: CancellationError.self) { try await pending.value }
  }
}
