#!/usr/bin/env python3
"""Verify vendored parser bytes, reversible configuration and upstream patches and license."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
package = root / 'Packages/MarkdownEngine'
record = json.loads((package / 'Provenance.json').read_text())
actual = {str(p.relative_to(package)) for directory in ('src', 'extensions')
    for p in (package / directory).rglob('*') if p.is_file()}
expected_sources = {name for name in record['originalFiles'] if name.startswith(('src/', 'extensions/'))}
if actual != expected_sources:
    raise SystemExit('Unexpected or missing native parser source files')
for name, expected in record['files'].items():
    target = package / name
    if hashlib.sha256(target.read_bytes()).hexdigest() != expected:
        raise SystemExit('Native parser checksum mismatch: ' + name)
patches = json.loads((package / 'Patches.json').read_text())
for name, original in record['originalFiles'].items():
    value = (package / name).read_bytes()
    for patch in reversed(patches.get(name, [])):
        before, after = patch['before'].encode(), patch['after'].encode()
        if value.count(after) != 1:
            raise SystemExit('Native parser patch boundary mismatch: ' + name)
        value = value.replace(after, before, 1)
    if hashlib.sha256(value).hexdigest() != original:
        raise SystemExit('Unexpected native parser source change: ' + name)
backport_notice = (package / 'CommonMark-COPYING').read_bytes()
if hashlib.sha256(backport_notice).hexdigest() != record['backports']['files']['COPYING']:
    raise SystemExit('CommonMark backport source notice mismatch')
if backport_notice != (root / 'App/Resources/Licenses/CommonMark-cmark.txt').read_bytes():
    raise SystemExit('CommonMark backport distribution notice mismatch')
license_path = root / 'App/Resources/Licenses/swift-cmark.txt'
if license_path.read_bytes() != (package / 'COPYING').read_bytes():
    raise SystemExit('Native parser distribution notice mismatch')
print('Native parser source and distribution notice verified.')
