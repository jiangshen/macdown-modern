#!/usr/bin/env python3
"""Reproduce the pinned native parser and audited upstream CommonMark corrections."""
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
BACKPORT_VERSION = '0.31.2'
BACKPORT_COMMIT = 'eec0eeba6d31189fd828314576494566d539b1e3'
BACKPORT_URL = 'https://codeload.github.com/commonmark/cmark/tar.gz/refs/tags/0.31.2'
BACKPORT_SHA256 = 'f9bc5ca38bcb0b727f0056100fac4d743e768872e3bacec7746de28f5700d697'
MANIFEST = '''// swift-tools-version: 6.4
import PackageDescription

// Native C is maintained third-party parser code. First-party integration is Swift.
let package = Package(
  name: "SnowfolioMarkdownEngine",
  platforms: [.macOS("27.0")],
  products: [
    .executable(name: "cmark-audit", targets: ["cmark-audit"]),
    .library(name: "cmark-gfm", targets: ["cmark-gfm"]),
    .library(name: "cmark-gfm-extensions", targets: ["cmark-gfm-extensions"]),
  ],
  targets: [
    .executableTarget(name: "cmark-audit", dependencies: ["cmark-gfm"], path: "Audit"),
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
    parser.add_argument('--commonmark-archive', type=Path)
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
    changes = {}
    def apply(name, before, after, reason):
        path = DEST / name
        content = path.read_text()
        if content.count(before) != 1:
            raise SystemExit('Native parser patch boundary changed: ' + name)
        path.write_text(content.replace(before, after))
        changes.setdefault(name, []).append({'before': before, 'after': after, 'reason': reason})
    opening = "  case '^':\n    // TODO: Support a name between ^ and ["
    closing = "    break;\n  }\n\n  if (subj->pos == initpos)"
    apply('src/inlines.c', opening, '#ifndef CMARK_DISABLE_ATTRIBUTES\n' + opening,
        'Make Apple attributed-string inline grammar optional')
    apply('src/inlines.c', closing, '    break;\n#endif\n  }\n\n  if (subj->pos == initpos)',
        'Close attribute grammar configuration gate')
    backport_data = args.commonmark_archive.read_bytes() if args.commonmark_archive else urllib.request.urlopen(BACKPORT_URL, timeout=45).read()
    if hashlib.sha256(backport_data).hexdigest() != BACKPORT_SHA256:
        raise SystemExit('CommonMark backport archive integrity mismatch')
    backports = {}
    with tarfile.open(fileobj=io.BytesIO(backport_data)) as tar:
        for entry in tar:
            if not entry.isfile():
                continue
            path = '/'.join(Path(entry.name).parts[1:])
            if path in ('src/html.c', 'src/houdini_html_u.c', 'src/utf8.c', 'COPYING'):
                backports[path] = tar.extractfile(entry).read()
    def section(text, start, end):
        a = text.index(start)
        b = text.index(end, a)
        return text[a:b]
    html = (DEST / 'src/html.c').read_text()
    upstream_html = backports['src/html.c'].decode()
    start, end = '  case CMARK_NODE_STRONG:', '  case CMARK_NODE_EMPH:'
    apply('src/html.c', section(html, start, end), section(upstream_html, start, end),
        'CommonMark 0.31.2 HTML renderer: preserve nested strong elements')
    entities = (DEST / 'src/houdini_html_u.c').read_text()
    upstream_entities = backports['src/houdini_html_u.c'].decode()
    start, end = '    int codepoint = 0;', '      if (codepoint == 0'
    apply('src/houdini_html_u.c', section(entities, start, end), section(upstream_entities, start, end),
        'CommonMark 0.31.2: numeric references have at most seven decimal or six hex digits')
    utf8 = (DEST / 'src/utf8.c').read_text()
    upstream_utf8 = backports['src/utf8.c'].decode()
    name = 'int cmark_utf8proc_is_punctuation'
    original_function = utf8[utf8.index(name):]
    upstream_function = upstream_utf8[upstream_utf8.index(name):].replace(
        'cmark_utf8proc_is_punctuation_or_symbol', 'cmark_utf8proc_is_punctuation', 1)
    apply('src/utf8.c', original_function, upstream_function,
        'CommonMark 0.31.2 Unicode punctuation-or-symbol table; retain existing public symbol name')
    (DEST / 'CommonMark-COPYING').write_bytes(backports['COPYING'])
    (ROOT / 'App/Resources/Licenses/CommonMark-cmark.txt').write_bytes(backports['COPYING'])
    (DEST / 'Patches.json').write_text(json.dumps(changes, indent=2) + '\n')
    (DEST / 'Package.swift').write_text(MANIFEST)
    provenance = {
        'source': 'https://github.com/swiftlang/swift-cmark', 'version': VERSION,
        'revision': COMMIT, 'archiveURL': URL, 'archiveSHA256': SHA256,
        'configuration': 'CMARK_DISABLE_ATTRIBUTES disables the Apple attributed-string inline grammar that can swallow ordinary Markdown text.',
        'backports': {'source': 'https://github.com/commonmark/cmark',
            'version': BACKPORT_VERSION, 'revision': BACKPORT_COMMIT,
            'archiveURL': BACKPORT_URL, 'archiveSHA256': BACKPORT_SHA256,
            'files': {name: hashlib.sha256(value).hexdigest() for name, value in backports.items()}},
        'patches': 'Patches.json contains exact reversible native-source replacements and their upstream origin',
        'originalFiles': original,
        'files': {name: hashlib.sha256((DEST / name).read_bytes()).hexdigest()
            for name in sorted([*original, 'Package.swift', 'Patches.json', 'CommonMark-COPYING'])},
    }
    (DEST / 'Provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print('Native parser', VERSION, 'verified with pinned CommonMark', BACKPORT_VERSION, 'backports')


if __name__ == '__main__':
    main()
