# Changelog

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
