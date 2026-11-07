#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_root="${SNOWFOLIO_APP_BUILD_DIR:-$repo_root/Build/Snowfolio}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
python3 "$repo_root/Tools/verify-markdown-engine.py"
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
tuist generate --no-open --path "$repo_root/App" > "$artifact_root/generate.log" 2>&1
action=build-for-testing
if [ "${1:-}" = "--test" ]; then action=test; fi
if xcodebuild -workspace "$repo_root/App/Snowfolio.xcworkspace" \
    -scheme Snowfolio -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifact_root/DerivedData" -parallel-testing-enabled NO \
    "$action" > "$artifact_root/xcodebuild.log" 2>&1; then
    echo "Native Mac app $action passed."
else
    result=$?
    tail -60 "$artifact_root/xcodebuild.log" >&2
    exit "$result"
fi
app="$artifact_root/DerivedData/Build/Products/Debug/Snowfolio.app"
if [ "$(xcrun lipo -archs "$app/Contents/MacOS/Snowfolio")" != arm64 ]; then
    echo "The app executable must be arm64 only." >&2
    exit 1
fi
if [ ! -s "$app/Contents/Resources/Assets.car" ] || [ ! -s "$app/Contents/Resources/AppIcon.icns" ]; then
    echo "Compiled adaptive icon assets are missing." >&2
    exit 1
fi
if [ ! -s "$app/Contents/Resources/MarkdownDocument.icns" ]; then
    echo "Compiled Markdown document icon is missing." >&2
    exit 1
fi
for license in Yams.txt libyaml.txt; do
    if [ ! -s "$app/Contents/Resources/$license" ]; then
        echo "Bundled YAML license is missing: $license" >&2
        exit 1
    fi
done
highlight_resources="$app/Contents/Resources/SnowfolioCore_CodeHighlightCore.bundle/Contents/Resources"
for resource in Prism.js Languages.json Prism-LICENSE.txt Prism-Provenance.json prism.css prism-coy.css prism-dark.css prism-funky.css prism-okaidia.css prism-solarizedlight.css prism-tomorrow.css prism-twilight.css; do
    if [ ! -s "$highlight_resources/$resource" ]; then
        echo "Bundled code-highlighting resource is missing: $resource" >&2
        exit 1
    fi
done
python3 - "$highlight_resources" <<'VERIFY_PRISM'
import hashlib
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
provenance = json.loads((root / 'Prism-Provenance.json').read_text())
for name, expected in provenance['files'].items():
    actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
    if actual != expected:
        raise SystemExit('Bundled Prism checksum mismatch: ' + name)
VERIFY_PRISM
math_resources="$app/Contents/Resources/SnowfolioCore_MathCore.bundle/Contents/Resources"
python3 - "$math_resources" <<'VERIFY_MATH'
import hashlib
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
provenance = json.loads((root / 'KaTeX-Provenance.json').read_text())
for name, expected in provenance['files'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Bundled math checksum mismatch: ' + name)
if (root / 'KaTeX.css').read_text().count('data:font/woff2;base64,') != 20:
    raise SystemExit('Bundled math fonts are missing')
VERIFY_MATH
diagram_resources="$app/Contents/Resources/SnowfolioCore_DiagramCore.bundle/Contents/Resources"
python3 - "$diagram_resources" "$app/Contents/Resources" <<'VERIFY_DIAGRAMS'
import hashlib
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
notices = Path(sys.argv[2])
provenance = json.loads((root / 'Diagram-Provenance.json').read_text())
for name, expected in provenance['files'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Bundled diagram checksum mismatch: ' + name)
for name in ('Mermaid', 'Viz', 'Graphviz', 'Graphviz-rbtree', 'Expat', 'Emscripten'):
    if (notices / (name + '-diagram.txt')).read_bytes() != (root / (name + '-LICENSE.txt')).read_bytes():
        raise SystemExit('Bundled diagram distribution notice mismatch: ' + name)
if (notices / 'Diagram-Sources.txt').read_bytes() != (root / 'Diagram-Sources.txt').read_bytes():
    raise SystemExit('Bundled diagram source availability notice is missing')
VERIFY_DIAGRAMS
echo "App: $app"
