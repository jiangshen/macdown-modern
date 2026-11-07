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
    apply('src/include/cmark-gfm.h', '#define CMARK_OPT_TABLE_ROWSPAN_DITTO (1 << 21)',
        '#define CMARK_OPT_TABLE_ROWSPAN_DITTO (1 << 21)\n\n'
        '/** Snowfolio configuration extension: leave fence syntax to ordinary block/inline parsing.\n'
        ' * Default CommonMark behavior is unchanged when this bit is absent.\n */\n'
        '#define CMARK_OPT_NO_FENCED_CODE (1 << 22)',
        'Local runtime configuration gate for the existing fenced-code preference; not an upstream API')
    apply('src/blocks.c',
        '    } else if (!indented && (matched = scan_open_code_fence(',
        '    } else if (!indented && !(parser->options & CMARK_OPT_NO_FENCED_CODE) &&\n'
        '               (matched = scan_open_code_fence(',
        'Allow opting out of the existing fence recognizer; all remaining block/inline grammar stays native')
    apply('src/include/syntax_extension.h', '  cmark_match_inline_func         match_inline;\n', '  cmark_match_inline_func         match_inline;\n  cmark_match_inline_func         match_inline_before;\n', 'Local generic extension bridge: optional inline callback before built-in token handling; no dialect grammar in C')
    apply('src/syntax_extension.c', 'void cmark_syntax_extension_set_match_inline_func(cmark_syntax_extension *extension,', 'void cmark_syntax_extension_set_match_inline_before_func(cmark_syntax_extension *extension,\n                                                         cmark_match_inline_func func) {\n  extension->match_inline_before = func;\n}\n\nvoid cmark_syntax_extension_set_match_inline_func(cmark_syntax_extension *extension,', 'Local generic extension bridge setter; existing extension callbacks and defaults remain unchanged')
    apply('src/include/cmark-gfm-extension_api.h', 'CMARK_GFM_EXPORT\nvoid cmark_syntax_extension_set_match_inline_func(cmark_syntax_extension *extension,', "/** Snowfolio extension API (not upstream): try this optional callback before\n * built-in inline token handling. On success it must advance the cursor and\n * return a positioned node. On failure it must return NULL without changing the\n * parser. The parser adjusts consumed multiline spans and the returned node's\n * end position; callback start/end positions initially describe a single line.\n * Escapes, code, HTML and destinations consumed by earlier native tokens remain\n * opaque. An unset callback leaves ordinary CommonMark behavior unchanged.\n */\nCMARK_GFM_EXPORT\nvoid cmark_syntax_extension_set_match_inline_before_func(cmark_syntax_extension *extension,\n                                                         cmark_match_inline_func func);\n\nCMARK_GFM_EXPORT\nvoid cmark_syntax_extension_set_match_inline_func(cmark_syntax_extension *extension,", 'Document the opt-in Swift callback bridge and its ownership/cursor/source-position contract; not an upstream API')
    apply('src/blocks.c', '  if (extension->match_inline || extension->insert_inline_from_delim) {', '  if (extension->match_inline || extension->match_inline_before || extension->insert_inline_from_delim) {', 'Register extensions which provide only the optional pre-token callback')
    apply('src/inlines.c', '                                  subject *subj) {\n  cmark_node *res = NULL;', '                                  subject *subj, bool before_builtin) {\n  cmark_node *res = NULL;', 'Route optional pre-token callbacks separately from existing fallback callbacks')
    apply('src/inlines.c', '    res = ext->match_inline(ext, parser, parent, c, subj);', '    cmark_match_inline_func callback = before_builtin ? ext->match_inline_before : ext->match_inline;\n    if (callback)\n      res = callback(ext, parser, parent, c, subj);', 'Keep absent pre-token and fallback callbacks inert')
    apply('src/inlines.c', '  c = peek_char(subj);\n  if (c == 0) {\n    return 0;\n  }\n  switch (c) {', '  c = peek_char(subj);\n  if (c == 0) {\n    return 0;\n  }\n  new_inl = try_extensions(parser, parent, c, subj, true);\n  if (new_inl) {\n    adjust_subj_node_newlines(subj, new_inl, subj->pos - initpos, 0, options);\n    cmark_node_append_child(parent, new_inl);\n    return 1;\n  }\n  switch (c) {', 'Dispatch opt-in Swift dialect callbacks before built-ins; retain native multiline position accounting')
    apply('src/inlines.c', '      new_inl = try_extensions(parser, parent, c, subj);', '      new_inl = try_extensions(parser, parent, c, subj, false);', 'Existing inline extension callbacks retain their original fallback position')
    apply('src/inlines.c', '// Parse an inline, advancing subject, and add it as a child of parent.', '// Extension callbacks can return a subtree parsed in its own inline context.\n// Apply the same no-nested-link rule as handle_close_bracket to the outer context.\nstatic void S_update_link_context(subject *subj, cmark_node *root) {\n  cmark_node *node = root;\n  if (!subj->last_bracket)\n    return;\n  while (node) {\n    if (node->type == CMARK_NODE_LINK) {\n      subj->no_link_openers = true;\n      return;\n    }\n    if (node->type != CMARK_NODE_IMAGE && node->first_child) {\n      node = node->first_child;\n    } else {\n      while (node != root && !node->next)\n        node = node->parent;\n      if (node == root)\n        return;\n      node = node->next;\n    }\n  }\n}\n\n// Parse an inline, advancing subject, and add it as a child of parent.', 'Preserve native link-bracket context for extension-created subtrees; image descriptions stay opaque')
    apply('src/inlines.c', '    adjust_subj_node_newlines(subj, new_inl, subj->pos - initpos, 0, options);\n    cmark_node_append_child(parent, new_inl);', '    adjust_subj_node_newlines(subj, new_inl, subj->pos - initpos, 0, options);\n    S_update_link_context(subj, new_inl);\n    cmark_node_append_child(parent, new_inl);', 'Apply the native no-nested-link invariant to pre-token callback results')
    apply('src/inlines.c', '  if (new_inl != NULL) {\n    append_child(parent, new_inl);', '  if (new_inl != NULL) {\n    S_update_link_context(subj, new_inl);\n    append_child(parent, new_inl);', 'Apply the same context invariant to existing inline extension subtrees')
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
        'configuration': 'CMARK_DISABLE_ATTRIBUTES opts out of Apple attributed-string grammar; local CMARK_OPT_NO_FENCED_CODE (bit 22) opts out of fence recognition per render, preserving the original preference. Default native fence behavior is unchanged. Local set_match_inline_before_func is a generic opt-in extension bridge for Swift dialect callbacks; the native engine adjusts multiline positions, with no dialect grammar in C.',
        'backports': {'source': 'https://github.com/commonmark/cmark',
            'version': BACKPORT_VERSION, 'revision': BACKPORT_COMMIT,
            'archiveURL': BACKPORT_URL, 'archiveSHA256': BACKPORT_SHA256,
            'files': {name: hashlib.sha256(value).hexdigest() for name, value in backports.items()}},
        'patches': 'Patches.json contains exact reversible source replacements; reasons distinguish local configuration gates from upstream backports',
        'originalFiles': original,
        'files': {name: hashlib.sha256((DEST / name).read_bytes()).hexdigest()
            for name in sorted([*original, 'Package.swift', 'Patches.json', 'CommonMark-COPYING'])},
    }
    (DEST / 'Provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
    print('Native parser', VERSION, 'verified with pinned CommonMark', BACKPORT_VERSION, 'backports')


if __name__ == '__main__':
    main()
