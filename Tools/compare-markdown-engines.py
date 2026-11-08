#!/usr/bin/env python3
"""Compare optional parser candidates and the complete current pipeline, without installing them.

Core-engine and complete application-processing scopes are reported separately.
Use one shared audit executable and alternate engines across fresh process samples.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import statistics
import subprocess

SPEC_SHA = 'd431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20'
NORMALIZER_SHA = '3d8935700caed4b3776860b3627b83160998082c08c539e76a6431fec5024810'


def fixture(workload, size):
    if workload == 'mixed':
        unit = ('## A notebook section\n\nLocal **Markdown** with _emphasis_, '
                '[a link](https://example.invalid), Unicode 中文 👩‍💻 and `inline code`.\n\n'
                '1. First item\n2. Second item\n\n> [!NOTE]\n> An offline callout with text.\n\n'
                '| Column | Value |\n| --- | --- |\n| One | Two |\n\n'
                '```swift\nlet title = "Snowfolio"\nprint(title)\n```\n\n')
    elif workload == 'long-line':
        unit = 'Unicode 中文 👩‍💻 **bold** and `code` in a long paragraph. '
    elif workload == 'autolinks':
        unit = 'Before &amp; user&#64;example.com, then https://example.org/中文 and tail.\n\n'
    elif workload == 'nul':
        unit = 'Before�\0 **中文 😀** and `code` with \0tail.\n\n'
    elif workload == 'escaped-cell':
        header = '| Header | Other |\n|---|---|\n|'
        trailer = ' **target** | value |\n'
        remaining = size - len((header + trailer).encode())
        return (header + 'a\\|' * (remaining // 3) + 'x' * (remaining % 3) + trailer).encode()
    else:
        unit = 'A calm paragraph of plain text for writing and reading, with Unicode 中文 👩‍💻.\n\n'
    count = size // len(unit.encode())
    data = unit.encode() * count
    return data + b'x' * (size - len(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, required=True)
    parser.add_argument('--md4c', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--phase', required=True)
    parser.add_argument('--engines', nargs='+', choices=['cmark', 'md4c', 'snowfolio'], default=['cmark', 'md4c', 'snowfolio'])
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--iterations', type=int, default=5)
    parser.add_argument('--spec', type=Path)
    parser.add_argument('--normalize-module', type=Path, help='Pinned CommonMark/cmark test/normalize.py; hash is verified before import')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MD4C_LIBRARY=str(args.md4c.resolve()))
    corpus = []
    normalize = None
    if args.normalize_module:
        if hashlib.sha256(args.normalize_module.read_bytes()).hexdigest() != NORMALIZER_SHA:
            raise SystemExit('Expected pinned CommonMark/cmark HTML normalizer')
        spec = importlib.util.spec_from_file_location('commonmark_html_normalize', args.normalize_module)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        normalize = module.normalize_html
    if args.spec:
        data = args.spec.read_bytes()
        if hashlib.sha256(data).hexdigest() != SPEC_SHA:
            raise SystemExit('Expected pinned official CommonMark 0.31.2 corpus')
        examples = json.loads(data)
        for engine in [e for e in args.engines if e != 'snowfolio']:
            failures = []
            for case in examples:
                actual = subprocess.run([str(args.audit), engine, 'commonmark', '--html'],
                                        input=case['markdown'], text=True, capture_output=True,
                                        check=True, timeout=10, env=env).stdout
                if actual != case['html']:
                    failures.append({'example': case['example'], 'section': case['section'],
                                     'source': case['markdown'], 'expected': case['html'], 'actual': actual})
            report = {'engine': engine, 'total': len(examples), 'exactHTMLMatches': len(examples) - len(failures),
                      'exactHTMLMismatches': len(failures), 'failures': failures,
                      'note': 'Exact spec HTML comparison; output-format differences require inspection before classifying grammar compliance.'}
            if normalize:
                semantic = [c for c in failures if normalize(c['expected']) != normalize(c['actual'])]
                report['normalizedHTMLMatches'] = len(examples) - len(semantic)
                report['normalizedHTMLDifferences'] = semantic
                report['normalizerSHA256'] = NORMALIZER_SHA
            (args.output / (engine + '-commonmark.json')).write_text(json.dumps(report, indent=2) + '\n')
            corpus.append({k: v for k, v in report.items() if k != 'failures'})
            print(f'{engine}: {report["exactHTMLMatches"]}/{len(examples)} exact CommonMark HTML matches', flush=True)
    cases = [(work, size) for work in ['prose', 'mixed'] for size in [100_000, 1_000_000, 10_000_000]]
    cases += [(work, 1_000_000) for work in ['long-line', 'autolinks', 'escaped-cell', 'nul']]
    records = []
    for workload, size in cases:
        file = args.output / 'current-fixture.md'
        data = fixture(workload, size)
        assert len(data) == size
        file.write_bytes(data)
        for sample in range(args.samples):
            engines = args.engines if sample % 2 == 0 else list(reversed(args.engines))
            for engine in engines:
                record = json.loads(subprocess.run(
                    [str(args.audit), engine, 'gfm', str(file), str(args.iterations)],
                    text=True, capture_output=True, check=True, timeout=90, env=env).stdout)
                record.update(workload=workload, sample=sample, fixtureSHA256=hashlib.sha256(data).hexdigest())
                records.append(record)
        file.unlink()
        print(f'{workload} {size}: collected {args.samples} fresh samples per engine', flush=True)
        (args.output / 'samples.json').write_text(json.dumps(records, indent=2) + '\n')
    summaries = []
    for workload, size in cases:
        for engine in args.engines:
            selected = [r for r in records if r['workload'] == workload and r['inputBytes'] == size and r['engine'] == engine]
            summaries.append({'workload': workload, 'bytes': size, 'engine': engine,
                              'medianWarmMS': statistics.median(r['warmMedianMilliseconds'] for r in selected),
                              'medianColdMS': statistics.median(r['coldMilliseconds'] for r in selected),
                              'maxProcessPeakResidentBytes': max(r['processPeakResidentBytes'] for r in selected),
                              'htmlSHA256': selected[0]['htmlSHA256'], 'parentIDsSHA256': selected[0]['parentIDsSHA256'],
                              'scope': selected[0]['scope']})
    report = {'phase': args.phase, 'samples': args.samples, 'warmIterationsPerProcess': args.iterations,
              'method': 'Release arm64, fresh processes, sequential alternating engine order; file I/O, fixture construction and output hashing excluded from elapsed render times. Peak RSS is whole-process, not a leak measurement. Core and full pipeline scopes are distinct.',
              'corpus': corpus, 'cases': summaries}
    (args.output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Saved compact engine comparison.', flush=True)


if __name__ == '__main__':
    main()
