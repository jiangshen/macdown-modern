import CoreFoundation
import Darwin
import Dispatch
import Foundation

public enum CommandLineConnectionError: Error, Equatable, LocalizedError, Sendable {
  case unavailable, rejected
  case transport(Int32)

  public var errorDescription: String? {
    switch self {
    case .unavailable:
      "Snowfolio's command-line connection is not available. Reopen the app and try again."
    case .rejected: "Snowfolio did not acknowledge this command-line request."
    case .transport(let code): "The command-line request could not reach Snowfolio (\(code))."
    }
  }
}

private struct CommandLineReceipt: Codable {
  let version: Int
  let processID: Int32
  let accepted: Bool
}

/// Local Mach messaging is named for the selected GUI process. No Markdown enters
/// launch URLs, shared defaults or temporary files. Only the small receipt returns
/// synchronously; document decoding and opening remain asynchronous in the app.
public enum CommandLineConnection {
  static func name(for processID: Int32) -> CFString {
    "local.snowfolio.cli.\(getuid()).\(processID)" as CFString
  }

  @concurrent public static func send(
    _ data: Data, to processID: Int32, timeout: Duration = .seconds(8)
  ) async throws {
    guard processID > 0 else { throw CommandLineConnectionError.unavailable }
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var endpoint: CFMessagePort?
    repeat {
      try Task.checkCancellation()
      endpoint = CFMessagePortCreateRemote(nil, name(for: processID))
      if endpoint != nil { break }
      guard ContinuousClock.now < deadline else { throw CommandLineConnectionError.unavailable }
      try await Task.sleep(for: .milliseconds(25))
    } while true
    guard let endpoint else { throw CommandLineConnectionError.unavailable }
    let remaining = ContinuousClock.now.duration(to: deadline).components
    let budget = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
    guard budget > 0 else { throw CommandLineConnectionError.unavailable }
    let sendBudget = min(1, budget / 2)
    var reply: Unmanaged<CFData>?
    let result = CFMessagePortSendRequest(
      endpoint, 1, data as CFData, sendBudget, budget - sendBudget,
      CFRunLoopMode.defaultMode.rawValue, &reply)
    let bytes = reply?.takeRetainedValue()
    try Task.checkCancellation()
    guard result == kCFMessagePortSuccess else {
      throw CommandLineConnectionError.transport(result)
    }
    guard let bytes,
      let receipt = try? JSONDecoder().decode(CommandLineReceipt.self, from: bytes as Data),
      receipt.version == 1, receipt.processID == processID, receipt.accepted
    else { throw CommandLineConnectionError.rejected }
  }
}

/// CF's C callback is dispatched exclusively onto the main queue. A retained
/// context with a weak owner prevents callbacks from outliving their Swift owner.
@MainActor
public final class CommandLineMessageServer {
  @MainActor private final class Context {
    weak var owner: CommandLineMessageServer?
    init(owner: CommandLineMessageServer) { self.owner = owner }
  }

  private var port: CFMessagePort?
  private let receive: @MainActor (Data) -> Void

  public init(receive: @escaping @MainActor (Data) -> Void) { self.receive = receive }

  public func start() throws {
    guard port == nil else { return }
    let box = Context(owner: self)
    var context = CFMessagePortContext(
      version: 0, info: Unmanaged.passUnretained(box).toOpaque(),
      retain: { pointer in
        guard let pointer else { return nil }
        _ = Unmanaged<Context>.fromOpaque(pointer).retain()
        return pointer
      },
      release: { pointer in
        if let pointer { Unmanaged<Context>.fromOpaque(pointer).release() }
      }, copyDescription: nil)
    var contextUnused = DarwinBoolean(false)
    guard
      let created = CFMessagePortCreateLocal(
        nil, CommandLineConnection.name(for: getpid()),
        { _, version, bytes, info in
          guard let bytes, let info, let copy = CFDataCreateCopy(nil, bytes) else { return nil }
          let payload = copy as Data
          let box = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
          // CFMessagePortSetDispatchQueue below guarantees this callback's executor.
          let reply = MainActor.assumeIsolated {
            box.owner?.accept(version: version, data: payload)
          }
          guard let reply else { return nil }
          return Unmanaged.passRetained(reply as CFData)
        }, &context, &contextUnused), !contextUnused.boolValue
    else { throw CommandLineConnectionError.unavailable }
    port = created
    CFMessagePortSetDispatchQueue(created, DispatchQueue.main)
  }

  func accept(version: Int32, data: Data) -> Data? {
    let accepted = version == 1 && !data.isEmpty
    if accepted { receive(data) }
    return try? JSONEncoder().encode(
      CommandLineReceipt(version: 1, processID: getpid(), accepted: accepted))
  }

  public func stop() {
    if let port { CFMessagePortInvalidate(port) }
    port = nil
  }

  isolated deinit {
    if let port { CFMessagePortInvalidate(port) }
  }
}
