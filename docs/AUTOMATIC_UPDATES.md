# Automatic updates

The modern app integrates Sparkle 2.10.1, pinned exactly in App/Project.swift.
This is a maintained third-party binary dependency; first-party updater code is Swift.
The complete upstream license and external notices ship as Sparkle.txt.

Both app hosts start the same updater service during applicationDidFinishLaunching.
The application menu and General → Software Updates expose manual checking,
automatic-check consent and prerelease selection. The service observes Sparkle's
availability and automatic-check state; Sparkle owns scheduling, download validation,
standard update windows and installation. It is not a custom update installer.

Development builds do not construct or start the Sparkle controller. Their controls
explain that checks are off, while the prerelease preference can still be saved.
This prevents an ordinary release from replacing the development app during testing.

## Release configuration

Generate the project with both values supplied by the release operator:

- TUIST_SNOWFOLIO_UPDATE_FEED_URL: Snowfolio's HTTPS appcast URL.
- TUIST_SNOWFOLIO_UPDATE_PUBLIC_KEY: the base64-encoded 32-byte Ed25519 public key.

No placeholder feed or signing key is installed. Missing or invalid metadata keeps
checks unavailable. Release packaging must require valid configuration; a successful
compile alone is not a deliverable release.

The feed must use HTTPS, have a host, and contain no user credentials or fragment.
The archive signature is verified before extraction. The delegate always returns the
published Snowfolio feed; an inherited SUFeedURL preference cannot switch it to
MacDown's update service. No ATS, package-signature or library-validation exception
is added for Sparkle.

The historical updateIncludesPreReleases choice selects Sparkle's beta channel in
addition to its normal stable channel. SUEnableAutomaticChecks remains Sparkle's
persisted consent choice. Neither migration nor initialization silently turns it on.
Changing prerelease selection requests the normal delayed schedule reset.

## Arm64 release preparation

The official framework includes Intel and arm64 slices. Before distributing an
unused, normally signed app copy, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 Tools/thin-snowfolio-updater.py /path/to/Snowfolio.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 Tools/verify-snowfolio-updates.py /path/to/Snowfolio.app \
  --require-configured --require-arm64-only
```

The preparation tool rejects a running app or an updater with open files, preserves
all selected-slice signatures, and checks the entire app with deep/strict codesign
verification before and after thinning. It never changes entitlements or re-signs.
The official package cache is untouched. The verifier checks all five updater
executables, exact framework version, full license notice and release metadata.
Normal debug build checks allow the vendor's universal framework.

A local native Release compile and an owned preparation check pass: all five
executables become arm64-only and the complete app signature remains valid without
re-signing. This proves preparation mechanics, not Developer ID or Gatekeeper status.

## Acceptance still required

The isolated configuration/lifecycle and existing Settings checks pass locally.
Both native and regular debug apps build for testing; native Release also compiles.
Actual-app update-control persistence, complete new-source suites and signed update
delivery remain separate gates. No feed, updater signing key, signed appcast or
published release has been created. Developer ID/notarization and real update
installation must pass before this subsystem or the original updater can be retired.

References: [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
[channels and publication](https://sparkle-project.org/documentation/publishing/),
[updater lifecycle](https://sparkle-project.org/documentation/api-reference/Classes/SPUUpdater.html).
