#!/usr/bin/env python3
"""Append newly detected domains to domains.txt (used by the watcher PR step).

Reads the list of new domains (one per line) from the file given as argv[1]
and appends the ones not already present to domains.txt, under a dated
comment. Exits 0 when nothing was added, 1 when the file changed.
"""
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DOMAINS = REPO / "domains.txt"


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: apply_new_domains.py <new-domains-file>", file=sys.stderr)
        return 2

    new = {
        l.strip().lower()
        for l in Path(sys.argv[1]).read_text().splitlines()
        if l.strip() and not l.strip().startswith("#")
    }
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
        return 0

    stamp = datetime.now(timezone.utc).date().isoformat()
    block = "\n# --- added by domain watcher on " + stamp + " ---\n"
    block += "\n".join(to_add) + "\n"
    if not text.endswith("\n"):
        text += "\n"
    DOMAINS.write_text(text + block, encoding="utf-8")
    print("appended " + str(len(to_add)) + " domain(s): " + ", ".join(to_add))
    return 1


if __name__ == "__main__":
    sys.exit(main())
