#if FULL_WORKSPACE_DOCUMENT_HOST_PROBE
  import AppKit
  import WebKit

  @testable import SnowfolioUI

  /// Diagnostic only. Compare bare WebKit and the real preview pipeline without
  /// SwiftUI embedding, then retain both native snapshots and view geometry.
  @MainActor
  final class NativeWebKitPaintControl: NSWindowController {
    private let plain: WKWebView
    private let pipeline: MarkdownPreviewWebView
    private let coordinator: NativeMarkdownPreview.Coordinator
    private let output: URL
    private let status = NSTextField(labelWithString: "Ready to capture")
    private let captureButton = NSButton(title: "Capture snapshots", target: nil, action: nil)
    private var captureTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var previewError: String?
    private var direct: WKWebView?
    private var directCaptureTask: Task<Void, Never>?

    init(output: URL) {
      self.output = output
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.defaultWebpagePreferences.allowsContentJavaScript = false
      plain = WKWebView(frame: .zero, configuration: configuration)
      let coordinator = NativeMarkdownPreview(html: "", directory: nil).makeCoordinator()
      self.coordinator = coordinator
      pipeline = MarkdownPreviewWebView(
        frame: .zero,
        configuration: NativeMarkdownPreview.configuration(
          handler: coordinator.resources, scrollHandler: coordinator))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 920, height: 540),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered, defer: false)
      window.title = "Native WebKit painting controls"
      window.identifier = NSUserInterfaceItemIdentifier("nativeWebKitPaintControl")
      window.isRestorable = false
      super.init(window: window)
      plain.setAccessibilityIdentifier("plainPaintWebView")
      pipeline.setAccessibilityIdentifier("pipelinePaintWebView")
      pipeline.navigationDelegate = coordinator
      coordinator.onError = { [weak self] error in
        self?.previewError = error
        if let error { self?.status.stringValue = error }
      }
      let columns = NSStackView()
      columns.orientation = .horizontal
      columns.distribution = .fillEqually
      columns.spacing = 16
      for (title, view) in [("Plain WebKit", plain), ("Snowfolio pipeline", pipeline)] {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        let column = NSStackView(views: [label, view])
        column.orientation = .vertical
        column.distribution = .fill
        column.alignment = .leading
        column.spacing = 8
        view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true
        columns.addArrangedSubview(column)
        column.heightAnchor.constraint(equalTo: columns.heightAnchor).isActive = true
      }
      captureButton.target = self
      captureButton.action = #selector(capture)
      captureButton.setAccessibilityIdentifier("capturePaintSnapshots")
      status.setAccessibilityIdentifier("paintCaptureStatus")
      let directButton = NSButton(
        title: "Use direct WebKit window", target: self, action: #selector(showDirect))
      directButton.setAccessibilityIdentifier("showDirectPaintControl")
      let controls = NSStackView(views: [captureButton, directButton, status])
      controls.orientation = .horizontal
      controls.spacing = 12
      let root = NSStackView(views: [columns, controls])
      root.orientation = .vertical
      root.distribution = .fill
      root.alignment = .leading
      root.spacing = 12
      root.translatesAutoresizingMaskIntoConstraints = false
      let content = NSView()
      window.contentView = content
      content.addSubview(root)
      NSLayoutConstraint.activate([
        root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
        root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
        root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
        root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        columns.widthAnchor.constraint(equalTo: root.widthAnchor),
      ])
      window.contentMinSize = NSSize(width: 800, height: 420)
      window.center()
      plain.loadHTMLString(
        """
        <!doctype html><html><meta charset="utf-8"><body style="margin:24px;color:#111;background:#fff;font:20px system-ui">
        <h1>Plain WebKit checkpoint</h1><p>Native AppKit container.</p>
        <div style="height:96px;background:#2864dc;color:white;padding:12px">Plain painting marker</div>
        </body></html>
        """, baseURL: nil)
      loadTask = Task { @MainActor [weak self] in
        let preferences = NativeDocumentPreferences.shared
        await preferences.readingStyles.loadIfNeeded()
        guard let self, !Task.isCancelled else { return }
        self.coordinator.update(
          self.pipeline,
          html: """
            <h1 data-sourcepos="1:1-1:28">Snowfolio pipeline checkpoint</h1>
            <p data-sourcepos="3:1-3:24">Native AppKit container.</p>
            <div style="height:96px;background:#2864dc;color:white;padding:12px">Pipeline painting marker</div>
            """,
          directory: nil, remoteImages: false, style: preferences.documentStyle, revision: 1)
      }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(output:)") }

    private func geometry(_ view: WKWebView) -> [String: Any] {
      var result: [String: Any] = [
        "frame": NSStringFromRect(view.frame), "bounds": NSStringFromRect(view.bounds),
        "visibleRect": NSStringFromRect(view.visibleRect),
        "hidden": view.isHiddenOrHasHiddenAncestor, "wantsLayer": view.wantsLayer,
        "windowVisible": view.window?.isVisible == true,
        "loading": view.isLoading, "progress": view.estimatedProgress,
      ]
      if view === pipeline, let previewError { result["previewError"] = previewError }
      if let window = view.window {
        result["screenFrame"] = NSStringFromRect(
          window.convertToScreen(view.convert(view.bounds, to: nil)))
        result["windowFrame"] = NSStringFromRect(window.frame)
        result["occlusionState"] = window.occlusionState.rawValue
      }
      if let layer = view.layer {
        result["layerFrame"] = NSStringFromRect(layer.frame)
        result["layerHidden"] = layer.isHidden
      }
      return result
    }

    @objc private func capture(_ sender: Any?) {
      guard captureTask == nil else { return }
      captureButton.isEnabled = false
      captureTask = Task { @MainActor [weak self] in
        guard let self else { return }
        let views: [(String, WKWebView)] = [("plain", self.plain), ("pipeline", self.pipeline)]
        let initial = views.map { name, view in
          var record = self.geometry(view)
          record["name"] = name
          return record
        }
        do {
          let geometry = try JSONSerialization.data(
            withJSONObject: initial, options: [.prettyPrinted, .sortedKeys])
          try geometry.write(
            to: self.output.appendingPathComponent("paint-geometry.json"), options: .atomic)
        } catch { self.status.stringValue = error.localizedDescription }
        var results: [[String: Any]] = []
        for (name, view) in views {
          results.append(await self.snapshot(view, name: name))
        }
        do {
          let report = try JSONSerialization.data(
            withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
          try report.write(
            to: self.output.appendingPathComponent("paint-diagnostics.json"), options: .atomic)
          self.status.stringValue = "Captured"
        } catch { self.status.stringValue = error.localizedDescription }
      }
    }

    private func snapshot(_ view: WKWebView, name: String) async -> [String: Any] {
      var result = geometry(view)
      result["name"] = name
      do {
        let image = try await view.takeSnapshot(configuration: nil)
        guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        result["snapshotSaved"] = true
      } catch {
        result["snapshotSaved"] = false
        result["error"] = error.localizedDescription
      }
      return result
    }

    @objc private func showDirect(_ sender: Any?) {
      guard direct == nil, let window else { return }
      loadTask?.cancel()
      pipeline.stopLoading()
      coordinator.resources.cancelAll()
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.defaultWebpagePreferences.allowsContentJavaScript = false
      let view = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
      view.setAccessibilityIdentifier("directPaintWebView")
      direct = view
      // No SwiftUI, stack or intermediate native container. Load after attaching
      // to the existing visible window, matching the simplest AppKit setup.
      window.contentView = view
      window.title = "Direct WebKit window control"
      let capture = NSMenuItem(
        title: "Capture Direct WebKit Snapshot", action: #selector(captureDirect), keyEquivalent: ""
      )
      capture.target = self
      NSApp.mainMenu?.items.first?.submenu?.addItem(capture)
      view.loadHTMLString(
        """
        <!doctype html><html><meta charset="utf-8"><body style="margin:24px;color:#111;background:#fff;font:20px system-ui">
        <h1>Direct window WebKit checkpoint</h1><p>WKWebView is the window content view.</p>
        <div style="height:96px;background:#2864dc;color:white;padding:12px">Direct painting marker</div>
        </body></html>
        """, baseURL: nil)
    }

    @objc private func captureDirect(_ sender: Any?) {
      guard let direct, directCaptureTask == nil else { return }
      directCaptureTask = Task { @MainActor [weak self] in
        guard let self else { return }
        let result = await self.snapshot(direct, name: "direct")
        do {
          let report = try JSONSerialization.data(
            withJSONObject: [result], options: [.prettyPrinted, .sortedKeys])
          try report.write(
            to: self.output.appendingPathComponent("paint-direct-diagnostics.json"),
            options: .atomic)
        } catch {
          NSLog(
            "Direct WebKit control could not write capture metadata: %@", error.localizedDescription
          )
        }
      }
    }

    override func close() {
      loadTask?.cancel()
      captureTask?.cancel()
      directCaptureTask?.cancel()
      direct?.stopLoading()
      plain.stopLoading()
      pipeline.stopLoading()
      coordinator.resources.cancelAll()
      super.close()
    }
  }
#endif
