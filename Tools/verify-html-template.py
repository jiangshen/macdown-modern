#!/usr/bin/env python3
"""Verify the byte-preserved HTML template and its distribution notice."""
import hashlib
import json
from pathlib import Path
import sys

repo = Path(__file__).resolve().parents[1]
source = repo / 'Packages/SnowfolioCore/Sources/RenderingCore/Resources/Templates'
root = Path(sys.argv[1]) if len(sys.argv) > 1 else source
record = json.loads((source / 'Provenance.json').read_text())
if json.loads((root / 'Provenance.json').read_text()) != record:
    raise SystemExit('Bundled template provenance differs from source')
if {p.name for p in root.glob('*.handlebars')} != set(record['files']):
    raise SystemExit('Unexpected or missing HTML templates')
for name, expected in record['files'].items():
    data = (root / name).read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise SystemExit('Template checksum mismatch: ' + name)
    if data != (repo / record['source']).read_bytes():
        raise SystemExit('Template differs from retained original: ' + name)
notice = (root / record['notice']).read_bytes()
if hashlib.sha256(notice).hexdigest() != record['noticeSHA256']:
    raise SystemExit('Template distribution notice checksum mismatch')
if notice != (repo / 'LICENSE/macdown.txt').read_bytes():
    raise SystemExit('Template distribution notice differs from original')
print('Verified original Default HTML template and distribution notice.')
