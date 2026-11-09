#!/usr/bin/env python3
"""Verify the embedded updater; signed release creation must require configuration."""
import argparse
import base64
import hashlib
import json
import plistlib
from pathlib import Path
import subprocess
from urllib.parse import urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("app", type=Path)
parser.add_argument("--require-configured", action="store_true")
parser.add_argument("--require-arm64-only", action="store_true")
args = parser.parse_args()
repo = Path(__file__).resolve().parent.parent
info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
feed, key = info.get("SUFeedURL"), info.get("SUPublicEDKey")
configured = bool(feed and key)
if bool(feed) != bool(key):
    raise SystemExit("An update feed and Ed25519 public key must be supplied together.")
if args.require_configured and not configured:
    raise SystemExit("Release updates require Snowfolio's own feed and Ed25519 public key.")
if configured:
    url = urlsplit(feed)
    if url.scheme.lower() != "https" or not url.hostname or url.username is not None or url.password is not None or url.fragment:
        raise SystemExit("The published update feed must use HTTPS without credentials or a fragment.")
    try:
        valid_key = len(base64.b64decode(key, validate=True)) == 32
    except (ValueError, TypeError):
        valid_key = False
    if not valid_key:
        raise SystemExit("The update public key must be a complete Ed25519 public key.")
if info.get("SUVerifyUpdateBeforeExtraction") is not True:
    raise SystemExit("Update signatures must be checked before extraction.")
framework = args.app / "Contents/Frameworks/Sparkle.framework"
metadata = plistlib.loads((framework / "Resources/Info.plist").read_bytes())
provenance = json.loads((repo / "docs/validation/sparkle-provenance.json").read_text())
if metadata.get("CFBundleShortVersionString") != provenance["version"]:
    raise SystemExit("Embedded Sparkle does not match the pinned version.")
notice = args.app / "Contents/Resources/Sparkle.txt"
if hashlib.sha256(notice.read_bytes()).hexdigest() != provenance["licenseSHA256"]:
    raise SystemExit("Sparkle's complete distribution notice is missing or changed.")
architectures = {}
for path in sorted(framework.resolve().rglob("*")):
    if path.is_symlink() or not path.is_file():
        continue
    with path.open("rb") as source:
        magic = source.read(4)
    if magic not in [bytes.fromhex(x) for x in ["cffaedfe", "cefaedfe", "feedface", "feedfacf", "cafebabe", "bebafeca", "cafebabf", "bfbafeca"]]:
        continue
    result = subprocess.run(["xcrun", "lipo", "-archs", str(path)], check=True,
                            text=True, capture_output=True)
    slices = result.stdout.strip().split()
    if "arm64" not in slices or args.require_arm64_only and slices != ["arm64"]:
        raise SystemExit("A bundled updater executable has unsupported architecture slices.")
    architectures[str(path.relative_to(framework.resolve()))] = slices
if not architectures:
    raise SystemExit("No native Sparkle executables were found.")
print(json.dumps({"sparkle": provenance["version"], "configured": configured,
                  "verifyBeforeExtraction": True, "architectures": architectures}, indent=2))
