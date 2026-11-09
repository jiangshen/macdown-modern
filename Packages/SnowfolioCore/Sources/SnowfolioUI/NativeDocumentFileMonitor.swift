import Darwin
import Dispatch
import Foundation

/// Directory events include atomic replacement by editors that do not coordinate
/// writes. They only wake the native file presenter; this object never reads or
/// replaces document contents, writes files, or decides whether to discard edits.
@MainActor
final class NativeDocumentFileMonitor {
  private var source: (any DispatchSourceFileSystemObject)?
  private var pending: Task<Void, Never>?
  private var url: URL?
  private var signature: FileSignature?
  private var generation: UInt64 = 0
  var didChange: (@MainActor (URL) -> Void)?

  func observe(_ url: URL?) {
    guard self.url != url || source == nil else { return }
    stop()
    guard let url, url.isFileURL else { return }
    self.url = url
    let generation = generation
    pending = Task { [weak self] in
      let opened = await FileProbe.openParent(of: url)
      guard let self, self.generation == generation, !Task.isCancelled else {
        if let opened { Darwin.close(opened.descriptor) }
        return
      }
      guard let opened else { return }
      signature = opened.signature
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: opened.descriptor,
        eventMask: [.write, .rename, .delete, .attrib, .extend, .link, .revoke],
        queue: .global(qos: .utility))
      // Legacy dispatch callbacks must not inherit MainActor isolation when
      // the utility queue invokes them; hop explicitly only for owned UI state.
      source.setCancelHandler { @Sendable in Darwin.close(opened.descriptor) }
      source.setEventHandler { @Sendable [weak self] in
        Task { @MainActor [weak self] in self?.scheduleCheck() }
      }
      self.source = source
      source.resume()
      // Also ask the native presenter to compare its known file date after
      // arming, covering changes between the native read and monitor setup.
      didChange?(url)
      scheduleCheck()
    }
  }

  private func scheduleCheck() {
    pending?.cancel()
    let generation = generation
    guard let url else { return }
    pending = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
      let current = await FileProbe.signature(at: url)
      guard let self, self.generation == generation, !Task.isCancelled,
        signature != current
      else { return }
      signature = current
      didChange?(url)
    }
  }

  func stop() {
    generation &+= 1
    pending?.cancel()
    pending = nil
    source?.cancel()
    source = nil
    url = nil
    signature = nil
  }

  isolated deinit {
    pending?.cancel()
    source?.cancel()
  }
}

private struct FileSignature: Equatable, Sendable {
  let device: Int32
  let inode: UInt64
  let size: Int64
  let seconds: Int
  let nanoseconds: Int
}

private enum FileProbe {
  struct Opened: Sendable {
    let descriptor: Int32
    let signature: FileSignature?
  }

  @concurrent
  static func openParent(of url: URL) async -> Opened? {
    let descriptor = url.deletingLastPathComponent().withUnsafeFileSystemRepresentation {
      $0.map { Darwin.open($0, O_EVTONLY) } ?? -1
    }
    guard descriptor >= 0 else { return nil }
    return Opened(descriptor: descriptor, signature: readSignature(at: url))
  }

  @concurrent
  static func signature(at url: URL) async -> FileSignature? { readSignature(at: url) }

  private static func readSignature(at url: URL) -> FileSignature? {
    var status = stat()
    let result = url.withUnsafeFileSystemRepresentation {
      $0.map { Darwin.fstatat(AT_FDCWD, $0, &status, 0) } ?? -1
    }
    guard result == 0 else { return nil }
    return FileSignature(
      device: status.st_dev, inode: status.st_ino, size: status.st_size,
      seconds: status.st_mtimespec.tv_sec, nanoseconds: status.st_mtimespec.tv_nsec)
  }
}
