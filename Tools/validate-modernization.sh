#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_path="$repo_root/Packages/SnowfolioCore"
artifact_root="${1:-$repo_root/Build/Modernization}"
mkdir -p "$artifact_root"
artifact_root="$(cd "$artifact_root" && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [ "$(uname -m)" != arm64 ]; then
    echo "Validation requires a native Apple Silicon terminal." >&2
    exit 1
fi

xcrun swift --version > "$artifact_root/toolchain.txt"
if xcrun swift test --package-path "$package_path" --scratch-path "$artifact_root/build" \
    --arch arm64 > "$artifact_root/swift-test.log" 2>&1; then
    echo "Swift foundation build and tests passed."
else
    result=$?
    tail -60 "$artifact_root/swift-test.log" >&2
    exit "$result"
fi

bin_path="$(xcrun swift build --package-path "$package_path" \
    --scratch-path "$artifact_root/build" --arch arm64 --show-bin-path)"
verified_count=0
: > "$artifact_root/architecture.txt"
for bundle in "$bin_path/"*.xctest; do
    [ -d "$bundle" ] || continue
    bundle_name="$(basename "$bundle" .xctest)"
    test_binary="$bundle/Contents/MacOS/$bundle_name"
    architecture="$(xcrun lipo -archs "$test_binary")"
    if [ "$architecture" != arm64 ]; then
        echo "Expected arm64 only; found: $architecture in $bundle_name" >&2
        exit 1
    fi
    file "$test_binary" >> "$artifact_root/architecture.txt"
    verified_count=$((verified_count + 1))
done
if [ "$verified_count" -eq 0 ]; then
    echo "No test executables found in $bin_path" >&2
    exit 1
fi
echo "Verified $verified_count native arm64 test executables. Logs: $artifact_root"
