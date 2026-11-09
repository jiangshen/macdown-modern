# Native plug-in compatibility

Status: implementation and verification in progress. Original loader retained.

Snowfolio inventories the Snowfolio and MacDown Application Support PlugIns folders
without loading code, querying principal classes or creating folders. Its native menu
reports Intel-only, unsupported and malformed bundles. Open Plug-ins Folder explicitly
creates the modern directory. Refresh updates the cached inventory; it does not execute
callbacks or mutate the menu while it is tracking.

Run requires a first-use confirmation for each plug-in in the current app session.
Only then does PluginSession load and retain the original optional name,
plugInDidInitialize and BOOL run: contract on the main actor. Aliases share one instance.
A loaded instance is retained until quit; replacement code requires restart. Callbacks
can access NSDocumentController.shared.currentDocument and the historical markdown,
html and fileURL interface. This is executable native code with the app's access to
files and documents, not an isolated document-transform service. Architecture inventory
alone does not prove callback, signing, trust or arbitrary plug-in compatibility.

The app test fixture is first-party Swift, bundled only with the UI test runner and
copied to an owned temporary plug-in folder. It never publishes anything or uses the
user's real plug-ins. Its test covers metadata-only listing, cancellation, repeated
runs, initialization count, current document/source/fileURL, native Undo/Redo, exact
UTF16LE/BOM/CRLF/Unicode Save and a false-return error. Runtime acceptance is pending.

## Release signing proposal — approval pending

Apple's Hardened Runtime library validation normally permits Apple-signed code and
code signed by the same Team ID as the host. Preserving practical same-process plug-ins
from other developers requires the supported exception documented by
[Apple](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

The proposed exact change is to App/Project.swift, only the Snowfolio app target when
nativeDocumentHost is selected:

```swift
entitlements: nativeDocumentHost
  ? .dictionary(["com.apple.security.cs.disable-library-validation": .boolean(true)]) : nil,
```

This would affect the whole native Snowfolio process, including future release builds:
it permits loading native code signed by another developer or unsigned code, and
removes this validation for other libraries loaded in that process too. Explicit Run
confirmation limits ordinary plug-in execution but does not restore that process-wide
validation. Other Hardened Runtime protections remain enabled. The CLI, test runner,
comparison host and global macOS security settings retain their current protections.
Apple notes that Gatekeeper applies additional checks to apps with this exception.
Developer ID signing, Gatekeeper and notarization still require real release validation.

This entitlement has NOT been added to the app. Automatic approval review rejected
applying it because the user has not explicitly approved this entitlement, target and
release scope. The source change must wait for that approval; do not bypass it by
changing a signing command or moving the exception elsewhere.

A disposable owned executable compiled from current production PluginCore sources
proves the functional requirement: with runtime enabled and no exception its fixture
load fails with NSCocoaErrorDomain3588; with only this exception, runtime remains
present and discovery stays nonexecuting while invocation returns true,true,false and
retains the shared document. This is an ad-hoc standalone proof, not actual-app,
Developer ID, Gatekeeper or notarization acceptance. Compact evidence is retained at
/private/tmp/snowfolio-validation-history/plugin-menu-runtime/hardened-runtime.json.
