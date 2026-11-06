# MacDown

## Swift modernization

The migration roadmap is in [docs/MODERNIZATION_PLAN.md](docs/MODERNIZATION_PLAN.md).
Source ownership and legacy migration boundaries are in
[docs/SOURCE_INVENTORY.md](docs/SOURCE_INVENTORY.md).

The first milestone adds independently tested Swift document/editor foundations;
they are not yet connected to the legacy application UI.

With Xcode 27 and Swift 6.4 on Apple Silicon:

```sh
bash Tools/validate-modernization.sh
```

This builds/tests `Packages/MacDownCore` without CocoaPods and checks every generated
test executable is arm64-only. Logs are saved to `Build/Modernization`. Set
`DEVELOPER_DIR` if your Xcode is installed somewhere other than `/Applications/Xcode.app`.

The legacy application baseline currently fails before compilation because its generated
CocoaPods configuration is absent and its macOS 10.8 deployment target is unsupported
by Xcode 27. See the roadmap for the captured diagnostics and next integration steps.

## Native app development build

With Xcode 27, Swift 6.4 and Tuist (`brew install tuist`):

```sh
bash Tools/build-modern-app.sh
```

The generated workspace is `Modern/MacDownModern.xcworkspace`. The app is written to
`Build/ModernApp/DerivedData/Build/Products/Debug/MacDownModern.app`.
Use `bash Tools/build-modern-app.sh --test` to run the document lifecycle UI suite
when Xcode UI automation is available.

This is the migration's native document/editor build. Markdown preview, export,
legacy preference migration and other parity items remain tracked in the roadmap.
The layered app icon supports Default, Dark, Clear and Tinted system appearances;
[view all six native renderings](docs/design/icon/Appearances.png).
