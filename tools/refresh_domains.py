#!/usr/bin/env python3
"""Domain watcher for statlocker-adblock.

The Statlocker companion app loads its ads from public "ad surface" pages on
dtapp.statlocker.gg (one page per ad slot, opened in a child webview). Those
pages reference the ad stack: the Playwire/RAMP loader and the scripts it
pulls in.

This script fetches those pages (plus one level of referenced scripts),
extracts every domain they mention, and reports any domain that is neither
in domains.txt (the current blocklist) nor in the whitelist (domains the
app legitimately uses, plus non-ad code artifacts).

Usage:
    python refresh_domains.py            # new domains printed to stdout, one
                                         # per line; exit 0 = nothing new,
                                         # exit 1 = new domains found,
                                         # exit 2 = a primary source failed
    python refresh_domains.py --verbose  # also dump all observed hosts to stderr

Designed to run unattended in GitHub Actions (no dependencies beyond the
standard library).
"""
import re
import sys
import urllib.request

# The app's public ad-surface pages (Tauri ad surface, one per slot).
SLOT_URLS = [
    "https://dtapp.statlocker.gg/?slot=sky",
    "https://dtapp.statlocker.gg/?slot=med_rect",
]

# URLs that are permanently gone. Fetching them again only adds a 404 to every
# run and trains everyone to ignore the log.
SKIP_URLS = {
    # Playwire's pre-content bootstrap. 404 on every run since at least
    # 2026-11-09; the bidder list it used to carry now arrives via ramp.js.
    "https://config.playwire.com/1025810/v2/pre_content.js",
}

# Domains that must NEVER be blocked: the app, its data, Steam/Valve sign-in,
# video playback, generic CDNs, and code-artifact strings that are not live
# traffic. Verified against the app's full observed host set. If Statlocker
# ever needs a new one, add it here BEFORE touching domains.txt.
WHITELIST_APEXES = [
    "statlocker.gg",           # app itself: api, dtapp, updates, auth
    "deadlock-api.com",        # match data + hero assets
    "valve.net",               # replay metadata (replay.valve.net)
    "steamstatic.com", "steamcdn-a.akamaihd.net", "steamcommunity.com",
    "steamlogin.com", "steampowered.com", "steamgriddb.com",
    "googleapis.com", "gstatic.com", "google.com", "googletagmanager.com",
    "youtube.com", "ytimg.com",
    "jsdelivr.net", "jsdelivr.com", "unpkg.com", "cloudflare.com", "withgoogle.com",
    # JW Player: the app may use it to PLAY highlight videos; only its
    # ad-tech subdomain (prd.jwpltx.com) is blocked, not the player.
    "jwplayer.com", "jwplatform.com", "jwpcdn.com",
    # cert revocation / OCSP endpoints (blocking these breaks TLS!)
    "digicert.com", "globalsign.com", "godaddy.com", "geotrust.com",
    "sectigo.com", "lencr.org", "amazontrust.com", "symantec.com", "usertrust.com",
    "baltimorecertificates.com", "certum.com", "comodoca.com", "entrust.net",
    # strings inside code, not real traffic
    "example.com", "w3.org", "adobe.com", "schema.org", "tizen.org",
    "react.dev", "github.com", "githubusercontent.com", "github.io",
    "pinterest.com", "tumblr.com", "twitter.com", "x.com", "linkedin.com",
    "facebook.com", "reddit.com", "microsoft.com", "apple.com", "mozilla.org",
    # --- non-ad domains observed in ad-page/JS content: docs, example links
    #     from old library comments, telemetry, management endpoints.
    #     Strings in config files, not live ad traffic.
    "apache.org", "whatwg.org",
    "jquery.com", "videojs.com", "prebid.org",
    "js.org",                    # dev project docs (redux.js.org, etc.)
    "datadoghq.com", "datadoghq.eu",  # telemetry - never block
    "padolsey.com", "marphezis.com", "aptana.com", "cssplay.co.uk",
    "patternify.com", "pelagodesign.com", "ozpr.net",
    "qsearch-a.akamaihd.net",    # legacy Bing string; akamaihd.net too broad
    "appnexus.com",              # runtime is adnxs.com (blocked); console/stash
                                 # subdomains are management endpoints
    # GCP/CDN apexes we only block at specific subdomain level
    "cloudfront.net", "run.app", "a2z.com", "yahoo.com", "amazon.dev",
    "amazon.com", "amazonaws.com", "googleusercontent.com",
]

HOST_RE = re.compile(
    r"(?:https?:)?//([a-z0-9][a-z0-9\-]{1,60}\.(?:[a-z0-9\-]{1,60}\.){1,6}[a-z]{2,12})"
)

UA = "Mozilla/5.0 (statlocker-adblock domain watcher)"
MAX_EXTRA_FETCHES = 10
MAX_FETCH_BYTES = 1 << 20  # 1 MiB per file


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read(MAX_FETCH_BYTES)


def under(h, apex):
    return h == apex or h.endswith("." + apex)


def main():
    verbose = "--verbose" in sys.argv
    with open("domains.txt", encoding="utf-8") as f:
        blocked = {l.strip().lower() for l in f if l.strip() and not l.strip().startswith("#")}

    found = set()
    to_fetch = [u for u in SLOT_URLS if u not in SKIP_URLS]
    enqueued = set(to_fetch)  # dedupe: both slot pages reconstruct the same ramp.js URL
    # Sources we cannot do without. If one of these fails, the watcher saw
    # nothing and must say so loudly instead of reporting a clean run.
    primary = set(to_fetch)
    extra_fetches = 0
    failed_fetches = 0

    while to_fetch:
        url = to_fetch.pop(0)
        try:
            data = fetch(url)
        except Exception as e:
            if url in primary:
                print(f"ERROR: primary source unreachable: {url}: {e}", file=sys.stderr)
                return 2
            print(f"WARN: failed to fetch {url}: {e}", file=sys.stderr)
            failed_fetches += 1
            continue
        text = data.decode("utf-8", "ignore")
        for m in HOST_RE.finditer(text):
            found.add(m.group(1).lower().rstrip("."))
        # one level deeper: the ad-surface pages load their config script
        # (the Playwire/RAMP config carries the full bidder list). The URL is
        # built by concatenation in the page:
        #   rampScript.src = 'https://<host>/' + PUB_ID + '/' + WEBSITE_ID + '/ramp.js'
        # so reconstruct it from the host literal + the two id variables.
        host_m = re.search(r"src\s*=\s*'https://([a-z0-9.\-]+)/'", text)
        pub_m = re.search(r"PUB_ID\s*=\s*'(\d+)'", text)
        web_m = re.search(r"WEBSITE_ID\s*=\s*'(\d+)'", text)
        if host_m and pub_m and web_m and "ramp.js" in text:
            ramp_url = (
                f"https://{host_m.group(1)}/{pub_m.group(1)}/{web_m.group(1)}/ramp.js"
            )
            if ramp_url not in enqueued and ramp_url not in SKIP_URLS:
                to_fetch.append(ramp_url)
                enqueued.add(ramp_url)
                primary.add(ramp_url)
        # future-proofing: also follow any fully-spelled .js URLs
        candidates = set(re.findall(r'src="([^"]+\.js[^"]*)"', text, re.I))
        candidates.update(re.findall(r"https?://[a-z0-9.\-]+/[^\s'\"<>)]*?\.js", text, re.I))
        for s in sorted(candidates):
            # Skip unexpanded JS template URLs (e.g. /stack/${s}/ramptag.js):
            # they 403/404 when fetched literally, and their hosts are already
            # captured from the page text by HOST_RE.
            if "${" in s:
                continue
            if s in enqueued or s in SKIP_URLS:
                continue
            if s.startswith("http") and extra_fetches < MAX_EXTRA_FETCHES:
                to_fetch.append(s)
                enqueued.add(s)
                extra_fetches += 1

    unknown = sorted(
        h
        for h in found
        if not any(under(h, w) for w in WHITELIST_APEXES)
        and not any(under(h, b) for b in blocked)
    )

    if verbose:
        print(f"# observed hosts: {len(found)}", file=sys.stderr)
        for h in sorted(found):
            print(f"#   {h}", file=sys.stderr)
        print(
            "# covered by blocklist: "
            f"{sum(1 for h in found if any(under(h, b) for b in blocked))}",
            file=sys.stderr,
        )

    if failed_fetches:
        print(f"# fetch failures: {failed_fetches}", file=sys.stderr)

    if unknown:
        print("\n".join(unknown))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
