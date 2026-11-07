#!/usr/bin/env python3
"""Verify preserved reading styles in source and the packaged application."""
import hashlib
import json
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[1]
source = repo / 'Packages/SnowfolioCore/Sources/RenderingCore/Resources/Styles'
root = Path(sys.argv[1]) if len(sys.argv) > 1 else source
record = json.loads((source / 'Provenance.json').read_text())
if json.loads((root / 'Provenance.json').read_text()) != record:
    raise SystemExit('Bundled reading style provenance differs from source')
actual = {p.name for p in root.iterdir() if p.suffix == '.css'}
if actual != set(record['files']):
    raise SystemExit('Unexpected or missing reading styles')
for name, expected in record['files'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Reading style checksum mismatch: ' + name)
    if (root / name).read_bytes() != (repo / 'MacDown/Resources/Styles' / name).read_bytes():
        raise SystemExit('Reading style differs from retained original: ' + name)
notice = (root / 'MacDown-LICENSE.txt').read_bytes()
if hashlib.sha256(notice).hexdigest() != record['noticeSHA256'] or notice != (repo / 'LICENSE/macdown.txt').read_bytes():
    raise SystemExit('Reading style distribution notice mismatch')
print(f'Verified {len(actual)} original reading styles and distribution notice.')
