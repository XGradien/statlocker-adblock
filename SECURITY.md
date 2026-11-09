# Security

## What this tool touches

One system file: `C:\Windows\System32\drivers\etc\hosts`. Nothing else.

There is no service, no background process, no scheduled task, no registry
entry, and no browser extension. The only network access is `install`
downloading the blocklist and its SHA-256 checksum from this repository over
HTTPS. Nothing is uploaded, and there is no analytics of any kind.

## Supply chain

The blocklist ships with a SHA-256 sidecar (`domains.txt.sha256`), and the
installer refuses to write a list whose checksum does not match. The release
zip is reproducible: entry timestamps are pinned to the commit time, so two
builds of the same commit are byte-identical and the SHA-256 published with a
release can be verified by anyone (`tools/build-release.py`).

## Reporting a vulnerability

Please do not open a public issue for a security problem - it would publish the
issue before it is fixed. Instead, open a **private vulnerability report** from
the Security tab of this repository, or contact the maintainer directly through
GitHub.

Include what you found, how to reproduce it, and what you think the impact is.
You can expect an acknowledgement within a few days.

## Scope

The following are known, deliberate properties of the design rather than
vulnerabilities:

- **The tool requires administrator rights.** Editing the hosts file is a
  protected system change, so Windows asks for permission every time. The tool
  cannot run without it.
- **The blocklist is only as trustworthy as this repository.** Anyone with
  write access to `domains.txt` controls what the tool blocks. The checksum
  protects against a mangled or intercepted download, not against a
  compromised repository.
- **The tool cannot survive a fundamental change in how Statlocker serves
  ads.** If ads ever come from `*.statlocker.gg` itself, blocking them would
  break the app. The watcher will raise that; it cannot fix it.
