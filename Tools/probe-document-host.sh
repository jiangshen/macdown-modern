#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_root="$repo_root/Build/DocumentHostProbe"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$artifact_root"
tuist generate --no-open --path "$repo_root/Tools/DocumentHostProbe" > "$artifact_root/generate.log" 2>&1
action="${1:-test}"
case "$action" in test|build-for-testing) ;; *) exit 2 ;; esac
if xcodebuild "$action" -workspace "$repo_root/Tools/DocumentHostProbe/DocumentHostProbe.xcworkspace" \
  -scheme DocumentHostProbe -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$artifact_root/DerivedData" -parallel-testing-enabled NO \
  > "$artifact_root/xcodebuild.log" 2>&1; then
  echo "Standalone document host $action passed."
else
  result=$?
  tail -60 "$artifact_root/xcodebuild.log" >&2
  exit "$result"
fi
