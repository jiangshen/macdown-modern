#!/usr/bin/env python3
"""Build the pinned CSS parser/walker without its lexer data or source-map dependencies."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'Tools/CSSParserBuild'
DEST = ROOT / 'Packages/SnowfolioCore/Sources/RenderingCore/Resources/CSS'


def main():
    with tempfile.TemporaryDirectory(prefix='snowfolio-css-parser-') as temporary:
        work = Path(temporary)
        for name in ('package.json', 'package-lock.json', 'entry.js'):
            shutil.copyfile(BUILD / name, work / name)
        subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], check=True, cwd=work)
        subprocess.run(['node', str(work / 'node_modules/esbuild/bin/esbuild'), str(work / 'entry.js'),
                        '--bundle', '--minify', '--format=iife', '--global-name=SnowfolioCSS',
                        '--target=es2020', '--charset=utf8', '--legal-comments=inline',
                        '--outfile=' + str(work / 'CSSParser.js'),
                        '--metafile=' + str(work / 'meta.json')], check=True, cwd=work)
        inputs = sorted(json.loads((work / 'meta.json').read_text())['inputs'])
        if any(not (name == 'entry.js' or name.startswith('node_modules/css-tree/lib/')) for name in inputs):
            raise ValueError('Unexpected bundled CSS parser dependency')
        DEST.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / 'CSSParser.js', DEST / 'CSSParser.js')
        notice = work / 'node_modules/css-tree/LICENSE'
        shutil.copyfile(notice, DEST / 'CSSParser-LICENSE.txt')
        shutil.copyfile(notice, ROOT / 'App/Resources/Licenses/CSSParser.txt')
        record = {
            'package': 'css-tree', 'version': '3.2.1', 'source': 'https://github.com/csstree/csstree',
            'archive': 'https://registry.npmjs.org/css-tree/-/css-tree-3.2.1.tgz',
            'scope': 'Parser, walker and identifier decoding only; no lexer data, source-map code or network/native bridge.',
            'buildInputs': {name: hashlib.sha256((BUILD / name).read_bytes()).hexdigest()
                            for name in ('package.json', 'package-lock.json', 'entry.js')},
            'bundledModules': inputs,
            'files': {name: hashlib.sha256((DEST / name).read_bytes()).hexdigest()
                      for name in ('CSSParser.js', 'CSSParser-LICENSE.txt')}
        }
        (DEST / 'CSSParser-Provenance.json').write_text(json.dumps(record, indent=2) + '\n')
        print('Pinned CSS parser and MIT distribution notice built.')


if __name__ == '__main__':
    main()
