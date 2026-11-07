#!/usr/bin/env python3
"""Verify vendored parser bytes, the two-directive configuration patch and license."""
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
for name, original in record['originalFiles'].items():
    value = (package / name).read_bytes()
    if name == 'src/inlines.c':
        value = value.replace(b"#ifndef CMARK_DISABLE_ATTRIBUTES\n  case '^':", b"  case '^':", 1)
        value = value.replace(b'    break;\n#endif\n  }\n\n  if (subj->pos == initpos)', b'    break;\n  }\n\n  if (subj->pos == initpos)', 1)
    if hashlib.sha256(value).hexdigest() != original:
        raise SystemExit('Unexpected native parser source change: ' + name)
license_path = root / 'App/Resources/Licenses/swift-cmark.txt'
if license_path.read_bytes() != (package / 'COPYING').read_bytes():
    raise SystemExit('Native parser distribution notice mismatch')
print('Native parser source and distribution notice verified.')
