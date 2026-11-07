#!/usr/bin/env python3
"""Capture original word-formatting choices across all emphasis markers."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

CASES = [
    'So A*maz*ing', 'a*b*c', 'a**b**c', 'a***b***c',
    'a_b_c', 'a__b__c', 'a___b___c', 'file_name_with_underlines',
    'a*b_', '*a*b', 'a_b_', '_a_b', 'a**b**', '**a**b',
    '*word*', '__word__', '***word***', '___word___',
    '****word****', '____word____', '*****word*****', '_____word_____',
    'a~~b~~c', 'a~b~c', 'a==b==c', '~~word~~', '==word==',
    '~~~word~~~', '===word===', 'plain **bold** and *italic*',
    '(a*b*c)', '(*word*)', '!_word_', '.**word**', '>_word_',
    '中*文*中', '*中文*中', 'foo_бар_baz', '_café_ and 👩‍💻',
    '_outer *inner* outer_', '**outer _inner_ outer**',
    '==outer **bold** and _under_==', '~~outer **bold**~~',
    '_a _ b_', '_a_b_c_', '*a * b*', '**a * b**',
    r'\*escaped* and *word*', r'\_escaped_ and _word_',
    '`a*b*c` and _word_', '*before `code* text` after*',
    '_before ``code_ text`` after_', '==before `code==` after==',
    '[*label*](https://example.com)', '[a*b*c](https://example.com)',
    'a[__label__](https://example.com)c', '[*label*][ref]\n\n[ref]: https://example.com',
    '[*unmatched*', '![*alt* _text_](image.png)',
    '[url](https://example.com/a_b_c "a*b*c")',
    '<span title="a_b_c">a_b_c</span>',
    '> *quoted*', '- _listed_', 'one\r\n_a_b_c',
    '```text\na*b*c a_b_c\n```', '    a*b*c a_b_c\n',
    '*** leading***', '_trailing _', 'a*b*c and a_b_c and a==b==c and a~~b~~c',
]

# Block grammar, native link labels and equivalent void-tag output deliberately
# remain native. Every departure from original output is explicit and reviewed.
NATIVE_DIFFERENCES = {}
for underline in (False, True):
    for allow in (False, True):
        NATIVE_DIFFERENCES[('~~~word~~~', underline, allow)] = (
            '<pre><code class="language-word~~~"></code></pre>\n',
            'Native CommonMark recognizes this opening tilde fence before inline parsing; '
            'the intraword choice does not override block grammar.')
        NATIVE_DIFFERENCES[('![*alt* _text_](image.png)', underline, allow)] = (
            '<p><img src="image.png" alt="*alt* _text_" /></p>\n',
            'Native HTML emits the equivalent XHTML void image tag; the original literal '
            'image-description markers are preserved.')
    NATIVE_DIFFERENCES[('[*unmatched*', underline, False)] = (
        '<p>[<em>unmatched</em></p>\n',
        'Native link-label parsing preserves emphasis inside an unfinished bracketed label '
        'while retaining the unmatched bracket; Hoedown suppresses that span after the raw bracket byte.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--hoedown', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    version = subprocess.check_output([str(args.hoedown), '--version'], text=True).strip()
    if '3.0.7' not in version:
        raise SystemExit('Requires original Hoedown 3.0.7')
    cases = []
    for source in CASES:
        for underline in (False, True):
            for allow in (False, True):
                command = [str(args.hoedown), '--fenced-code', '--highlight', '--strikethrough',
                           '--underline' if underline else '--no-underline',
                           '--no-disable-intra-emphasis' if allow else '--disable-intra-emphasis']
                html = subprocess.run(command, input=source, text=True,
                                      capture_output=True, check=True).stdout
                case = {'source': source, 'underline': underline,
                        'policy': 'allowWithinWords' if allow else 'avoidWithinWords', 'html': html}
                if (source, underline, allow) in NATIVE_DIFFERENCES:
                    expected, note = NATIVE_DIFFERENCES[(source, underline, allow)]
                    case.update(nativeHTML=expected, nativeBehaviorNote=note)
                cases.append(case)
    args.output.write_text(json.dumps({
        'engine': version, 'source': 'https://github.com/hoedown/hoedown/tree/3.0.7',
        'fixtureSourceSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'cases': cases}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
