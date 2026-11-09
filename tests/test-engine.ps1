# Self-contained tests for adblock.ps1.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-engine.ps1
#
# No Pester dependency: the engine is exercised through its own -HostsPath /
# -DomainsFile / -LiveDomainsUrl seams against a throwaway hosts file, so these
# tests never touch the real one. Exits non-zero when anything fails.

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Engine = Join-Path $RepoRoot 'adblock.ps1'

$script:Checks = 0
$script:Failures = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)
    $script:Checks++
    if ($Condition) {
        Write-Host "  ok   $Name"
    } else {
        $script:Failures++
        Write-Host "  FAIL $Name" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    $script:Checks++
    if ($Expected -eq $Actual) {
        Write-Host "  ok   $Name"
    } else {
        $script:Failures++
        Write-Host ("  FAIL {0} (expected '{1}', got '{2}')" -f $Name, $Expected, $Actual) -ForegroundColor Red
    }
}

function Invoke-Engine {
    param([string[]]$Arguments)
    # The engine writes its own errors to stderr; with Stop they would become
    # terminating errors in this test script instead of output we can assert on.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Engine @Arguments 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    return [pscustomobject]@{
        Code   = $code
        Output = ($output -join "`n")
    }
}

# --- workspace -------------------------------------------------------------

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("slk-engine-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null

$HostsFile     = Join-Path $Tmp 'hosts.test'
$BundledList   = Join-Path $Tmp 'domains.txt'
$LiveList      = Join-Path $Tmp 'live-domains.txt'
$LiveHash      = "$LiveList.sha256"
$BadList       = Join-Path $Tmp 'bad.txt'

$Bundled = @(
    'a.example.com', 'b.example.com', 'c.example.com', 'd.example.com',
    'e.example.com', 'f.example.com', 'g.example.com', 'h.example.com',
    'i.example.com', 'j.example.com', 'k.example.com', 'l.example.com'
)
$Live = @('x.example.com', 'y.example.com', 'z.example.com') + $Bundled

Set-Content -Path $BundledList -Value $Bundled -Encoding ascii
Set-Content -Path $LiveList -Value $Live -Encoding ascii
Set-Content -Path $LiveHash -Value ("$((Get-FileHash -Path $LiveList -Algorithm SHA256).Hash.ToLower())  live-domains.txt") -Encoding ascii
Set-Content -Path $BadList -Value @('good.example.com', 'not a domain!!') -Encoding ascii

$InitialHosts = @(
    '127.0.0.1 localhost',
    '::1 localhost',
    '',
    '# custom user entry',
    '10.0.0.5 myserver.local'
)

function Reset-HostsFile {
    Set-Content -Path $HostsFile -Value $InitialHosts -Encoding ascii
}

function Get-FileBody {
    return [System.IO.File]::ReadAllText($HostsFile)
}

function Get-LiveUrl {
    param([string]$Path)
    return 'file:///' + ($Path -replace '\\', '/')
}

Reset-HostsFile

# --- tests -----------------------------------------------------------------

Write-Host "`n[1] install writes the block section"
$r = Invoke-Engine -Arguments @('install', '-HostsPath', $HostsFile, '-DomainsFile', $BundledList, '-NoLiveUpdate')
Assert-Equal 0 $r.Code 'install exits 0'
Assert-True ((Get-FileBody) -match [regex]::Escape('# === statlocker-adblock')) 'section marker written'
Assert-True ((Get-FileBody) -match '127\.0\.0\.1 a\.example\.com') 'first bundled domain blocked'
Assert-True (Test-Path ($HostsFile + '.bak-statlocker-adblock')) 'install left a backup of the hosts file'

Write-Host "`n[2] a second install is idempotent"
$firstHash = (Get-FileHash -Path $HostsFile -Algorithm SHA256).Hash
$r = Invoke-Engine -Arguments @('install', '-HostsPath', $HostsFile, '-DomainsFile', $BundledList, '-NoLiveUpdate')
$secondHash = (Get-FileHash -Path $HostsFile -Algorithm SHA256).Hash
Assert-Equal 0 $r.Code 'second install exits 0'
Assert-Equal $firstHash $secondHash 'hosts file byte-identical after reinstalling'

Write-Host "`n[3] the user's own hosts entries survive"
Assert-True ((Get-FileBody) -match 'myserver\.local') 'custom hosts entry preserved'

Write-Host "`n[4] status reports the block as active"
$r = Invoke-Engine -Arguments @('status', '-HostsPath', $HostsFile)
Assert-Equal 0 $r.Code 'status exits 0 while active'
Assert-True ($r.Output -match 'ACTIVE') 'status says ACTIVE'
Assert-True ($r.Output -match 'Domains blocked:\s+12') 'status counts 12 domains'

Write-Host "`n[5] remove takes the section out"
$r = Invoke-Engine -Arguments @('remove', '-HostsPath', $HostsFile)
Assert-Equal 0 $r.Code 'remove exits 0'
Assert-True (-not ((Get-FileBody) -match 'statlocker-adblock')) 'section gone after remove'
Assert-True ((Get-FileBody) -match 'myserver\.local') 'custom entry still present after remove'
Assert-True (-not (Test-Path ($HostsFile + '.bak-statlocker-adblock'))) 'remove deleted the backup too - nothing left behind'

Write-Host "`n[6] status reports the block as inactive"
$r = Invoke-Engine -Arguments @('status', '-HostsPath', $HostsFile)
Assert-Equal 3 $r.Code 'status exits 3 when nothing is installed'

Write-Host "`n[7] a malformed domain line aborts the install"
Reset-HostsFile
$r = Invoke-Engine -Arguments @('install', '-HostsPath', $HostsFile, '-DomainsFile', $BadList, '-NoLiveUpdate')
Assert-True ($r.Code -ne 0) 'malformed list makes install fail'
Assert-True (-not ((Get-FileBody) -match 'statlocker-adblock')) 'nothing written when the list is rejected'

Write-Host "`n[8] the live list is accepted when its checksum matches"
Reset-HostsFile
$r = Invoke-Engine -Arguments @(
    'install', '-HostsPath', $HostsFile, '-DomainsFile', $BundledList,
    '-LiveDomainsUrl', (Get-LiveUrl $LiveList),
    '-LiveHashUrl',   (Get-LiveUrl $LiveHash)
)
Assert-Equal 0 $r.Code 'install with a verified live list exits 0'
Assert-True ($r.Output -match 'checksum verified') 'reports the list as checksum-verified'
Assert-True ((Get-FileBody) -match '127\.0\.0\.1 x\.example\.com') 'live domain written'

Write-Host "`n[9] a mismatched checksum falls back to the bundled list"
Set-Content -Path $LiveHash -Value ("0" * 64 + "  live-domains.txt") -Encoding ascii
Reset-HostsFile
$r = Invoke-Engine -Arguments @(
    'install', '-HostsPath', $HostsFile, '-DomainsFile', $BundledList,
    '-LiveDomainsUrl', (Get-LiveUrl $LiveList),
    '-LiveHashUrl',   (Get-LiveUrl $LiveHash)
)
Assert-Equal 0 $r.Code 'a bad checksum does not fail the install'
Assert-True ($r.Output -match 'checksum') 'warns that the checksum failed'
Assert-True ((Get-FileBody) -match '127\.0\.0\.1 a\.example\.com') 'bundled list used'
Assert-True (-not ((Get-FileBody) -match '127\.0\.0\.1 x\.example\.com')) 'unverified live domain NOT written'
$tmpBase = Join-Path $env:TEMP 'statlocker-adblock-live-domains.txt'
Assert-True (-not (Test-Path $tmpBase)) 'live list temp file cleaned up'
Assert-True (-not (Test-Path ($tmpBase + '.sha256'))) 'live hash temp file cleaned up'

Write-Host "`n[10] the DNS probe confirms a blocked domain resolves locally"
Reset-HostsFile
$r = Invoke-Engine -Arguments @('install', '-HostsPath', $HostsFile, '-DomainsFile', $BundledList, '-NoLiveUpdate')
$r = Invoke-Engine -Arguments @('status', '-HostsPath', $HostsFile, '-ProbeDomain', 'localhost')
Assert-True ($r.Output -match '127\.0\.0\.1') 'probe reports localhost resolving to 127.0.0.1'
$r = Invoke-Engine -Arguments @('status', '-HostsPath', $HostsFile, '-ProbeDomain', 'no-such-host.invalid')
Assert-True ($r.Output -match 'DNS probe') 'probe reports an unresolvable host without crashing'

# --- summary ---------------------------------------------------------------

Remove-Item -Path $Tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host ("All {0} checks passed." -f $script:Checks)
    exit 0
}
Write-Host ("{0} of {1} checks FAILED." -f $script:Failures, $script:Checks)
exit 1
