#!/usr/bin/env python3
"""Reproduce the pinned offline MathJax module boundary and original notices."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'Tools/MathJaxBuild'
DEST = ROOT / 'Packages/SnowfolioCore/Sources/MathCore/Resources'
INPUTS = ('package.json', 'package-lock.json', 'entry.mjs', 'font-default.mjs')


def build(work):
    work.mkdir(exist_ok=True)
    for name in INPUTS:
        shutil.copyfile(BUILD / name, work / name)
    subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund',
                    '--cache', str(work / 'npm-cache')], check=True, cwd=work)
    subprocess.run(['node', str(work / 'node_modules/esbuild/bin/esbuild'), str(work / 'entry.mjs'),
                    '--bundle', '--minify', '--format=iife', '--global-name=SnowfolioMathJax',
                    '--platform=browser', '--target=es2022', '--charset=utf8', '--legal-comments=inline',
                    '--define:import.meta.url="snowfolio-math:"',
                    '--alias:#default-font/svg/default.js=' + str(work / 'font-default.mjs'),
                    '--outfile=' + str(work / 'MathJax4.js'),
                    '--metafile=' + str(work / 'meta.json')], check=True, cwd=work)
    modules = sorted(json.loads((work / 'meta.json').read_text())['inputs'])
    if any(not (name in ('entry.mjs', 'font-default.mjs') or
               name.startswith(('node_modules/@mathjax/src/mjs/',
                                'node_modules/@mathjax/mathjax-tex-font/mjs/')))
           for name in modules):
        raise ValueError('Unexpected MathJax dependency')
    require_module = 'node_modules/@mathjax/src/mjs/input/tex/require/RequireConfiguration.js'
    if require_module not in modules or any(
            '/autoload/' in name or
            ('/require/' in name and name != require_module) or
            ('/html/' in name and '/input/tex/' in name) for name in modules):
        raise ValueError('Unexpected TeX loading or arbitrary HTML module')
    DEST.mkdir(exist_ok=True)
    shutil.copyfile(work / 'MathJax4.js', DEST / 'MathJax4.js')
    notice = work / 'node_modules/@mathjax/src/LICENSE'
    shutil.copyfile(notice, DEST / 'MathJax4-LICENSE.txt')
    shutil.copyfile(notice, ROOT / 'App/Resources/Licenses/MathJax4.txt')
    lock = json.loads((BUILD / 'package-lock.json').read_text())
    packages = {name: {'version': info['version'], 'integrity': info['integrity'],
                       'source': info['resolved']}
                for name, info in lock['packages'].items()
                if name in ('node_modules/@mathjax/src', 'node_modules/@mathjax/mathjax-tex-font',
                            'node_modules/esbuild')}
    record = {'version': '4.1.3', 'fontVersion': '4.1.3', 'packages': packages,
              'offlineRegistry': {'rootURL': 'snowfolio-math:', 'runtimeLoading': False},
              'scope': 'Direct TeX/AMS/newcommand/bbox/color/cancel/mathtools/boldsymbol/braket/textmacros/verb/unicode/extpfeil modules, SVG original TeX outlines, LiteDOM and MathML serializer. Upstream require parser and package registry imported with page-loader bootstrap disabled in Swift; only bundled packages/legacy aliases are preloaded, defaultAllow=false and Loader.load removed. No document scripts, native DOM, Node/file/network bridge or TeX HTML package. Swift owns orchestration.',
              'buildInputs': {name: hashlib.sha256((BUILD / name).read_bytes()).hexdigest()
                              for name in INPUTS}, 'bundledModules': modules,
              'files': {name: hashlib.sha256((DEST / name).read_bytes()).hexdigest()
                        for name in ('MathJax4.js', 'MathJax4-LICENSE.txt')}}
    (DEST / 'MathJax4-Provenance.json').write_text(json.dumps(record, indent=2) + '\n')
    print('Pinned offline MathJax 4.1.3 module boundary and Apache-2.0 notice built.')


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='snowfolio-mathjax-build-') as temporary:
        build(Path(temporary))
