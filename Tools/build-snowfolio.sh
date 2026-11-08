#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
artifact_root="${SNOWFOLIO_APP_BUILD_DIR:-$repo_root/Build/Snowfolio}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
action=build-for-testing
if [ "${1:-}" = "--test" ]; then action=test; shift; fi
build_arguments=("$action")
while [ "$#" -gt 0 ]; do
    case "$1" in
        --only-testing)
            if [ "$action" != test ] || [ "$#" -lt 2 ]; then
                echo "--only-testing requires --test and a SnowfolioUITests identifier." >&2
                exit 2
            fi
            case "$2" in
                SnowfolioUITests/*) build_arguments+=("-only-testing:$2") ;;
                *) echo "The test identifier must start with SnowfolioUITests/." >&2; exit 2 ;;
            esac
            shift 2
            ;;
        *) echo "Usage: build-snowfolio.sh [--test [--only-testing identifier]...]" >&2; exit 2 ;;
    esac
done
python3 "$repo_root/Tools/verify-markdown-engine.py"
python3 "$repo_root/Tools/verify-editor-themes.py"
python3 "$repo_root/Tools/verify-reading-styles.py"
python3 "$repo_root/Tools/verify-css-parser.py"
python3 "$repo_root/Tools/verify-html-template.py"
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
if xcodebuild -workspace "$repo_root/App/Snowfolio.xcworkspace" \
    -scheme Snowfolio -configuration Debug -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$artifact_root/DerivedData" -parallel-testing-enabled NO \
    "${build_arguments[@]}" > "$artifact_root/xcodebuild.log" 2>&1; then
    echo "Native Mac app $action passed."
else
    result=$?
    sed -n '/error:/p; /Test Case.*failed/p' "$artifact_root/xcodebuild.log" >&2
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
for license in Yams.txt libyaml.txt CommonMark-cmark.txt Hoedown-inline.txt macdown.txt; do
    if [ ! -s "$app/Contents/Resources/$license" ]; then
        echo "Bundled dependency license is missing: $license" >&2
        exit 1
    fi
done
for license in swift-cmark.txt CommonMark-cmark.txt Hoedown-inline.txt macdown.txt; do
    if ! cmp -s "$repo_root/App/Resources/Licenses/$license" "$app/Contents/Resources/$license"; then
        echo "Bundled native parser notice differs from verified source: $license" >&2
        exit 1
    fi
done
reading_styles="$app/Contents/Resources/SnowfolioCore_RenderingCore.bundle/Contents/Resources/Styles"
python3 "$repo_root/Tools/verify-reading-styles.py" "$reading_styles"
python3 "$repo_root/Tools/verify-html-template.py" "$app/Contents/Resources/SnowfolioCore_RenderingCore.bundle/Contents/Resources/Templates"
python3 "$repo_root/Tools/verify-css-parser.py" "$app/Contents/Resources/SnowfolioCore_RenderingCore.bundle/Contents/Resources/CSS"
if ! cmp -s "$repo_root/App/Resources/Licenses/CSSParser.txt" "$app/Contents/Resources/CSSParser.txt"; then
    echo "Bundled CSS parser notice differs from source." >&2
    exit 1
fi
theme_resources="$app/Contents/Resources/SnowfolioCore_EditorCore.bundle/Contents/Resources/Themes"
python3 "$repo_root/Tools/verify-editor-themes.py" "$theme_resources"
highlight_resources="$app/Contents/Resources/SnowfolioCore_CodeHighlightCore.bundle/Contents/Resources"
for resource in Prism.js Languages.json LanguageTitles.json Prism-LICENSE.txt Prism-Provenance.json prism.css prism-coy.css prism-dark.css prism-funky.css prism-okaidia.css prism-solarizedlight.css prism-tomorrow.css prism-twilight.css; do
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
