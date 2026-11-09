import AppKit
import Darwin
import DocumentCore

@main
@MainActor
struct SnowfolioCommandLine {
  static func main() async {
    do {
      let directory = URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
      let invocation = try CommandLineInvocation(
        arguments: Array(CommandLine.arguments.dropFirst()), directory: directory)
      switch invocation {
      case .help:
        print(
          """
          Usage: snowfolio [options] [file ...]
                 producer | snowfolio [file ...]

          Open Markdown files in Snowfolio. Piped UTF-8 text opens as a new unsaved document.
          Missing files are created empty. Options precede filenames; use -- for leading-dash names.

            -h, --help       Print help and exit.
            -v, --version    Print the app version and exit.
          """)
      case .version:
        let app = try applicationURL()
        let version =
          Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
          ?? "development"
        print("Snowfolio \(version)")
      case .open(let files):
        let app = try applicationURL()
        // This separate command-line process can block on EOF. Unlike the old
        // zero-timeout readiness check, a delayed producer cannot be missed.
        let input =
          isatty(STDIN_FILENO) == 1 ? nil : try FileHandle.standardInput.readToEnd() ?? Data()
        let request = try CommandLineLaunchRequest(files: files, pipedData: input)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.appleEvent = try CommandLineLaunchEvent.encode(request, applicationURL: app)
        #if DEBUG
          trace(
            "before launch ownPID=\(ProcessInfo.processInfo.processIdentifier) mainBundle=\(Bundle.main.bundleIdentifier ?? "none")"
          )
        #endif
        let launched = try await NSWorkspace.shared.openApplication(
          at: app, configuration: configuration)
        #if DEBUG
          trace(
            "launch returned pid=\(launched.processIdentifier) bundle=\(launched.bundleIdentifier ?? "none") self=\(launched.processIdentifier == ProcessInfo.processInfo.processIdentifier)"
          )
        #endif
      }
    } catch {
      FileHandle.standardError.write(Data("snowfolio: \(error.localizedDescription)\n".utf8))
      exit(error is CommandLineInvocationError ? EX_USAGE : EXIT_FAILURE)
    }
  }

  #if DEBUG
    private static func trace(_ message: @autoclosure () -> String) {
      if ProcessInfo.processInfo.environment["SNOWFOLIO_TRACE_CLI"] == "1" {
        FileHandle.standardError.write(Data("SnowfolioCLI \(message())\n".utf8))
      }
    }
  #endif

  private static func applicationURL() throws -> URL {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
      throw CocoaError(.executableNotLoadable)
    }
    let executable = buffer.withUnsafeBufferPointer { bytes -> String in
      guard let base = bytes.baseAddress else { return "" }
      return FileManager.default.string(withFileSystemRepresentation: base, length: strlen(base))
    }
    let url = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
    let app = url.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    guard app.pathExtension == "app", Bundle(url: app)?.bundleIdentifier == "local.macdown.modern"
    else {
      throw NSError(
        domain: "SnowfolioCLI", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "Run the command-line tool bundled inside Snowfolio.app."
        ])
    }
    return app
  }
}
