#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_root="${MACDOWN_APP_BUILD_DIR:-$repo_root/Build/ModernApp}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if ! command -v tuist >/dev/null 2>&1; then
    echo "Install Tuist first: brew install tuist" >&2
    exit 1
fi
if [ "$(uname -m)" != arm64 ]; then
    echo "Build from a native Apple Silicon terminal." >&2
    exit 1
fi
mkdir -p "$artifact_root"
artifact_root="$(cd "$artifact_root" && pwd)"
tuist generate --no-open --path "$repo_root/Modern" > "$artifact_root/generate.log" 2>&1
action=build-for-testing
if [ "${1:-}" = "--test" ]; then action=test; fi
if xcodebuild -workspace "$repo_root/Modern/MacDownModern.xcworkspace" \
    -scheme MacDownModern -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifact_root/DerivedData" -parallel-testing-enabled NO \
    "$action" > "$artifact_root/xcodebuild.log" 2>&1; then
    echo "Native Mac app $action passed."
else
    result=$?
    tail -60 "$artifact_root/xcodebuild.log" >&2
    exit "$result"
fi
app="$artifact_root/DerivedData/Build/Products/Debug/MacDownModern.app"
if [ "$(xcrun lipo -archs "$app/Contents/MacOS/MacDownModern")" != arm64 ]; then
    echo "The app executable must be arm64 only." >&2
    exit 1
fi
if [ ! -s "$app/Contents/Resources/Assets.car" ] || [ ! -s "$app/Contents/Resources/AppIcon.icns" ]; then
    echo "Compiled adaptive icon assets are missing." >&2
    exit 1
fi
echo "App: $app"
