#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
spec_file="${1:?Provide the official CommonMark 0.31.2 spec.json file}"
artifact_root="${2:-$repo_root/Build/CommonMark}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [ "$(uname -m)" != arm64 ]; then
    echo "CommonMark validation requires native Apple Silicon." >&2
    exit 1
fi
python3 "$repo_root/Tools/verify-markdown-engine.py"
mkdir -p "$artifact_root"
artifact_root="$(cd "$artifact_root" && pwd)"
package_path="$repo_root/Packages/MarkdownEngine"
if ! xcrun swift build --package-path "$package_path" --scratch-path "$artifact_root/build" \
    --arch arm64 --product cmark-audit > "$artifact_root/build.log" 2>&1; then
    tail -40 "$artifact_root/build.log" >&2
    exit 1
fi
bin_path="$(xcrun swift build --package-path "$package_path" \
    --scratch-path "$artifact_root/build" --arch arm64 --show-bin-path)"
program="$bin_path/cmark-audit"
if [ "$(xcrun lipo -archs "$program")" != arm64 ]; then
    echo "The core parser audit executable must be arm64 only." >&2
    exit 1
fi
python3 "$repo_root/Tools/check-commonmark.py" --program "$program" \
    --spec-file "$spec_file" --output "$artifact_root/commonmark.json"
