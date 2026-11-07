#!/usr/bin/env python3
"""Reproduce the pinned native parser with an opt-out for Apple's attribute grammar."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'Packages/MarkdownEngine'
VERSION = '0.9.0'
COMMIT = '08ddb528923cc1a6527e02b7a1aee9e516ca749a'
URL = 'https://codeload.github.com/swiftlang/swift-cmark/tar.gz/refs/tags/0.9.0'
SHA256 = '21e88b2ac458edda8c3376336e589f6aff2d9ac1091794ab6461299e6248e0e7'
MANIFEST = '''// swift-tools-version: 6.4
import PackageDescription

// Native C is maintained third-party parser code. First-party integration is Swift.
let package = Package(
  name: "SnowfolioMarkdownEngine",
  platforms: [.macOS("27.0")],
  products: [
    .library(name: "cmark-gfm", targets: ["cmark-gfm"]),
    .library(name: "cmark-gfm-extensions", targets: ["cmark-gfm-extensions"]),
  ],
  targets: [
    .target(
      name: "cmark-gfm", path: "src",
      exclude: ["scanners.re", "libcmark-gfm.pc.in", "config.h.in", "CMakeLists.txt"],
      cSettings: [.define("CMARK_DISABLE_ATTRIBUTES")]),
    .target(
      name: "cmark-gfm-extensions", dependencies: ["cmark-gfm"], path: "extensions",
      exclude: ["CMakeLists.txt", "ext_scanners.re"]),
  ]
)
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    data = args.archive.read_bytes() if args.archive else urllib.request.urlopen(URL, timeout=45).read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit('Native parser archive integrity mismatch')
    original = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tar:
        for entry in tar:
            parts = Path(entry.name).parts
            if not entry.isfile() or len(parts) < 2:
                continue
            path = Path(*parts[1:])
            if '..' in path.parts or path.is_absolute():
                raise SystemExit('Invalid native parser archive path')
            if path.parts[0] not in ('src', 'extensions', 'COPYING'):
                continue
            value = tar.extractfile(entry).read()
            original[str(path)] = hashlib.sha256(value).hexdigest()
            target = DEST / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value)
    source = DEST / 'src/inlines.c'
    text = source.read_text()
    opening = "  case '^':\n    // TODO: Support a name between ^ and ["
    closing = "    break;\n  }\n\n  if (subj->pos == initpos)"
    if text.count(opening) != 1 or text.count(closing) != 1:
        raise SystemExit('Native parser attribute boundary changed')
    text = text.replace(opening, '#ifndef CMARK_DISABLE_ATTRIBUTES\n' + opening)
    text = text.replace(closing, '    break;\n#endif\n  }\n\n  if (subj->pos == initpos)')
    source.write_text(text)
    (DEST / 'Package.swift').write_text(MANIFEST)
    provenance = {
        'source': 'https://github.com/swiftlang/swift-cmark', 'version': VERSION,
        'revision': COMMIT, 'archiveURL': URL, 'archiveSHA256': SHA256,
        'patch': 'Two preprocessor directives make the ^[ attributed-string grammar optional via CMARK_DISABLE_ATTRIBUTES; all other native engine source is unchanged.',
        'reason': 'This grammar is outside CommonMark/GFM and original MacDown. Its failed reference matching can swallow visible text. The app opts out; native grammar remains the same pinned maintained parser.',
        'originalFiles': original,
        'files': {name: hashlib.sha256((DEST / name).read_bytes()).hexdigest()
            for name in sorted([*original, 'Package.swift'])},
    }
    (DEST / 'Provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print('Native parser', VERSION, 'verified; attribute grammar disabled by package configuration')


if __name__ == '__main__':
    main()
