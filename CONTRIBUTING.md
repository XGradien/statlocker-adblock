# Contributing

## How the pieces fit

| File | Role |
|---|---|
| `adblock.ps1` | The engine. Writes/removes a marked section in the Windows hosts file. Idempotent, verified, backed up. |
| `Install AdBlock.bat` / `Remove AdBlock.bat` / `Check AdBlock Status.bat` | The user-facing entry points. Self-elevate via UAC. |
| `domains.txt` | The blocklist. One domain per line. |
| `domains.txt.sha256` | SHA-256 of the blocklist. The installer refuses a live list whose checksum does not match, so this must be updated in the same commit as `domains.txt`. `apply_new_domains.py` writes it for you. |
| `tools/refresh_domains.py` | The watcher. Fetches Statlocker's public ad-surface pages and their Playwire/RAMP config, reports domains that are neither blocked nor whitelisted. |
| `tools/apply_new_domains.py` | Appends watcher output to `domains.txt` and refreshes the checksum sidecar (used by the PR step). |
| `.github/workflows/refresh-domains.yml` | Runs the watcher every 12h and opens a PR when the ad stack changes. |
| `tests/test-engine.ps1` | Engine tests. Drives `adblock.ps1` against a throwaway hosts file: install, idempotency, checksum accept/reject, remove, status, DNS probe. |
| `tests/test_watcher.py` | Watcher tests. Skip list, primary-vs-secondary failure handling, checksum sidecar. |

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
5. **Update the checksum sidecar in the same commit.** `domains.txt.sha256` is
   what `Install AdBlock.bat` verifies the live list against; committing one
   without the other makes every online install fall back to the bundled list.
   `tools/apply_new_domains.py` writes it for you, so let the watcher do it.
   The hash is over the LF-normalised list, which is what GitHub serves, so it
   stays correct on a Windows checkout where the working copy has CRLF.
6. **The watcher validates lines before appending them.** Anything that is not
   a plain domain name is skipped with a warning rather than written to the
   list, because one bad line would make every install refuse it.

## Running the watcher locally

```
python tools/refresh_domains.py --verbose
```

Exit 0 = nothing new. Exit 1 = new domains on stdout. Exit 2 = a primary
source (a slot page or ramp.js) could not be fetched, so the run saw nothing
and failed on purpose. (On a PC with the block installed, the ad CDN itself is
unreachable - that's expected; the watcher still reads the slot pages, and
GitHub Actions runs unblocked.)

## Running the tests

```
powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-engine.ps1
python -m unittest discover -s tests -v
```

The engine tests never touch the real hosts file: `adblock.ps1` takes a
`-HostsPath` override and the tests point it at a throwaway copy. The live
list is exercised through `file://` URLs, so the suite runs offline.

Both suites also run in GitHub Actions on every push and pull request.

## The one design change that would break this

If Statlocker ever serves ad *creatives* from their own domain
(`*.statlocker.gg`) instead of third-party ad networks, hosts blocking can't
follow - blocking their domain would break the app itself. The watcher will
flag that as new activity; the fix would move to a script/element filter
(à la uBlock). Until then, the current design is the simplest thing that
works.
