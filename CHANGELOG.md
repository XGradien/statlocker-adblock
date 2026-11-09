# Changelog

## 1.2.0 (2026-11-09)

- README gains a before/after picture of the companion app: the two ad slots
  (the tall one down the right edge, the wide one at the bottom-left) show as
  flat gray placeholder boxes without the block, and are gone with it on.
- `assets/before-after.png` is part of the release zip, so the README's new
  image resolves from a downloaded copy and not only from the repo.

## 1.1.4 (2026-11-09)

- `Check AdBlock Status.bat` reports whether the backup file actually exists
  instead of always printing its path.
- The DNS probe warning no longer assumes another app overwrote the hosts
  file; a broken DNS connection produces the same symptom.
- The `.bat` windows no longer promise the hosts file goes back "exactly" how
  it was (it leaves a blank line or two), and both failure messages now
  mention that antivirus software can block hosts-file edits.
- `tools/build-release.py` builds the release zip into a gitignored `dist/`.
  Builds are reproducible: entry timestamps come from the HEAD commit, so the
  SHA-256 published with a release can be reproduced by anyone. Covered by
  new tests.
- Added `SECURITY.md`, describing what the tool touches, its supply chain, and
  how to report a problem privately.

## 1.1.3 (2026-11-09)

- `Remove AdBlock.bat` now clears a backup file left behind by an older
  version, even when the block itself is already gone. Before, someone who
  uninstalled with v1.0.0 or v1.1.0 had `hosts.bak-statlocker-adblock` sitting
  in their Windows folder with no way to clear it from the tool.

## 1.1.2 (2026-11-09)

- `install` and `remove` flush the Windows DNS cache. Windows caches name
  lookups, so an ad address the app resolved earlier could keep working until
  its cache entry expired, which looks exactly like the tool failing. The
  change is now active as soon as the app restarts.

## 1.1.1 (2026-11-09)

- `Remove AdBlock.bat` deletes the backup it made, so a clean uninstall leaves
  nothing behind at all. The installer already said the backup was temporary;
  now it actually is.
- `Install AdBlock.bat` always cleans up the downloaded list, even if
  something goes wrong halfway through.
- The watcher notices when Statlocker's ad pages change shape so it can no
  longer find the ad config. That used to look exactly like a clean run. It now
  opens an issue instead, and closes that issue by itself once it can read the
  pages again.
- README: keep-the-folder guidance, and an answer for "I deleted the folder,
  how do I remove the block?"
- Tests: 28 engine checks (backup cleanup, temp file cleanup) and 16 watcher
  checks (structure-change detection).

## 1.1.0 (2026-11-09)

- Blocklist extended 92 → 119 domains: the domain watcher's first PR added
  27 verified ad-tech domains (3Lift, 33Across, Rubicon Project, smaato,
  TrustedStack, SmileWanted, GumGum, Connatix, RichAudience, Criteo/PostRelease,
  OmniTag, uidapi, EUID, Microsoft SAS CDN and others).
- `domains.txt` now ships with a SHA-256 sidecar, and the installer refuses a
  live list whose checksum does not match. A truncated download or a tampered
  list can no longer reach your hosts file. The checksum is computed over the
  LF-normalised list, so it is the same on a Windows checkout and in CI.
- The watcher validates every line before appending it to `domains.txt`, so a
  malformed entry can no longer end up in the list and make every install fail.
- `Check AdBlock Status.bat` now resolves a blocked domain and confirms it
  lands on 127.0.0.1. A hosts file overwritten by a VPN or antivirus shows up
  instead of looking healthy.
- The watcher stopped fetching a Playwire URL that has 404'd since 2026-11-09,
  and it now fails the run when a primary source (a slot page or ramp.js) is
  unreachable instead of reporting a clean run it could not actually do.
- Watcher run artifacts (`watch.log`, `new-domains.txt`) are written to the
  runner temp directory and gitignored. One of them had been committed to the
  repo by the PR step.
- Tests: `tests/test-engine.ps1` (24 checks against a throwaway hosts file)
  and `tests/test_watcher.py` (15 checks over the watcher), run on every push
  and pull request.
- `.gitattributes` pins CRLF for `.bat` and `.ps1`, so a fresh clone on Windows
  checks out files cmd.exe can parse.
- Watcher fixes from the first days of the project: a here-doc terminator
  syntax error that failed every run, apply-step exit-code handling, skipping
  unexpanded JS template URLs, fetch dedupe, GITHUB_TOKEN write permissions,
  the repo's "Allow GitHub Actions to create and approve pull requests"
  setting, and a whitelist for docs/telemetry domains found in ad-config
  content.

## 1.0.0 (2026-11-03)

- First public release.
- One-double-click install (`Install AdBlock.bat`) and removal
  (`Remove AdBlock.bat`), plus `Check AdBlock Status.bat`.
- Blocks the 92 verified third-party ad domains of the Statlocker companion
  app (Playwire/RAMP + Intergient, Google ad infrastructure, Amazon ad
  infrastructure, ad exchanges, identity syncs, ad CDNs). The app itself,
  its stats, and its data endpoints are untouched.
- Install automatically fetches the latest domain list from this repo when
  online, so the blocklist stays current without doing anything.
- `domain-watcher` GitHub Action monitors Statlocker's public ad-surface
  pages and their Playwire config every 12 hours and opens a pull request
  with any newly detected ad domains.
- Hosts-file edits are idempotent, verified after writing, and always backed
  up to `hosts.bak-statlocker-adblock`.
