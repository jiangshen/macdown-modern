#!/usr/bin/env python3
"""Capture original Hoedown 3.0.7 inline dialect output; never used by app builds."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

CASES = [
    ("highlight", "a ==bright== b"),
    ("highlight", "==*emphasis* **strong** [link](https://example.com)=="),
    ("highlight", "== space== ==space == ===triple==="),
    ("highlight", "a==b==c"),
    ("highlight", "====x===="),
    ("highlight", "==a===b=="),
    ("highlight", "==a====b=="),
    ("highlight", "==a ==b== c=="),
    ("highlight", "==one\ntwo=="),
    ("highlight", "==`==code==` remains code=="),
    ("highlight", r"\==escaped== and ==literal &amp; text=="),
    ("highlight", "unmatched ==source"),
    ("superscript", "x^2 x^(a + b) x^word."),
    ("superscript", "x^(**bold** and `code`) after"),
    ("superscript", "x^a^b"),
    ("superscript", "x^(one\ntwo) after"),
    ("superscript", r"x^a\ b x^(a\)b)"),
    ("superscript", "x^中文 😀^2"),
    ("superscript", "x^<em>hi</em>"),
    ("superscript", "x^ " ),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hoedown", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    version = subprocess.check_output([str(args.hoedown), "--version"], text=True).strip()
    if "3.0.7" not in version:
        raise SystemExit("Characterization requires original Hoedown 3.0.7")
    cases = []
    for option, source in CASES:
        result = subprocess.run([str(args.hoedown), "--" + option], input=source,
            text=True, capture_output=True, check=True).stdout.strip()
        cases.append({"option": option, "source": source, "html": result})
    data = {"engine": version,
        "source": "https://github.com/hoedown/hoedown/tree/3.0.7",
        "fixtureSourceSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "cases": cases}
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
