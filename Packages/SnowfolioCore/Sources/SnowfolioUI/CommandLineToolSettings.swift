import AppKit
import DocumentCore
import Observation
import SwiftUI

@MainActor
@Observable
final class CommandLineToolSettings {
  static let receiptKey = "commandLineToolInstallation"
  let helper: URL
  private(set) var receipt: CommandLineInstallationReceipt?
  private(set) var status = CommandLineInstallationStatus.absent
  private(set) var helperAvailable = false
  private(set) var isBusy = false
  private(set) var message: String?
  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults, helper: URL? = nil) {
    self.defaults = defaults
    self.helper =
      helper ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/snowfolio")
    if let saved = defaults.dictionary(forKey: Self.receiptKey),
      let link = saved["link"] as? String, let target = saved["helper"] as? String,
      link.hasPrefix("/"), target.hasPrefix("/"), !link.utf8.contains(0), !target.utf8.contains(0)
    {
      receipt = .init(link: URL(fileURLWithPath: link), helper: URL(fileURLWithPath: target))
    }
  }

  var needsUpdate: Bool { status == .linked && receipt?.helper != helper.standardizedFileURL }
  var command: String {
    CommandLineInstallation.quotedCommand(
      for: status == .linked && !needsUpdate ? receipt?.link ?? helper : helper)
  }

  var summary: String {
    if isBusy { return String(localized: "Checking…") }
    if !helperAvailable { return String(localized: "Unavailable") }
    switch status {
    case .linked:
      return needsUpdate ? String(localized: "Update available") : String(localized: "Installed")
    case .absent: return String(localized: "Not installed")
    case .occupied: return String(localized: "Location has changed")
    }
  }

  func refresh() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    await readState()
  }

  func install(in directory: URL) async {
    await perform {
      try await CommandLineInstallation.install(
        at: directory.appendingPathComponent("snowfolio"), helper: self.helper)
    }
  }

  func update() async {
    guard let receipt else { return }
    await perform { try await CommandLineInstallation.update(receipt, helper: self.helper) }
  }

  func remove() async {
    guard let receipt else { return }
    await perform {
      try await CommandLineInstallation.remove(receipt)
      return nil
    }
  }

  private func perform(
    _ action: @MainActor () async throws -> CommandLineInstallationReceipt?
  ) async {
    guard !isBusy else { return }
    isBusy = true
    message = nil
    defer { isBusy = false }
    do {
      let next = try await action()
      // Persist the filesystem result even if the settings view went away.
      receipt = next
      if let next {
        defaults.set(
          ["link": next.link.path, "helper": next.helper.path], forKey: Self.receiptKey)
      } else {
        defaults.removeObject(forKey: Self.receiptKey)
      }
    } catch is CancellationError {
      // Cancellation before a mutation leaves the recorded installation intact.
    } catch {
      message = error.localizedDescription
    }
    await readState()
  }

  private func readState() async {
    helperAvailable = await CommandLineInstallation.helperIsAvailable(helper)
    do {
      if let receipt {
        status = try await CommandLineInstallation.inspect(receipt)
      } else {
        status = .absent
      }
    } catch {
      status = .occupied
      message = error.localizedDescription
    }
  }
}

struct CommandLineToolSettingsControl: View {
  let model: CommandLineToolSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Command-line tool")
          Text("Open Markdown files and piped text from Terminal.")
            .font(.callout).foregroundStyle(.secondary)
        }
        Spacer(minLength: 12)
        Text(model.summary).foregroundStyle(.secondary)
          .accessibilityIdentifier("commandLineToolStatus")
      }
      if let receipt = model.receipt {
        Text(receipt.link.path).font(.callout).foregroundStyle(.secondary)
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("commandLineToolPath")
      }
      HStack {
        if model.status != .linked {
          Button("Install…", action: chooseDirectory)
            .disabled(!model.helperAvailable)
            .accessibilityIdentifier("installCommandLineTool")
        }
        if model.needsUpdate {
          Button("Update") { Task { await model.update() } }
            .disabled(!model.helperAvailable)
            .accessibilityIdentifier("updateCommandLineTool")
        }
        if model.status == .linked {
          Button("Remove") { Task { await model.remove() } }
            .accessibilityIdentifier("removeCommandLineTool")
        }
        Spacer()
        Button("Copy Command") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(model.command, forType: .string)
        }
        .disabled(!model.helperAvailable)
        .accessibilityIdentifier("copyCommandLineTool")
      }
      .disabled(model.isBusy)
      if let message = model.message {
        Text(message).font(.callout).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("commandLineToolMessage")
      }
    }
    .padding(.vertical, 3)
    .task { await model.refresh() }
  }

  private func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.title = String(localized: "Install Command-Line Tool")
    panel.message = String(
      localized: "Choose a folder in your shell’s PATH for the snowfolio command.")
    panel.prompt = String(localized: "Install")
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL =
      model.receipt?.link.deletingLastPathComponent()
      ?? FileManager.default.homeDirectoryForCurrentUser
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { await model.install(in: url) }
    }
  }
}
