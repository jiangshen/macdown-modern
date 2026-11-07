#!/usr/bin/env python3
"""Verify the pinned CSS parser and its distribution notice without Node/network access."""
import hashlib
import json
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[1]
source = repo / 'Packages/SnowfolioCore/Sources/RenderingCore/Resources/CSS'
root = Path(sys.argv[1]) if len(sys.argv) > 1 else source
record = json.loads((source / 'CSSParser-Provenance.json').read_text())
if json.loads((root / 'CSSParser-Provenance.json').read_text()) != record:
    raise SystemExit('CSS parser provenance differs from source')
for name, expected in record['files'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('CSS parser checksum mismatch: ' + name)
for name, expected in record['buildInputs'].items():
    if hashlib.sha256((repo / 'Tools/CSSParserBuild' / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('CSS parser build input differs: ' + name)
if (root / 'CSSParser-LICENSE.txt').read_bytes() != (repo / 'App/Resources/Licenses/CSSParser.txt').read_bytes():
    raise SystemExit('CSS parser distribution notice mismatch')
print('Verified pinned CSS parser and MIT distribution notice.')
