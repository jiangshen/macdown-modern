import MarkdownCore
import SwiftUI

public struct DocumentWorkspace: View {
  public let document: MarkdownDocument
  public let preferences: AppPreferences
  @Environment(\.openDocument) private var openDocument
  @Environment(\.scenePhase) private var scenePhase
  @State private var scrolling = DocumentScrollCoordinator()
  @State private var zoom: DocumentZoomController
  @State private var droppedDocuments = DroppedDocumentOpener()
  @State private var processor = MarkdownProcessor()
  @State private var output = DocumentExportController()
  @State private var editing = EditorCommandController()
  @State private var callouts = CalloutEditorController()
  @State private var previewHTML = ""
  @State private var sourceSyntax: MarkdownSyntax?
  @State private var headings: [MarkdownHeading] = []
  @State private var parsedRevision: UInt64?
  @State private var previewLoadRevision: UInt64?
  @State private var previewOptions: MarkdownRenderingOptions?
  @State private var renderedRevision: UInt64?
  @SceneStorage("sourceViewport") private var sourceViewport: Data?
  @SceneStorage("previewViewport") private var previewViewport: Data?
  @SceneStorage("editorSelection") private var editorSelection: Data?
  @SceneStorage("workspaceZoomPercent") private var zoomPercent = 100
  @SceneStorage("workspaceMode") private var mode = WorkspaceMode.split
  @State private var manualRefresh = 0
  @State private var lastRequestedRefresh = 0
  @State private var loading = false
  @State private var error: String?
  @State private var renderNotices: [MarkdownRenderNotice] = []
  @State private var previewError: String?
  @State private var largeFilePaused = false

  public init(
    document: MarkdownDocument, preferences: AppPreferences, zoom: DocumentZoomController? = nil
  ) {
    self.document = document
    self.preferences = preferences
    _zoom = State(initialValue: zoom ?? DocumentZoomController())
  }

  private var request: RenderRequest {
    RenderRequest(
      revision: preferences.manualRendering && !preferences.syntaxHighlighting
        ? document.loadRevision : document.revision,
      loadRevision: document.loadRevision, syntaxHighlighting: preferences.syntaxHighlighting,
      options: preferences.renderingOptions, manualRefresh: manualRefresh,
      manual: preferences.manualRendering)
  }

  public var body: some View {
    NavigationSplitView {
      VStack(spacing: 8) {
        List {
          Section("Outline") {
            if !headings.isEmpty {
              ForEach(headings) { heading in
                Button {
                  if mode == .preview { mode = .split }
                  document.navigate(toUTF16Offset: heading.utf16Offset)
                } label: {
                  Text(
                    heading.title.isEmpty ? String(localized: "Untitled heading") : heading.title
                  )
                  .lineLimit(2)
                  .padding(.leading, CGFloat(heading.level - 1) * 10)
                }.buttonStyle(.plain)
                  .disabled(parsedRevision != document.revision)
              }
            } else {
              Text("Headings appear here").foregroundStyle(.secondary)
            }
          }
        }
        .listStyle(.sidebar)
        DocumentDropButton(openFiles: openDroppedFiles)
          .frame(height: 28).padding([.horizontal, .bottom], 12)
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 210, max: 340)
    } detail: {
      VStack(spacing: 0) {
        NativeDocumentSplit(
          document: document, preferences: preferences, editing: editing,
          html: previewHTML, syntax: sourceSyntax, syntaxRevision: parsedRevision,
          revision: renderedRevision, callouts: callouts, mode: mode,
          previewError: $previewError, openDroppedFiles: openDroppedFiles,
          editorSelection: $editorSelection, scrolling: scrolling, zoomScale: zoom.scale,
          sourceViewportStorage: $sourceViewport, previewViewportStorage: $previewViewport)
        if let message = error ?? previewError {
          Text(message).foregroundStyle(.secondary).padding(8).accessibilityIdentifier(
            "previewError")
        } else if !renderNotices.isEmpty, parsedRevision == document.revision {
          Text(renderNoticeText)
            .font(.caption).foregroundStyle(.secondary).padding(8)
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
            Label(item.title, systemImage: item.symbol(editorOnRight: preferences.editorOnRight))
              .tag(item).accessibilityLabel(item.title)
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
        if loading || output.isBusy || droppedDocuments.isOpening {
          ProgressView().controlSize(.small).accessibilityLabel("Updating preview")
        }
      }
    }
    .background(
      DocumentWindowBridge(output: output, preferTabs: preferences.preferDocumentTabs).frame(
        width: 0, height: 0)
    )
    .focusedSceneValue(\.documentExport, output)
    .focusedSceneValue(\.markdownEditor, editing)
    .focusedSceneValue(\.documentZoom, zoom)
    .onChange(of: document.fileURL, initial: true) { _, url in
      zoom.configure(fileURL: url, scenePercent: zoomPercent)
    }
    .onChange(of: zoomPercent) { _, value in
      zoom.configure(fileURL: document.fileURL, scenePercent: value)
    }
    .onChange(of: zoom.percent) { _, value in
      zoomPercent = value
      zoom.persist(fileURL: document.fileURL)
    }
    .onChange(of: preferences.highlight, initial: true) { _, value in
      editing.setHighlightEnabled(value)
    }
    .onChange(of: preferences.strikethrough, initial: true) { _, value in
      editing.setStrikethroughEnabled(value)
    }
    // Scene restoration may deliver these values after native views are created.
    .onChange(of: sourceViewport) { _, _ in scrolling.layoutChanged() }
    .onChange(of: previewViewport) { _, _ in scrolling.layoutChanged() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active { scrolling.flush() }
    }
    .onAppear {
      callouts.document = document
      callouts.editing = editing
      callouts.preferences = preferences
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
    .alert(
      "Couldn’t Open Files",
      isPresented: Binding(
        get: { !droppedDocuments.failures.isEmpty },
        set: { if !$0 { droppedDocuments.failures.removeAll() } }
      )
    ) {
      Button("OK", role: .cancel) { droppedDocuments.failures.removeAll() }
    } message: {
      Text(droppedDocuments.failures.joined(separator: "\n"))
    }
    .task(id: request) { await render(request) }
  }

  private var renderNoticeText: String {
    renderNotices.map { notice in
      switch notice {
      case .complexFrontMatter:
        String(
          localized:
            "This metadata block is too complex to display as properties. It is shown as Markdown.")
      case .invalidFrontMatter:
        String(localized: "Front matter is not valid YAML. It is shown as Markdown.")
      case .unsupportedMath:
        String(localized: "Some equations could not be rendered. Their TeX source is shown.")
      case .complexInlineFormatting:
        String(
          localized:
            "Some inline formatting is too complex to display. Remaining markers are shown as text."
        )
      case .unsupportedDiagram:
        String(localized: "Some diagrams could not render completely. Check their source.")
      }
    }.joined(separator: " ")
  }

  private func openDroppedFiles(_ urls: [URL]) -> Bool {
    guard MarkdownFileDrop.accepts(urls) else { return false }
    let anchor = DocumentWindowAnchor(output.window)
    Task { @MainActor in
      await droppedDocuments.open(urls, from: anchor) { url in
        try await openDocument(at: url)
      }
    }
    return true
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
      let result = try await processor.render(
        source, options: request.options, interactiveCallouts: true,
        includeSyntax: request.syntaxHighlighting, diagramPresentation: .isolated)
      try Task.checkCancellation()
      guard revision == document.revision else {
        loading = false
        return
      }
      renderNotices = result.notices
      sourceSyntax = result.syntax
      headings = result.headings
      parsedRevision = revision
      if !request.manual || explicitlyRequested || renderedRevision == nil
        || previewLoadRevision != request.loadRevision || previewOptions != request.options
      {
        callouts.setTargets(result.nodes, revision: revision)
        previewHTML = result.html
        renderedRevision = revision
        previewLoadRevision = request.loadRevision
        previewOptions = request.options
      }
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
  let loadRevision: UInt64
  let syntaxHighlighting: Bool
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
  func symbol(editorOnRight: Bool) -> String {
    if self == .editor, editorOnRight { return "square.trailingthird.inset.filled" }
    return symbol
  }

  var symbol: String {
    switch self {
    case .editor: "square.leadingthird.inset.filled"
    case .split: "rectangle.split.2x1"
    case .preview: "doc.richtext"
    }
  }
}
