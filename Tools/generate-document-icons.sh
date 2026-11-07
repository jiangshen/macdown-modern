#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
icon_work="$(mktemp -d "${TMPDIR:-/tmp}/snowfolio-document-icons.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
xcrun swift "$repo_root/Tools/generate-document-icons.swift" "$icon_work"
mkdir -p "$repo_root/App/Resources/DocumentIcons.xcassets" "$repo_root/docs/design/document-icon"
ditto "$icon_work/DocumentIcons.xcassets" "$repo_root/App/Resources/DocumentIcons.xcassets"
iconutil -c icns "$icon_work/MarkdownDocument.iconset" -o "$repo_root/App/Resources/MarkdownDocument.icns"
cp "$icon_work/MarkdownDocument.iconset/icon_512x512.png" "$repo_root/docs/design/document-icon/MarkdownDocument.png"
echo "Updated native document assets and ICNS fallback."
