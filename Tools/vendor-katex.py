#!/usr/bin/env python3
"""Reproduce pinned offline KaTeX code, self-contained CSS/fonts and license notices."""
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VERSION = "0.19.1"
URL = f"https://registry.npmjs.org/katex/-/katex-{VERSION}.tgz"
INTEGRITY = "jG8uKntjSEcm2EpQOh0XturpPuuC9r3Sq5HLHdsFdWZT27E672SF19QEi+of0/YeOy15lDgRhKvr5614uRrEfA=="
DEST = ROOT / "Packages/SnowfolioCore/Sources/MathCore/Resources"


def main():
    archive = urllib.request.urlopen(URL, timeout=30).read()
    if base64.b64encode(hashlib.sha512(archive).digest()).decode() != INTEGRITY:
        raise ValueError("KaTeX archive checksum mismatch")
    DEST.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        def read(name):
            entry = tar.getmember("package/" + name)
            if not entry.isfile():
                raise ValueError("Unexpected KaTeX archive entry")
            return tar.extractfile(entry).read()
        (DEST / "KaTeX.js").write_bytes(read("dist/katex.min.js"))
        (DEST / "KaTeX-LICENSE.txt").write_bytes(read("LICENSE"))
        (ROOT / "App/Resources/Licenses/KaTeX.txt").write_bytes(read("LICENSE"))
        css = read("dist/katex.min.css").decode()
        fonts = {}
        def embed(match):
            name = match.group(1)
            data = read("dist/fonts/" + name)
            fonts[name] = hashlib.sha256(data).hexdigest()
            return 'src:url(data:font/woff2;base64,' + base64.b64encode(data).decode() + ') format("woff2")'
        css, count = re.subn(r'src:url\(fonts/([^()]+\.woff2)\) format\("woff2"\)(?:,url\([^)]*\) format\("[^"\n]+"\))*', embed, css)
        if count != 20 or "url(fonts/" in css or "https:" in css or "http:" in css:
            raise ValueError("Unexpected KaTeX font declarations")
        (DEST / "KaTeX.css").write_text(css.rstrip("\n") + "\n")
    provenance = {"version": VERSION, "source": URL,
        "gitCommit": "8000fbd4e29cca2c0cb1e88b745af3ed2f436b66",
        "archiveIntegrity": "sha512-" + INTEGRITY,
        "changes": ["Embed original WOFF2 fonts in CSS; omit WOFF/TTF fallbacks for modern WebKit"],
        "fonts": fonts,
        "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(DEST.iterdir()) if p.name != "KaTeX-Provenance.json"}}
    (DEST / "KaTeX-Provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"KaTeX {VERSION}: {count} embedded fonts; no runtime downloads")


if __name__ == "__main__":
    main()
