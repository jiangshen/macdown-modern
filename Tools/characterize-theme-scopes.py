#!/usr/bin/env python3
"""Characterize original source scopes in a temporary development-only build.

PEG Markdown Highlight: Copyright 2011-2013 Ali Rantakari, MIT option.
Full notice: LICENSE/peg-markdown-highlight.txt. No original parser is shipped.
Native differences below are explicit reviewed expectations, not runtime captures.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

WRAPPER = r'''
#include <stdio.h>
#include <stdlib.h>
#include "pmh_parser.h"
int main(int argc, char **argv) {
  if (argc != 3) return 2;
  FILE *file = fopen(argv[1], "rb"); if (!file) return 3;
  fseek(file,0,SEEK_END); long n=ftell(file); rewind(file);
  char *source=calloc(n+1,1); if (!source) return 4;
  if (fread(source,1,n,file) != n) return 5; fclose(file);
  pmh_element **elements=NULL;
  pmh_markdown_to_elements(source,atoi(argv[2]),&elements);
  int types[]={pmh_HTML_ENTITY,pmh_REFERENCE,pmh_NOTE};
  for (int i=0;i<3;i++) for (pmh_element *item=elements[types[i]];item;item=item->next)
    printf("%s\t%lu\t%lu\n",pmh_element_name_from_type(item->type),item->pos,item->end);
  pmh_free_elements(elements); free(source); return 0;
}
'''

CASES = [{'name': 'named-numeric',
  'source': '中文 😀 **&amp; &#169; &#x1F600; &NotEqualTilde;**',
  'notes': True},
 {'name': 'unknown-overlong',
  'source': '&bogus; &#00000065; &#x0000041;',
  'notes': True,
  'native': {'HTML_ENTITY': [], 'REFERENCE': [], 'NOTE': []},
  'difference': 'Native CommonMark recognizes only standards-valid named entities and enforces '
                'numeric digit limits.'},
 {'name': 'escape',
  'source': '\\&amp; \\\\&copy; &amp;',
  'notes': True,
  'native': {'HTML_ENTITY': [[9, 15], [16, 21]], 'REFERENCE': [], 'NOTE': []},
  'difference': 'Native CommonMark treats a backslash-escaped ampersand as literal; the '
                'original highlighter still marked its entity.'},
 {'name': 'opaque',
  'source': '`&amp;` [label](https://e.test/?x=&amp;) <span title="&amp;">&copy;</span>\n'
            '\n'
            '    &amp;\n',
  'notes': True},
 {'name': 'reference', 'source': '[a]: https://example.com\nText [a].', 'notes': True},
 {'name': 'multiple',
  'source': '  [a]: /a\n[b]:\n  /b\n  "Title"\nText [a] [b].',
  'notes': True,
  'native': {'HTML_ENTITY': [], 'REFERENCE': [[2, 29]], 'NOTE': []},
  'difference': 'A single native-confirmed removed prefix styles adjacent definitions '
                'together, excludes initial block indentation, and includes their internal '
                'newline.'},
 {'name': 'container', 'source': '> [a]: /a\n>\n> [a]\n\n- [b]: /b\n\n  [b]', 'notes': True},
 {'name': 'notes',
  'source': 'Text[^n].\n\n[^n]: **Note**\n\n    Continued text.\n\n[^unused]: Unused.',
  'notes': True,
  'native': {'HTML_ENTITY': [], 'REFERENCE': [], 'NOTE': [[4, 8], [11, 47], [48, 66]]},
  'difference': 'The original NOTE scope emitted no elements, even with its notes extension. '
                'Native footnote references and definitions (including unused definitions) now '
                'receive NOTE presentation; a finalized multiline definition also includes its '
                'trailing line ending.'},
 {'name': 'notes-disabled', 'source': '[^n]: /note\n\nText [^n]', 'notes': False}]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    original = root / 'Dependency/peg-markdown-highlight'
    inputs = ['Makefile', 'pmh_grammar.leg', 'pmh_parser_head.c', 'pmh_parser_foot.c',
              'pmh_parser.h', 'pmh_definitions.h', 'tools/combine_parser_files.sh',
              'greg/Makefile', 'greg/greg.c', 'greg/greg.h', 'greg/tree.c', 'greg/compile.c']
    cases = []
    with tempfile.TemporaryDirectory(prefix='snowfolio-scope-capture-') as tmp:
        temp = Path(tmp)
        engine = temp / 'original'
        shutil.copytree(original, engine)
        # Force generation from unchanged, checksummed grammar/generator sources.
        for name in ['pmh_parser.c', 'pmh_parser_core.c', 'greg/greg', 'greg/greg.o', 'greg/tree.o', 'greg/compile.o']:
            (engine / name).unlink(missing_ok=True)
        subprocess.run(['make'], cwd=engine, check=True, stdout=subprocess.DEVNULL)
        (temp / 'capture.c').write_text(WRAPPER)
        exe = temp / 'capture'
        subprocess.run(['xcrun', 'clang', '-I', str(engine), str(engine / 'pmh_parser.c'),
                        str(temp / 'capture.c'), '-o', str(exe)], check=True)
        for definition in CASES:
            path = temp / 'input.md'
            path.write_bytes(definition['source'].encode())
            output = subprocess.check_output([str(exe), str(path), str(int(definition['notes']))], text=True)
            spans = {kind: [] for kind in ['HTML_ENTITY', 'REFERENCE', 'NOTE']}
            for line in output.splitlines():
                kind, start, end = line.split('\t')
                spans[kind].append([int(start), int(end)])
            for ranges in spans.values(): ranges.sort()
            cases.append({**definition, 'legacy': spans})
    args.output.write_text(json.dumps({
        'engine': 'Vendored PEG Markdown Highlight, regenerated unchanged in a temporary directory',
        'offsetUnit': 'Unicode code points, end exclusive',
        'notice': 'LICENSE/peg-markdown-highlight.txt',
        'sourceSHA256': {name: hashlib.sha256((original / name).read_bytes()).hexdigest() for name in inputs},
        'cases': cases,
    }, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
