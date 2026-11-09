#!/usr/bin/env python3
"""Prepare a signed, unused app copy for arm64-only distribution without re-signing."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
args = parser.parse_args()
app = args.app.resolve()
if app.suffix != ".app" or app.stat().st_uid != os.getuid():
    raise SystemExit("Choose an app build owned by the current user.")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
processes = subprocess.run(["ps", "-axo", "command="], check=True,
                           capture_output=True, text=True).stdout.splitlines()
if any(line.startswith(str(executable)) for line in processes):
    raise SystemExit("Quit this app build before preparing it for distribution.")
framework = app / "Contents/Frameworks/Sparkle.framework"
if framework.is_symlink():
    raise SystemExit("The updater must be embedded as a copy, not linked to a package cache.")
open_files = subprocess.run(["lsof", "-t", "+D", str(framework)], capture_output=True, text=True)
if open_files.returncode != 1 or open_files.stdout.strip() or open_files.stderr.strip():
    raise SystemExit("The embedded updater is in use or its open files could not be checked.")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
magics = {bytes.fromhex(s) for s in ["cffaedfe", "cefaedfe", "feedface", "feedfacf",
                                    "cafebabe", "bebafeca", "cafebabf", "bfbafeca"]}
binaries = []
for path in sorted(framework.resolve().rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as source:
        magic = source.read(4)
    if magic not in magics:
        continue
    slices = subprocess.run(["xcrun", "lipo", "-archs", str(path)], check=True,
                            capture_output=True, text=True).stdout.split()
    if "arm64" not in slices:
        raise SystemExit("A bundled updater executable has no arm64 slice.")
    binaries.append((path, slices))
if not binaries:
    raise SystemExit("No updater executables were found.")
before = sum(path.stat().st_size for path, _ in binaries)
changed = []
for path, slices in binaries:
    if slices == ["arm64"]:
        continue
    temporary = path.with_name(path.name + ".arm64")
    if temporary.exists():
        raise SystemExit("A previous preparation file needs inspection before continuing.")
    try:
        subprocess.run(["xcrun", "lipo", "-thin", "arm64", str(path), "-output", str(temporary)],
                       check=True)
        shutil.copystat(path, temporary)
        os.replace(temporary, path)
        changed.append(str(path.relative_to(app)))
    finally:
        temporary.unlink(missing_ok=True)
# lipo preserves the selected slice's signature. Verify every nested helper and
# the outer app seal; never replace a failed signature with an ad-hoc workaround.
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(json.dumps({"architecture": "arm64", "executables": len(binaries), "thinned": changed,
                  "executableBytesBefore": before,
                  "executableBytesAfter": sum(path.stat().st_size for path, _ in binaries),
                  "deepStrictSignatureVerification": "pass", "resigned": False}, indent=2))
