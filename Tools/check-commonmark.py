#!/usr/bin/env python3
"""Audit native parser output against the official CommonMark 0.31.2 corpus.

Download the published spec.json separately; the app and ordinary builds never fetch it.
This command reports and fails on every mismatch, including existing upstream differences.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

URL = 'https://spec.commonmark.org/0.31.2/spec.json'
SHA256 = 'd431b29d97b6f73e69d547109cf5081578fac931e72afe95639ebe766c1b2a20'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--program', type=Path, required=True)
    parser.add_argument('--spec-file', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = args.spec_file.read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit('Expected official CommonMark 0.31.2 fixtures from ' + URL)
    cases = json.loads(data)
    failures = []
    for case in cases:
        result = subprocess.run([str(args.program), '--unsafe'], input=case['markdown'],
            text=True, capture_output=True, check=True, timeout=5)
        if result.stdout != case['html']:
            failures.append({'example': case['example'], 'section': case['section'],
                'markdown': case['markdown'], 'expected': case['html'], 'actual': result.stdout})
    report = {'spec': 'CommonMark 0.31.2', 'source': URL, 'sha256': SHA256,
        'scope': 'Core native parser CLI; raw HTML enabled for official spec; no app decorations or GFM options',
        'total': len(cases), 'passed': len(cases)-len(failures), 'failed': len(failures), 'failures': failures}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(f"CommonMark: {report['passed']}/{report['total']} passed; {report['failed']} mismatches")
    raise SystemExit(1 if failures else 0)


if __name__ == '__main__':
    main()
