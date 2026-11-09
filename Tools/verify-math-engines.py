#!/usr/bin/env python3
"""Verify pinned math engines, distribution notices and offline font resources."""
import hashlib
import json
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
resources = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'Packages/SnowfolioCore/Sources/MathCore/Resources'
notices = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / 'App/Resources/Licenses'
for name, version in [('KaTeX', '0.19.1'), ('MathJax4', '4.1.3')]:
    provenance = json.loads((resources / (name + '-Provenance.json')).read_text())
    if provenance['version'] != version:
        raise SystemExit('Unexpected math engine version: ' + name)
    for filename, digest in provenance['files'].items():
        if hashlib.sha256((resources / filename).read_bytes()).hexdigest() != digest:
            raise SystemExit('Math engine resource checksum mismatch: ' + filename)
    if (resources / (name + '-LICENSE.txt')).read_bytes() != (notices / (name + '.txt')).read_bytes():
        raise SystemExit('Math engine distribution notice mismatch: ' + name)
    if len(sys.argv) == 1:
        for filename, digest in provenance.get('buildInputs', {}).items():
            if hashlib.sha256((ROOT / 'Tools/MathJaxBuild' / filename).read_bytes()).hexdigest() != digest:
                raise SystemExit('MathJax reproduction input differs: ' + filename)
mathjax = json.loads((resources / 'MathJax4-Provenance.json').read_text())
if mathjax.get('offlineRegistry') != {'rootURL': 'snowfolio-math:', 'runtimeLoading': False}:
    raise SystemExit('Unexpected MathJax registry policy')
modules = mathjax['bundledModules']
require_module = 'node_modules/@mathjax/src/mjs/input/tex/require/RequireConfiguration.js'
if require_module not in modules or any(
        '/autoload/' in name or ('/require/' in name and name != require_module) or
        ('/html/' in name and '/input/tex/' in name) for name in modules):
    raise SystemExit('Unexpected MathJax TeX loading or arbitrary HTML module')
if (resources / 'KaTeX.css').read_text().count('data:font/woff2;base64,') != 20:
    raise SystemExit('Offline KaTeX fonts missing')
print('Pinned offline math engines and original distribution notices verified.')
