#Requires -Version 5.1
<#
statlocker-adblock engine.

  install : writes (or refreshes) the ad-block section in the Windows hosts file
  remove  : removes the section, leaving everything else in hosts untouched
  status  : reports whether the block is active, and probes DNS to confirm a
            blocked domain really resolves to 127.0.0.1

The block lives in a clearly marked section inside the hosts file, so it is
trivially reversible and never mixes with the user's own entries. Every
install backs up the hosts file first (hosts.bak-statlocker-adblock).
The script is idempotent: running install any number of times produces the
same end state.

When online, install takes the live list from GitHub, but only after its
SHA-256 (domains.txt.sha256) checks out - a list that cannot be verified is
never written to the hosts file.

Hidden test overrides: -HostsPath and -DomainsFile point at different files,
-LiveDomainsUrl / -LiveHashUrl at different URLs, -ProbeDomain at a specific
host to resolve. Admin is only required when touching the real hosts file.
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('install', 'remove', 'status')]
    [string]$Action,

    # Hidden test overrides: point at different files. Default = the real
    # system paths. (Resolved in the body because $PSScriptRoot is not
    # available inside param() defaults in Windows PowerShell 5.1.)
    [string]$HostsPath = '',
    [string]$DomainsFile = '',

    # Best-effort live list; disable with -NoLiveUpdate (also used by tests)
    [switch]$NoLiveUpdate,
    [string]$LiveDomainsUrl = 'https://raw.githubusercontent.com/XGradien/statlocker-adblock/main/domains.txt',
    [string]$LiveHashUrl = '',

    # status: resolve one specific host instead of the first blocked domain
    [string]$ProbeDomain = ''
)

$ErrorActionPreference = 'Stop'

if (-not $HostsPath) { $HostsPath = Join-Path $env:windir 'System32\drivers\etc\hosts' }
if (-not $DomainsFile) { $DomainsFile = Join-Path $PSScriptRoot 'domains.txt' }

$MARKER_START = '# === statlocker-adblock (managed - remove this whole section to undo) ==='
$MARKER_END   = '# === end statlocker-adblock ==='

# Sections written by earlier personal builds of this tool; install cleans them up.
$LEGACY_PATTERNS = @(
    '(?m)^# === Statlocker ad block[^\r\n]*\r?\n.*(?m)^# === End Statlocker ad block[^\r\n]*\r?\n?'
)

function Get-Section([string]$HostsText) {
    $re = [regex]::new('(?ms)^' + [regex]::Escape($MARKER_START) + '.*^' + [regex]::Escape($MARKER_END) + '[ \t]*\r?\n?')
    $m = $re.Match($HostsText)
    if ($m.Success) { return $m.Value }
    return $null
}

function Remove-Section([string]$HostsText) {
    $re = [regex]::new('(?ms)^' + [regex]::Escape($MARKER_START) + '.*^' + [regex]::Escape($MARKER_END) + '[ \t]*\r?\n?')
    $hosts = $re.Replace($HostsText, '')
    foreach ($pat in $LEGACY_PATTERNS) {
        $hosts = [System.Text.RegularExpressions.Regex]::Replace(
            $hosts, $pat, '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    }
    return $hosts
}

function Read-Domains([string]$File) {
    $out = @()
    foreach ($l in [System.IO.File]::ReadAllLines($File)) {
        $t = $l.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        if ($t -notmatch '^[a-z0-9][a-z0-9\-]*(\.[a-z0-9\-]+)+$') {
            throw ("Refusing to install line that is not a plain domain name: '" + $t + "' (in " + $File + ")")
        }
        $out += $t
    }
    return $out
}

function New-Section([string[]]$Domains) {
    return ($MARKER_START + "`r`n" + (($Domains | ForEach-Object { '127.0.0.1 ' + $_ }) -join "`r`n") + "`r`n" + $MARKER_END + "`r`n")
}

function Test-RealHosts {
    return ($HostsPath -ieq (Join-Path $env:windir 'System32\drivers\etc\hosts'))
}

function Assert-Admin {
    if (-not (Test-RealHosts)) { return }  # testing against a copy: no admin needed
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Administrator rights are required. Double-click the .bat file instead of running this script directly."
    }
}

# Resolves one host the way the OS would (hosts file included) and reports
# whether it lands on this PC. GetHostAddresses consults the hosts file, unlike
# Resolve-DnsName, which asks the DNS server directly and would miss the block.
function Get-BlockProbeResult {
    param([string[]]$BlockedDomains)

    $target = (@($BlockedDomains) | Where-Object { $_ } | Select-Object -First 1)
    if (-not $target) {
        return @{ Probed = $false; Ok = $false; Detail = 'no blocked domain to probe' }
    }
    try {
        $addresses = @([Net.Dns]::GetHostAddresses($target) | ForEach-Object { $_.IPAddressToString })
    } catch {
        return @{
            Probed = $true
            Ok     = $false
            Detail = "could not resolve $target ($($_.Exception.Message))"
        }
    }
    return @{
        Probed = $true
        Ok     = ($addresses -contains '127.0.0.1')
        Detail = "$target -> " + ($addresses -join ', ')
    }
}

switch ($Action) {

    'status' {
        if (-not (Test-Path $HostsPath)) { throw "Hosts file not found: $HostsPath" }
        $hosts = [System.IO.File]::ReadAllText($HostsPath)
        $sec = Get-Section $hosts
        if ($sec) {
            $blocked = @($sec -split "`r?`n" | ForEach-Object {
                $m = [regex]::Match($_, '^\s*127\.0\.0\.1\s+(\S+)')
                if ($m.Success) { $m.Groups[1].Value }
            })
            $lastWrite = (Get-Item $HostsPath).LastWriteTime
            Write-Host "Ad block: ACTIVE"
            Write-Host ("  Domains blocked:  " + $blocked.Count)
            Write-Host ("  Hosts file last updated: " + $lastWrite.ToString('yyyy-MM-dd HH:mm'))
            $backupPath = $HostsPath + '.bak-statlocker-adblock'
            if (Test-Path $backupPath) {
                Write-Host ("  Backup file:  " + $backupPath)
            } else {
                Write-Host "  Backup file:  none (it is deleted when you remove the block)"
            }

            $probe = Get-BlockProbeResult -BlockedDomains (@($ProbeDomain) + $blocked)
            Write-Host ("  DNS probe:  " + $probe.Detail)
            if ($probe.Ok) {
                Write-Host "  The block is working: that domain resolves to this PC."
            } elseif ($ProbeDomain) {
                Write-Host "  That domain is not being blocked."
            } elseif ($probe.Probed) {
                Write-Host "  WARNING: a domain in your block list does not resolve to 127.0.0.1."
                Write-Host "  The hosts file may have been overwritten by another app, or DNS may be unavailable."
            }
            exit 0
        } else {
            Write-Host "Ad block: NOT active (no statlocker-adblock section found in the hosts file)."
            exit 3
        }
    }

    'install' {
        Assert-Admin

        # --- Resolve the domain list: bundled list, refreshed from GitHub if reachable ---
        $domains = Read-Domains $DomainsFile
        $source = "the list bundled with this folder ($($domains.Count) domains)"
        if (-not $NoLiveUpdate) {
            $tmp = Join-Path $env:TEMP 'statlocker-adblock-live-domains.txt'
            $tmpHash = "$tmp.sha256"
            $hashUrl = if ($LiveHashUrl) { $LiveHashUrl } else { "$LiveDomainsUrl.sha256" }
            try {
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                Remove-Item $tmpHash -Force -ErrorAction SilentlyContinue

                # Fetch the list. Failing here only means offline.
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-WebRequest -Uri $LiveDomainsUrl -OutFile $tmp -TimeoutSec 25 -UseBasicParsing
                } catch {
                    Write-Host "Could not reach GitHub to check for list updates - using the bundled list."
                    Write-Host "(If you are offline this is normal. Re-run 'Install AdBlock.bat' later to pick up updates.)"
                }

                # Verify it before trusting it: an unverifiable list is not installed.
                if (Test-Path $tmp) {
                    try {
                        $live = Read-Domains $tmp
                        if ($live.Count -lt 10 -or $live.Count -lt $domains.Count) {
                            Write-Host "The live list from GitHub looks stale or incomplete - using the bundled list."
                        } else {
                            Invoke-WebRequest -Uri $hashUrl -OutFile $tmpHash -TimeoutSec 25 -UseBasicParsing
                            $expected = (((Get-Content $tmpHash -Raw) -split '\s+')[0]).ToLower()
                            $actual = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash.ToLower()
                            if ($expected -ne $actual) {
                                throw "checksum mismatch (expected $expected, got $actual)"
                            }
                            $domains = $live
                            $source = "the latest list from GitHub ($($live.Count) domains, checksum verified)"
                        }
                    } catch {
                        Write-Host "The live list from GitHub could not be verified - using the bundled list."
                        Write-Host ("  (" + $_.Exception.Message + ")")
                    }
                }
            } finally {
                # Whatever happens above, the downloaded list never outlives the run.
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                Remove-Item $tmpHash -Force -ErrorAction SilentlyContinue
            }
        }

        # --- Write it ---
        Copy-Item $HostsPath ($HostsPath + '.bak-statlocker-adblock') -Force
        $hosts = [System.IO.File]::ReadAllText($HostsPath)
        $hosts = Remove-Section $hosts
        $section = New-Section $domains
        if ($hosts.TrimEnd() -ne '') { $hosts = $hosts.TrimEnd() + "`r`n`r`n" }
        $hosts = $hosts + $section
        [System.IO.File]::WriteAllText($HostsPath, $hosts)

        # --- Verify by reading back ---
        $check = Get-Section ([System.IO.File]::ReadAllText($HostsPath))
        if (-not $check) {
            Copy-Item ($HostsPath + '.bak-statlocker-adblock') $HostsPath -Force
            throw "Verification failed - the section was not found after writing. Your hosts file was restored from the backup."
        }

        # --- Flush the DNS cache so the block takes effect immediately ---
        # Windows caches name lookups. A cached ad address would keep resolving
        # to the real server until its TTL ran out, which looks exactly like the
        # tool not working. Restarting the app alone does not clear it.
        try {
            & ipconfig /flushdns | Out-Null
            Write-Host "  DNS cache flushed - the change is active now."
        } catch {
            Write-Host "  Could not flush the DNS cache - restarting the app is still enough."
        }

        Write-Host ("Installed: " + $domains.Count + " ad domains are now blocked on this PC.")
        Write-Host ("  Source:  " + $source)
        Write-Host ("  Backup:  " + $HostsPath + '.bak-statlocker-adblock')
        Write-Host "          (deleted automatically when you run Remove AdBlock.bat)"
        Write-Host ""
        Write-Host "Next step: quit the Statlocker companion app completely, then start it again."
        Write-Host "To undo at any time: double-click 'Remove AdBlock.bat' in this folder."
        exit 0
    }

    'remove' {
        Assert-Admin
        if (-not (Test-Path $HostsPath)) { Write-Host "Hosts file not found - nothing to do."; exit 0 }
        $hosts = [System.IO.File]::ReadAllText($HostsPath)
        if (-not (Get-Section $hosts)) {
            Write-Host "Nothing to remove - the statlocker-adblock section was not found."
            # Someone may have uninstalled with an older version, which left the
            # backup file behind. Clean it up so a clean install really is clean.
            $stale = $HostsPath + '.bak-statlocker-adblock'
            if (Test-Path $stale) {
                Remove-Item $stale -Force
                Write-Host "Deleted the backup file an older version left behind."
            }
            exit 0
        }
        [System.IO.File]::WriteAllText($HostsPath, (Remove-Section $hosts))
        if (Get-Section ([System.IO.File]::ReadAllText($HostsPath))) {
            throw "Verification failed - the section is still present. Do not edit hosts manually; report this."
        }
        # The backup exists only to undo a failed install. Leaving it behind after
        # a clean removal is exactly the leftover this tool promises not to create.
        $backup = $HostsPath + '.bak-statlocker-adblock'
        if (Test-Path $backup) { Remove-Item $backup -Force }
        # Flush the DNS cache too, so the old addresses come back promptly
        # instead of lingering until each cached entry expires.
        try { & ipconfig /flushdns | Out-Null } catch { }
        Write-Host "Removed: the ad block is off and your hosts file is back to how it was."
        Write-Host "The backup file was deleted too, so nothing is left behind."
        Write-Host "Restart the Statlocker app if you want the ads back (they will return)."
        exit 0
    }
}
