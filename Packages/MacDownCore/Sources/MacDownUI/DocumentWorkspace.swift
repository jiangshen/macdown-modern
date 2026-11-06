import MarkdownCore
import SwiftUI

public struct DocumentWorkspace: View {
  public let document: MarkdownDocument
  public let preferences: AppPreferences
  @State private var processor = MarkdownProcessor()
  @State private var output = DocumentExportController()
  @State private var editing = EditorCommandController()
  @State private var rendered: RenderedMarkdown?
  @State private var renderedRevision: UInt64?
  @State private var mode = WorkspaceMode.split
  @State private var manualRefresh = 0
  @State private var lastRequestedRefresh = 0
  @State private var loading = false
  @State private var error: String?
  @State private var previewError: String?
  @State private var largeFilePaused = false

  public init(document: MarkdownDocument, preferences: AppPreferences) {
    self.document = document
    self.preferences = preferences
  }

  private var request: RenderRequest {
    RenderRequest(
      revision: preferences.manualRendering ? document.loadRevision : document.revision,
      options: preferences.renderingOptions, manualRefresh: manualRefresh,
      manual: preferences.manualRendering)
  }

  public var body: some View {
    NavigationSplitView {
      List {
        Section("Outline") {
          if let rendered, !rendered.headings.isEmpty {
            ForEach(rendered.headings) { heading in
              Button {
                if mode == .preview { mode = .split }
                document.navigate(toUTF16Offset: heading.utf16Offset)
              } label: {
                Text(heading.title.isEmpty ? String(localized: "Untitled heading") : heading.title)
                  .lineLimit(2)
                  .padding(.leading, CGFloat(heading.level - 1) * 10)
              }.buttonStyle(.plain)
                .disabled(renderedRevision != document.revision)
            }
          } else {
            Text("Headings appear here").foregroundStyle(.secondary)
          }
        }
      }
      .listStyle(.sidebar)
      .navigationSplitViewColumnWidth(min: 160, ideal: 210, max: 340)
    } detail: {
      VStack(spacing: 0) {
        NativeDocumentSplit(
          document: document, preferences: preferences, editing: editing,
          html: rendered?.html ?? "", mode: mode, previewError: $previewError)
        if let message = error ?? previewError {
          Text(message).foregroundStyle(.secondary).padding(8).accessibilityIdentifier(
            "previewError")
        } else if largeFilePaused {
          HStack {
            Text("Live preview is paused for this large document.")
            Button("Render Preview") { manualRefresh += 1 }
          }.font(.callout).padding(8)
        } else if preferences.manualRendering {
          Text("Manual preview · Use Render to update").font(.caption).foregroundStyle(.secondary)
            .padding(6)
        }
      }
    }
    .toolbar {
      ToolbarItem {
        Picker("View", selection: $mode) {
          ForEach(WorkspaceMode.allCases) { item in
            Label(item.title, systemImage: item.symbol).tag(item).accessibilityLabel(item.title)
          }
        }.pickerStyle(.segmented).help("Workspace layout")
      }
      ToolbarItem {
        Button {
          manualRefresh += 1
        } label: {
          Label("Render", systemImage: "arrow.clockwise")
        }.keyboardShortcut("r", modifiers: .command)
          .help("Update the Markdown preview")
      }
      ToolbarItem {
        Menu {
          Button("Export HTML…") { output.exportHTML() }
          Button("Export PDF…") { output.exportPDF() }
          Button("Copy HTML") { output.copyHTML() }
          Divider()
          Button("Print…") { output.printDocument() }
        } label: {
          Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(!output.isAvailable)
      }
      ToolbarItem {
        if loading || output.isBusy {
          ProgressView().controlSize(.small).accessibilityLabel("Updating preview")
        }
      }
    }
    .background(DocumentWindowBridge(output: output).frame(width: 0, height: 0))
    .focusedSceneValue(\.documentExport, output)
    .focusedSceneValue(\.markdownEditor, editing)
    .onChange(of: preferences.strikethrough, initial: true) { _, value in
      editing.setStrikethroughEnabled(value)
    }
    .onAppear {
      output.document = document
      output.preferences = preferences
    }
    .alert(
      "Couldn’t Export",
      isPresented: Binding(
        get: { output.errorMessage != nil }, set: { if !$0 { output.errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) { output.errorMessage = nil }
    } message: {
      Text(output.errorMessage ?? "")
    }
    .task(id: request) { await render(request) }
  }

  private func render(_ request: RenderRequest) async {
    loading = false
    let explicitlyRequested = request.manualRefresh != lastRequestedRefresh
    lastRequestedRefresh = request.manualRefresh
    do {
      if !explicitlyRequested {
        try await Task.sleep(for: .milliseconds(180))
      }
      try Task.checkCancellation()
      let source = document.text
      if source.utf8.count > 1_048_576 && !explicitlyRequested {
        largeFilePaused = true
        return
      }
      largeFilePaused = false
      loading = true
      let revision = document.revision
      let result = try await processor.render(source, options: request.options)
      try Task.checkCancellation()
      guard revision == document.revision else {
        loading = false
        return
      }
      rendered = result
      renderedRevision = revision
      error = nil
      loading = false
    } catch is CancellationError {
      // The replacement request owns loading state; stale work never publishes.
    } catch {
      guard !Task.isCancelled else { return }
      loading = false
      self.error = String(
        localized: "The Markdown preview could not be rendered. Try Render again.")
    }
  }
}

private struct RenderRequest: Hashable {
  let revision: UInt64
  let options: MarkdownRenderingOptions
  let manualRefresh: Int
  let manual: Bool
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
  case editor, split, preview
  var id: Self { self }
  var title: LocalizedStringKey {
    switch self {
    case .editor: "Editor"
    case .split: "Split"
    case .preview: "Preview"
    }
  }
  var symbol: String {
    switch self {
    case .editor: "square.leadingthird.inset.filled"
    case .split: "rectangle.split.2x1"
    case .preview: "doc.richtext"
    }
  }
}
