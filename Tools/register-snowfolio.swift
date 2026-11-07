import AppKit
import CoreServices
import Foundation
import UniformTypeIdentifiers

// Registration only. Choosing this app as the default is a separate release step.
let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
  fatalError("Usage: register-snowfolio.swift /path/to/Snowfolio.app [evidence.json]")
}
let app = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
  .resolvingSymlinksInPath()
guard let bundle = Bundle(url: app), let identifier = bundle.bundleIdentifier,
  bundle.object(forInfoDictionaryKey: "CFBundleName") as? String == "Snowfolio",
  FileManager.default.fileExists(
    atPath: app.appendingPathComponent("Contents/Resources/MarkdownDocument.icns").path)
else { fatalError("Build the Snowfolio app and document icon first.") }
let workspace = NSWorkspace.shared
let markdown = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
func defaultIdentifier(_ type: UTType) -> String {
  guard let url = workspace.urlForApplication(toOpen: type) else { return "none" }
  return Bundle(url: url)?.bundleIdentifier ?? url.path
}
let before = ["markdown": defaultIdentifier(markdown), "plainText": defaultIdentifier(.plainText)]
let status = LSRegisterURL(app as CFURL, true)
guard status == noErr else { fatalError("Launch Services registration failed: \(status)") }
let applications = workspace.urlsForApplications(withBundleIdentifier: identifier)
  .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
guard applications.contains(app) else {
  fatalError("The built app is missing from registered applications.")
}
let handlers = workspace.urlsForApplications(toOpen: markdown)
  .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
guard handlers.contains(app) else { fatalError("The built app is missing from Markdown handlers.") }
let after = ["markdown": defaultIdentifier(markdown), "plainText": defaultIdentifier(.plainText)]
let extensions = ["md", "markdown"]
let types = Dictionary(
  uniqueKeysWithValues: extensions.map {
    ($0, UTType(filenameExtension: $0)?.identifier ?? "unknown")
  })
let evidence: [String: Any] = [
  "application": app.path, "bundleIdentifier": identifier,
  "registered": true, "markdownHandlerVerified": true, "defaultsBefore": before,
  "defaultsAfter": after, "defaultsUnchanged": before == after, "extensionTypes": types,
  "defaultSetterCalled": false,
]
let data = try JSONSerialization.data(
  withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
if arguments.count > 2 { try data.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic) }
print(String(decoding: data, as: UTF8.self))
