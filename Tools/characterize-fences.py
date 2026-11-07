#!/usr/bin/env python3
"""Capture original Hoedown fence choices; development-only, never part of app builds."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

CASES = [
    '```text\n**inside**\n```',
    '~~~text\n**inside**\n~~~',
    'before\n```text\nbody\n```\nafter',
    '> ```text\n> **quoted**\n> ```',
    '1. ```text\n    **listed**\n    ```',
    '    indented **code**\n',
    'Before ```inline``` after',
    '````text\n```nested```\n````',
    '~~~text\n<em>literal</em> & value\n~~~',
    '```text\r\n中文 👩‍💻\r\n```\r\n',
]


# Existing CommonMark behavior differs from Hoedown in these enabled-fence cases.
# Keep both exact outputs; never omit the cases to make the comparison pass.
NATIVE_DIFFERENCES = {
    ('before\n```text\nbody\n```\nafter', True): (
        '<p>before</p>\n<pre><code class="language-text">body\n</code></pre>\n<p>after</p>\n',
        'CommonMark fences may interrupt paragraphs without a blank line.'),
    ('1. ```text\n    **listed**\n    ```', True): (
        '<ol>\n<li>\n<pre><code class="language-text"> **listed**\n</code></pre>\n</li>\n</ol>\n',
        'CommonMark recognizes a fence immediately after a list marker and preserves excess indentation.'),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--hoedown', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    version = subprocess.check_output([str(args.hoedown), '--version'], text=True).strip()
    if '3.0.7' not in version:
        raise SystemExit('Characterization requires original Hoedown 3.0.7')
    cases = []
    for source in CASES:
        for enabled in (False, True):
            command = [str(args.hoedown), '--fenced-code' if enabled else '--no-fenced-code']
            html = subprocess.run(command, input=source, text=True, capture_output=True, check=True).stdout
            case = {'source': source, 'enabled': enabled, 'html': html}
            if (source, enabled) in NATIVE_DIFFERENCES:
                expected, note = NATIVE_DIFFERENCES[(source, enabled)]
                case.update(nativeHTML=expected, nativeBehaviorNote=note)
            cases.append(case)
    args.output.write_text(json.dumps({'engine': version,
        'source': 'https://github.com/hoedown/hoedown/tree/3.0.7',
        'fixtureSourceSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'comparisonNote': 'CommonMark normalizes inline-code line endings/spaces; legacy raw code text is retained here.',
        'cases': cases}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
