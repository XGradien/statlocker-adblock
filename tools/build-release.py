#!/usr/bin/env python3
"""Build the user-facing release zip into dist/.

    python tools/build-release.py --version 1.2.0

Only the files a user needs go into the zip: the three .bat entry points, the
engine, the blocklist, the README, and the images it references. The repo's
development files (tests, tools, workflows, this script) are not shipped.

The zip is written to dist/ and gitignored, so it is a local build product
rather than something committed by accident. Run it from the repo root.
"""
import argparse
import hashlib
import subprocess
import zipfile
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

SHIPPED_FILES = [
    "Install AdBlock.bat",
    "Remove AdBlock.bat",
    "Check AdBlock Status.bat",
    "adblock.ps1",
    "domains.txt",
    "README.md",
    "assets/install-steps.svg",
    "assets/how-it-works.svg",
    "assets/before-after.png",
]

# cmd.exe parses these, so they must be CRLF in the zip. The working copy is
# CRLF on Windows and LF on Linux, so normalise explicitly rather than hoping.
CRLF_FILES = {"Install AdBlock.bat", "Remove AdBlock.bat", "Check AdBlock Status.bat", "adblock.ps1"}


def commit_timestamp(repo):
    """The HEAD commit's time, as a zip-friendly tuple.

    Pinning the entry timestamps is what makes a build reproducible: two runs
    from the same commit produce byte-identical zips instead of differing only
    in the moment they happened to be built. Zip cannot store pre-1980 dates.
    """
    try:
        raw = subprocess.run(
            ["git", "-C", str(repo), "log", "-1", "--format=%cI"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return datetime.fromisoformat(raw).timetuple()[:6]
    except Exception:
        return (1980, 1, 1, 0, 0, 0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="version to put in the file name")
    parser.add_argument("--out-dir", default=None,
                        help="where to write the zip (default: dist/ under the repo)")
    args = parser.parse_args()

    dist = Path(args.out_dir) if args.out_dir else REPO / "dist"
    dist.mkdir(parents=True, exist_ok=True)
    out = dist / f"statlocker-adblock-v{args.version}.zip"

    missing = [f for f in SHIPPED_FILES if not (REPO / f).is_file()]
    if missing:
        print("missing files: " + ", ".join(missing))
        return 2

    stamp = commit_timestamp(REPO)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for rel in SHIPPED_FILES:
            data = (REPO / rel).read_bytes()
            if rel in CRLF_FILES:
                data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
            info = zipfile.ZipInfo(f"statlocker-adblock/{rel}", date_time=stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)

    digest = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"wrote {out}")
    print(f"  {out.stat().st_size} bytes")
    print(f"  sha256 {digest}")
    print(f"  entries dated {stamp[0]}-{stamp[1]:02d}-{stamp[2]:02d} (HEAD commit time)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
