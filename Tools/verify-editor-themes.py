#!/usr/bin/env python3
"""Verify retained editor theme assets and their distribution notice."""
import hashlib
import json
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[1]
source = repo / 'Packages/SnowfolioCore/Sources/EditorCore/Resources/Themes'
root = Path(sys.argv[1]) if len(sys.argv) > 1 else source
record = json.loads((source / 'Provenance.json').read_text())
if json.loads((root / 'Provenance.json').read_text()) != record:
    raise SystemExit('Bundled editor theme provenance differs from source')
actual = {p.name for p in root.iterdir() if p.suffix == '.style'}
if actual != set(record['sha256']):
    raise SystemExit('Unexpected or missing bundled editor themes')
for name, expected in record['sha256'].items():
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
        raise SystemExit('Editor theme checksum mismatch: ' + name)
if (repo / 'LICENSE/macdown.txt').read_bytes() != (repo / 'App/Resources/Licenses/macdown.txt').read_bytes():
    raise SystemExit('Editor theme distribution notice differs from original')
print(f'Verified {len(actual)} original editor themes and distribution notice.')
