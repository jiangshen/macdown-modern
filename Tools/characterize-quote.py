#!/usr/bin/env python3
"""Capture the original optional quoted-text dialect; development-only evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

CASES = [
    '"quote"', '" before **bold** after "', '"unclosed', '""', '"   "',
    '""two""', '"""three"""', '""first"second""', 'before"word"after',
    '"one\ntwo"', '"one\r\ntwo"', '"中文 👩‍💻"', '"\ttabs\t"',
    r'\"escaped"', r'"escaped\" inside"', r'\\"quote"',
    '`"code"` and "quote"', '"before `code" text` after"',
    '"before ``code" text`` after"', '"unclosed `code" after',
    '["label"](https://example.com)', '!["alt"](image.png)',
    '"[inner](https://example.com)"',
    '"a [reference][ref]"\n\n[ref]: https://example.com',
    '"before [label"](https://example.com) after"',
    '[url](https://example.com/"path" "title")',
    '<span title="attribute">"body"</span>',
    '"before <span title="attribute">body</span> after"',
    '"_under_"', '"==highlight=="', '"x^(2 + 1)"',
    '"outer "inner" rest"', '"before \n\nafter"',
    '> "quoted"', '- "listed"', '# "Title"',
    '```text\n"fenced"\n```', '    "indented"\n',
    '"<script>alert(1)</script>"', '"[bad](javascript:alert(1))"',
]

# Kept explicit after comparison; no fixture is skipped.
NATIVE_DIFFERENCES = {('"\ttabs\t"', False): ('<p>&quot;\ttabs\t&quot;</p>\n',
                         'Disabled quoted text preserves literal source tabs; Hoedown expands tabs '
                         'before inline parsing.'),
 ('!["alt"](image.png)', False): ('<p><img src="image.png" alt="&quot;alt&quot;" /></p>\n',
                                  'Native HTML uses the equivalent XHTML void image tag; quote '
                                  'markers remain literal image-description text.'),
 ('!["alt"](image.png)', True): ('<p><img src="image.png" alt="&quot;alt&quot;" /></p>\n',
                                 'Native HTML uses the equivalent XHTML void image tag; quote '
                                 'markers remain literal image-description text.'),
 ('"before \n\nafter"', False): ('<p>&quot;before</p>\n<p>after&quot;</p>\n',
                                 'Native CommonMark block parsing trims trailing paragraph spaces; '
                                 'quote delimiters never cross a blank paragraph.'),
 ('"before \n\nafter"', True): ('<p>&quot;before</p>\n<p>after&quot;</p>\n',
                                'Native CommonMark block parsing trims trailing paragraph spaces; '
                                'quote delimiters never cross a blank paragraph.'),
 ('# "Title"', False): ('<h1 id="title"><span id="toc_0" class="md-legacy-anchor" '
                        'aria-hidden="true"></span>\n'
                        '&quot;Title&quot;\n'
                        '</h1>\n',
                        'Snowfolio retains its existing heading IDs and compatibility anchors '
                        'around the same quotation content.'),
 ('# "Title"', True): ('<h1 id="title"><span id="toc_0" class="md-legacy-anchor" '
                       'aria-hidden="true"></span>\n'
                       '<q>Title</q>\n'
                       '</h1>\n',
                       'Snowfolio retains its existing heading IDs and compatibility anchors '
                       'around the same quotation content.'),
 ('"<script>alert(1)</script>"', False): ('<p>&quot;&lt;script>alert(1)&lt;/script>&quot;</p>\n',
                                          'The maintained tag filter escapes active script tags '
                                          'even when raw HTML is enabled; quoted text cannot '
                                          'bypass that policy.'),
 ('"<script>alert(1)</script>"', True): ('<p><q>&lt;script>alert(1)&lt;/script></q></p>\n',
                                         'The maintained tag filter escapes active script tags '
                                         'even when raw HTML is enabled; quoted text cannot bypass '
                                         'that policy.')}


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
        for enabled in (False, True):
            command = [str(args.hoedown), '--fenced-code',
                       '--quote' if enabled else '--no-quote']
            html = subprocess.run(command, input=source, text=True,
                                  capture_output=True, check=True).stdout
            case = {'source': source, 'enabled': enabled, 'html': html}
            if (source, enabled) in NATIVE_DIFFERENCES:
                expected, note = NATIVE_DIFFERENCES[(source, enabled)]
                case.update(nativeHTML=expected, nativeBehaviorNote=note)
            cases.append(case)
    args.output.write_text(json.dumps({
        'engine': version, 'source': 'https://github.com/hoedown/hoedown/tree/3.0.7',
        'fixtureSourceSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'cases': cases}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
