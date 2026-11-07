#!/usr/bin/env python3
"""Record original Hoedown underline choices; development-only compatibility evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

CASES = [
    '_under_', '_under *em* **strong**_', '**_under_**', '__strong__',
    '___both___', '____four____', '_____five_____', '___a _under_ b___',
    'word_under_score', 'a_b_c', 'a_b_', '_a_b', 'file_name_with_underlines',
    r'\_literal_ and _under_', r'\\_under_', '_ leading_', '_trailing _',
    '_trailing\t_', '_one\ntwo_', '_one\r\ntwo_', '_中文 👩‍💻_',
    '_a__b_', '_a___b_', '_before `code_ text` after_',
    '_before ``code_ text`` after_', '_unclosed `code_ after',
    '_before [label_](https://example.com) after_',
    '_before [label_][ref] after_\n\n[ref]: https://example.com',
    '[a _label_](https://example.com)', '![a _alt_](image.png)',
    '[reference _label_][ref]\n\n[ref]: https://example.com',
    '[url](https://example.com/_path_ "_title_")',
    '<span title="_attribute_">_body_</span>',
    '_before <span title="_">body</span> after_',
    '`_code_` and _under_', '```text\n_under_\n```', '    _indented_\n',
    '> _quoted_', '- _listed_', '_unclosed', '__', '_ _',
]

# Exact native differences, when present, are documented here after comparison.
NATIVE_DIFFERENCES = {('___both___', False): ('<p><em><strong>both</strong></em></p>\n', 'Disabled underline retains existing CommonMark delimiter-run nesting rather than Hoedown emphasis grouping.'), ('____four____', False): ('<p><strong><strong>four</strong></strong></p>\n', 'Disabled underline retains existing CommonMark delimiter-run nesting rather than Hoedown emphasis grouping.'), ('_____five_____', False): ('<p><em><strong><strong>five</strong></strong></em></p>\n', 'Disabled underline retains existing CommonMark delimiter-run nesting rather than Hoedown emphasis grouping.'), ('___a _under_ b___', False): ('<p><em><strong>a <em>under</em> b</strong></em></p>\n', 'Disabled underline retains existing CommonMark delimiter-run nesting rather than Hoedown emphasis grouping.'), ('_a__b_', False): ('<p><em>a__b</em></p>\n', 'Disabled underline retains existing CommonMark delimiter-run nesting rather than Hoedown emphasis grouping.'), ('_a___b_', False): ('<p><em>a___b</em></p>\n', 'Disabled underline retains existing CommonMark delimiter-run nesting rather than Hoedown emphasis grouping.'), ('word_under_score', False): ('<p>word_under_score</p>\n', 'Disabled underline retains CommonMark’s prohibition on intraword underscore emphasis. Enabled legacy underlines remain supported within words.'), ('a_b_c', False): ('<p>a_b_c</p>\n', 'Disabled underline retains CommonMark’s prohibition on intraword underscore emphasis. Enabled legacy underlines remain supported within words.'), ('a_b_', False): ('<p>a_b_</p>\n', 'Disabled underline retains CommonMark’s prohibition on intraword underscore emphasis. Enabled legacy underlines remain supported within words.'), ('_a_b', False): ('<p>_a_b</p>\n', 'Disabled underline retains CommonMark’s prohibition on intraword underscore emphasis. Enabled legacy underlines remain supported within words.'), ('file_name_with_underlines', False): ('<p>file_name_with_underlines</p>\n', 'Disabled underline retains CommonMark’s prohibition on intraword underscore emphasis. Enabled legacy underlines remain supported within words.'), ('_trailing\t_', False): ('<p>_trailing\t_</p>\n', 'Native parsing preserves the literal input tab; Hoedown expands it before inline parsing.'), ('_trailing\t_', True): ('<p>_trailing\t_</p>\n', 'Native parsing preserves the literal input tab; Hoedown expands it before inline parsing.'), ('![a _alt_](image.png)', False): ('<p><img src="image.png" alt="a alt" /></p>\n', 'Standard CommonMark image descriptions remove emphasis markers and use an XHTML void tag; Hoedown keeps raw alt markers.'), ('![a _alt_](image.png)', True): ('<p><img src="image.png" alt="a _alt_" /></p>\n', 'The optional dialect preserves literal image-description markers; native HTML emits the equivalent XHTML void tag.'), ('_before <span title="_">body</span> after_', False): ('<p><em>before <span title="_">body</span> after</em></p>\n', 'Disabled underline leaves raw HTML tags opaque to the maintained CommonMark delimiter grammar.')}


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
            command = [str(args.hoedown), '--fenced-code', '--underline' if enabled else '--no-underline']
            html = subprocess.run(command, input=source, text=True, capture_output=True, check=True).stdout
            case = {'source': source, 'enabled': enabled, 'html': html}
            if (source, enabled) in NATIVE_DIFFERENCES:
                expected, note = NATIVE_DIFFERENCES[(source, enabled)]
                case.update(nativeHTML=expected, nativeBehaviorNote=note)
            cases.append(case)
    args.output.write_text(json.dumps({'engine': version,
        'source': 'https://github.com/hoedown/hoedown/tree/3.0.7',
        'fixtureSourceSHA256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        'cases': cases}, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
