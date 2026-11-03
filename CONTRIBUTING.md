# Contributing

## How the pieces fit

| File | Role |
|---|---|
| `adblock.ps1` | The engine. Writes/removes a marked section in the Windows hosts file. Idempotent, verified, backed up. |
| `Install AdBlock.bat` / `Remove AdBlock.bat` / `Check AdBlock Status.bat` | The user-facing entry points. Self-elevate via UAC. |
| `domains.txt` | The blocklist. One domain per line. |
| `tools/refresh_domains.py` | The watcher. Fetches Statlocker's public ad-surface pages and their Playwire/RAMP config, reports domains that are neither blocked nor whitelisted. |
| `tools/apply_new_domains.py` | Appends watcher output to `domains.txt` (used by the PR step). |
| `.github/workflows/refresh-domains.yml` | Runs the watcher every 12h and opens a PR when the ad stack changes. |

## Rules for touching `domains.txt`

1. **Never block the whitelist** (app, data, Steam/Valve, video playback,
   CDNs, cert/OCSP endpoints) - it lives in
   `tools/refresh_domains.py` and is the safety contract of this project.
   If the app starts needing a new legitimate domain, add it to the
   whitelist *first*.
2. Prefer **apex domains** (e.g. `doubleclick.net`) over subdomains -
   Windows DNS parent-chain lookup covers all subdomains.
3. If you only need to block one subdomain of an apex the app legitimately
   uses (e.g. `prd.jwpltx.com` under JW Player), block the subdomain and
   comment why.
4. Every added domain should have a source: observed in the app's live
   traffic/cache, or referenced by the ad-surface pages / ramp config.
   Say so in the commit message.

## Running the watcher locally

```
python tools/refresh_domains.py --verbose
```

Exit 0 = nothing new. Exit 1 = new domains on stdout. (On a PC with the
block installed, the ad CDN itself is unreachable - that's expected; the
watcher still reads the slot pages, and GitHub Actions runs unblocked.)

## The one design change that would break this

If Statlocker ever serves ad *creatives* from their own domain
(`*.statlocker.gg`) instead of third-party ad networks, hosts blocking can't
follow - blocking their domain would break the app itself. The watcher will
flag that as new activity; the fix would move to a script/element filter
(à la uBlock). Until then, the current design is the simplest thing that
works.
