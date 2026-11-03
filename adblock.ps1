#Requires -Version 5.1
<#
statlocker-adblock engine.

  install : writes (or refreshes) the ad-block section in the Windows hosts file
  remove  : removes the section, leaving everything else in hosts untouched
  status  : reports whether the block is active

The block lives in a clearly marked section inside the hosts file, so it is
trivially reversible and never mixes with the user's own entries. Every
install backs up the hosts file first (hosts.bak-statlocker-adblock).
The script is idempotent: running install any number of times produces the
same end state.

Hidden test override: -HostsPath points at a different hosts file. Admin is
only required when touching the real system hosts file.
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
    [string]$LiveDomainsUrl = 'https://raw.githubusercontent.com/XGradien/statlocker-adblock/main/domains.txt'
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

switch ($Action) {

    'status' {
        if (-not (Test-Path $HostsPath)) { throw "Hosts file not found: $HostsPath" }
        $hosts = [System.IO.File]::ReadAllText($HostsPath)
        $sec = Get-Section $hosts
        if ($sec) {
            $n = @($sec -split "`n" | Where-Object { $_ -match '^\s*127\.0\.0\.1\s' }).Count
            $lastWrite = (Get-Item $HostsPath).LastWriteTime
            Write-Host "Ad block: ACTIVE"
            Write-Host ("  Domains blocked:  " + $n)
            Write-Host ("  Hosts file last updated: " + $lastWrite.ToString('yyyy-MM-dd HH:mm'))
            Write-Host ("  Backup file:  " + $HostsPath + '.bak-statlocker-adblock (from the last install)')
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
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $tmp = Join-Path $env:TEMP 'statlocker-adblock-live-domains.txt'
                Invoke-WebRequest -Uri $LiveDomainsUrl -OutFile $tmp -TimeoutSec 25 -UseBasicParsing
                $live = Read-Domains $tmp
                if ($live.Count -ge 10 -and $live.Count -ge $domains.Count) {
                    $domains = $live
                    $source = "the latest list from GitHub ($($live.Count) domains)"
                } else {
                    Write-Host "The live list from GitHub looks stale or incomplete - using the bundled list."
                }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Host "Could not reach GitHub to check for list updates - using the bundled list."
                Write-Host ("(If you are offline this is normal. Re-run 'Install AdBlock.bat' later to pick up updates.)")
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

        Write-Host ("Installed: " + $domains.Count + " ad domains are now blocked on this PC.")
        Write-Host ("  Source:  " + $source)
        Write-Host ("  Backup:  " + $HostsPath + '.bak-statlocker-adblock')
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
            exit 0
        }
        [System.IO.File]::WriteAllText($HostsPath, (Remove-Section $hosts))
        if (Get-Section ([System.IO.File]::ReadAllText($HostsPath))) {
            throw "Verification failed - the section is still present. Do not edit hosts manually; report this."
        }
        Write-Host "Removed: the ad block is off and your hosts file is back to how it was."
        Write-Host "Restart the Statlocker app if you want the ads back (they will return)."
        exit 0
    }
}
