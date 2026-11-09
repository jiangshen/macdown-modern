import Foundation
import Testing

@testable import PluginCore

@Suite("Plug-in discovery without execution")
struct PluginCatalogTests {
  private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func bundle(in folder: URL, name: String, cpu: UInt32? = nil) throws -> URL {
    let url = folder.appendingPathComponent(name + ".plugin")
    let contents = url.appendingPathComponent("Contents")
    let binaries = contents.appendingPathComponent("MacOS")
    try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
    let info: [String: Any] = [
      "CFBundlePackageType": "BNDL", "CFBundleExecutable": "fixture",
      "CFBundleIdentifier": "local.snowfolio.metadata." + UUID().uuidString,
      "NSPrincipalClass": "SnowfolioUnloadedMetadataFixture",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
      .write(to: contents.appendingPathComponent("Info.plist"))
    if let cpu {
      // A header-only Mach-O is enough for Foundation's architecture inspection.
      // It cannot execute: there are no load commands, segments or entry point.
      var data = Data()
      for word: UInt32 in [0xfeed_facf, cpu, 0, 8, 0, 0, 0, 0] {
        var littleEndian = word.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
      }
      try data.write(to: binaries.appendingPathComponent("fixture"))
    }
    return url
  }

  @Test(
    "Architecture inspection keeps principal classes unloaded",
    arguments: [
      (UInt32(0x0100_000c), PluginAvailability.compatible),
      (UInt32(0x0100_0007), PluginAvailability.intelOnly),
      (UInt32(0x0100_0012), PluginAvailability.unsupportedArchitecture),
    ])
  func architectures(cpu: UInt32, expected: PluginAvailability) async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = try bundle(in: root, name: "Local fixture 🧊", cpu: cpu)
    let before = try #require(Bundle(url: url))
    #expect(!before.isLoaded)
    #expect(NSClassFromString("SnowfolioUnloadedMetadataFixture") == nil)
    let result = try await PluginCatalog.discover(in: [root])
    let descriptor = try #require(result.plugins.first)
    #expect(result.issues.isEmpty)
    #expect(descriptor.availability == expected)
    #expect(descriptor.architectures == [Int(cpu)])
    #expect(descriptor.fallbackName == "Local fixture 🧊")
    #expect(descriptor.principalClassName == "SnowfolioUnloadedMetadataFixture")
    #expect(!before.isLoaded)
    #expect(NSClassFromString("SnowfolioUnloadedMetadataFixture") == nil)
  }

  @Test("Universal arm64/Intel bundles remain eligible without loading either slice")
  func universal() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = try bundle(in: root, name: "Universal")
    var data = Data()
    for word: UInt32 in [
      0xcafe_babe, 2,
      0x0100_0007, 3, 4096, 32, 12,
      0x0100_000c, 0, 8192, 32, 12,
    ] {
      var value = word.bigEndian
      withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
    for (offset, cpu) in [(4096, UInt32(0x0100_0007)), (8192, UInt32(0x0100_000c))] {
      data.append(Data(repeating: 0, count: offset - data.count))
      for word: UInt32 in [0xfeed_facf, cpu, 0, 8, 0, 0, 0, 0] {
        var value = word.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
      }
    }
    try data.write(to: url.appendingPathComponent("Contents/MacOS/fixture"))
    let result = try await PluginCatalog.discover(in: [root])
    let descriptor = try #require(result.plugins.first)
    #expect(descriptor.architectures == [0x0100_0007, 0x0100_000c])
    #expect(descriptor.availability == .compatible)
    #expect(try #require(Bundle(url: url)).isLoaded == false)
  }

  @Test("Missing folders stay absent, aliases deduplicate, and invalid candidates are reported")
  func inventory() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let missing = root.appendingPathComponent("absent")
    let plugins = root.appendingPathComponent("PlugIns")
    try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
    _ = try bundle(in: plugins, name: "Missing executable")
    let plain = plugins.appendingPathComponent("Not a bundle.plugin")
    try Data("plain file".utf8).write(to: plain)
    try Data("ignore".utf8).write(to: plugins.appendingPathComponent("unrelated.md"))
    let alias = root.appendingPathComponent("Alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: plugins)
    let result = try await PluginCatalog.discover(in: [missing, plugins, alias])
    #expect(result.issues.isEmpty)
    #expect(result.plugins.count == 2)
    #expect(result.plugins.allSatisfy { $0.availability == .invalidBundle })
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    #expect(try Data(contentsOf: plain) == Data("plain file".utf8))
  }

  @Test("Unavailable folder errors are surfaced and discovery respects cancellation")
  func errors() async throws {
    let root = try folder()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("file")
    try Data("contents".utf8).write(to: file)
    let remote = try #require(URL(string: "https://example.com"))
    let result = try await PluginCatalog.discover(in: [file, remote])
    #expect(result.plugins.isEmpty)
    #expect(result.issues.count == 2)
    #expect(try Data(contentsOf: file) == Data("contents".utf8))
    let gate = AsyncStream<Void>.makeStream()
    let task = Task {
      for await _ in gate.stream {}
      return try await PluginCatalog.discover(in: [root])
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
