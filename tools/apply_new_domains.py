#!/usr/bin/env python3
"""Append newly detected domains to domains.txt (used by the watcher PR step).

Reads the list of new domains (one per line) from the file given as argv[1]
and appends the ones not already present to domains.txt, under a dated
comment. Exits 0 when nothing was added, 1 when the file changed, 2 when
something went wrong (bad arguments, unreadable input, failed write).

Every run leaves domains.txt.sha256 matching domains.txt, because
adblock.ps1 refuses a live list whose checksum does not match.
"""
import hashlib
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOMAINS = REPO / "domains.txt"

# Mirrors the validation in adblock.ps1: a line that is not a plain domain name
# would end up in domains.txt and make every install refuse the list.
DOMAIN_RE = re.compile(r"^[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)+$")


def sha256_of(path: Path) -> str:
    """Hash the LF-normalised bytes.

    domains.txt is stored LF in the repository and served that way by GitHub
    raw. A Windows checkout has CRLF in the working copy, so hashing the raw
    bytes would produce a sidecar that no online install would ever accept.
    """
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def write_hash_sidecar(domains_path: Path) -> None:
    """Write <name>.sha256 next to the list.

    adblock.ps1 verifies this checksum before it trusts the live list, so a
    watcher PR has to ship domains.txt and its sidecar together.
    """
    sidecar = domains_path.with_name(domains_path.name + ".sha256")
    sidecar.write_text(
        sha256_of(domains_path) + "  " + domains_path.name + "\n", encoding="utf-8"
    )


def ensure_hash_sidecar(domains_path: Path) -> int:
    """Repair a missing or stale sidecar. Returns 1 when it changed."""
    sidecar = domains_path.with_name(domains_path.name + ".sha256")
    expected = sha256_of(domains_path)
    if sidecar.exists() and sidecar.read_text(encoding="utf-8").startswith(expected):
        return 0
    write_hash_sidecar(domains_path)
    print("updated " + str(sidecar))
    return 1


def main(argv=None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) < 1:
        print("usage: apply_new_domains.py <new-domains-file>", file=sys.stderr)
        return 2
    try:
        return _run(Path(args[0]))
    except OSError as e:
        # Exit 2, not Python's default 1: the workflow treats 1 as "domains
        # were appended", so an I/O failure must not look like a success.
        print("error: " + str(e), file=sys.stderr)
        return 2


def _run(source: Path) -> int:
    new = set()
    malformed = []
    for line in source.read_text().splitlines():
        entry = line.strip().lower()
        if not entry or entry.startswith("#"):
            continue
        if not DOMAIN_RE.match(entry):
            malformed.append(entry)
            continue
        new.add(entry)
    if malformed:
        print("skipped malformed line(s): " + ", ".join(malformed), file=sys.stderr)
    if not new:
        return 0

    text = DOMAINS.read_text(encoding="utf-8")
    existing = {
        l.strip().lower()
        for l in text.splitlines()
        if l.strip() and not l.strip().startswith("#")
    }
    to_add = sorted(new - existing)
    if not to_add:
        print("all detected domains already present")
        return ensure_hash_sidecar(DOMAINS)

    stamp = datetime.now(timezone.utc).date().isoformat()
    block = "\n# --- added by domain watcher on " + stamp + " ---\n"
    block += "\n".join(to_add) + "\n"
    if not text.endswith("\n"):
        text += "\n"
    DOMAINS.write_text(text + block, encoding="utf-8")
    write_hash_sidecar(DOMAINS)
    print("appended " + str(len(to_add)) + " domain(s): " + ", ".join(to_add))
    return 1


if __name__ == "__main__":
    sys.exit(main())
