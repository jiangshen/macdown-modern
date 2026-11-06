#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcode_app="${DEVELOPER_DIR%/Contents/Developer}"
renderer="$xcode_app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
output="${1:-$repo_root/Build/IconPreviews}"
mkdir -p "$output"
for rendition in Default Dark ClearLight ClearDark TintedLight TintedDark; do
    args=("$repo_root/Modern/Resources/AppIcon.icon" --export-image
          --output-file "$output/$rendition.png" --platform macOS --rendition "$rendition"
          --width 512 --height 512 --scale 1 --design-generation 27)
    if [[ "$rendition" = Tinted* ]]; then
        args+=(--tint-color 0.60 --tint-strength 0.70)
    fi
    "$renderer" "${args[@]}"
done
echo "Rendered all six native appearances: $output"
