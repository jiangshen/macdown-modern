#!/usr/bin/env python3
"""Rebuild pinned third-party Prism resources; requires Python 3 and Node, no npm install."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.30.0'
URL = f'https://registry.npmjs.org/prismjs/-/prismjs-{VERSION}.tgz'
INTEGRITY = 'DEvV2ZF2r2/63V+tK8hQvrR2ZGn10srHbXviTlcv7Kpzw8jWiNTqbVgjO3IY8RxrrOUF8VPMQQFysYYYv0YZxw=='
DEST = ROOT / 'Packages/SnowfolioCore/Sources/CodeHighlightCore/Resources'

def main():
    archive = urllib.request.urlopen(URL, timeout=30).read()
    if base64.b64encode(hashlib.sha512(archive).digest()).decode() != INTEGRITY:
        raise ValueError('Prism archive checksum mismatch')
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='snowfolio-prism-') as folder:
        folder = Path(folder)
        archive_path = folder / 'prism.tgz'
        archive_path.write_bytes(archive)
        # Only regular npm package files/directories from the verified archive.
        with tarfile.open(archive_path) as tar:
            for member in tar.getmembers():
                target = folder / member.name
                if not target.resolve().is_relative_to(folder.resolve()) or not (member.isfile() or member.isdir()):
                    raise ValueError('Unexpected archive entry')
            tar.extractall(folder)
        package = folder / 'package'
        script = r'''
const fs = require('node:fs');
const path = require('node:path');
const root = process.argv[1], destination = process.argv[2];
const components = require(path.join(root, 'components.json'));
const getLoader = require(path.join(root, 'dependencies.js'));
const names = Object.keys(components.languages).filter(id => id !== 'meta');
const order = [];
getLoader(components, names).load(id => order.push(id));
const files = ['prism-core', ...order.filter(id => id !== 'core').map(id => 'prism-' + id)];
let bundle = files.map(id => fs.readFileSync(path.join(root, 'components', id + '.min.js'), 'utf8')).join('\n;\n');
// Prism normalizes NBSP to ordinary space in util.encode. Code text must remain
// exact in MacDown; omit only that conversion, leaving its HTML escaping intact.
const nbspConversion = '.replace(/\\u00a0/g," ")';
if (bundle.split(nbspConversion).length !== 2) throw new Error('Prism NBSP patch did not match exactly once');
bundle = bundle.replace(nbspConversion, '');
fs.writeFileSync(path.join(destination, 'Prism.js'), '/*! PrismJS 1.30.0 | MIT | See Prism-LICENSE.txt */\n' + bundle + '\n');
const vm = require('node:vm');
const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(bundle, sandbox);
const languages = {};
for (const id of names) {
  // Extras modify other grammars and are not standalone fence languages.
  if (!sandbox.Prism.languages[id]) continue;
  languages[id] = id;
  const alias = components.languages[id].alias || [];
  for (const item of Array.isArray(alias) ? alias : [alias]) languages[item] = id;
}
fs.writeFileSync(path.join(destination, 'Languages.json'), JSON.stringify(languages, null, 2) + '\n');
console.log(order.length + ' pinned components, ' + new Set(Object.values(languages)).size + ' standalone grammars');
'''
        subprocess.run(['node', '-e', script, str(package), str(DEST)], check=True)
        (DEST / 'Prism-LICENSE.txt').write_bytes((package / 'LICENSE').read_bytes())
        for theme in sorted((package / 'themes').glob('*.css')):
            if not theme.name.endswith('.min.css'):
                (DEST / theme.name).write_bytes(theme.read_bytes())
    provenance = {'version': VERSION, 'source': URL, 'gitCommit': '93cca40b364215210f23a9e35f085a682a2b8175', 'archiveIntegrity': 'sha512-' + INTEGRITY, 'patches': ['Omit util.encode NBSP-to-space normalization; preserve exact code text'],
                  'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(DEST.iterdir()) if p.name != 'Prism-Provenance.json'}}
    (DEST / 'Prism-Provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')

if __name__ == '__main__':
    main()
