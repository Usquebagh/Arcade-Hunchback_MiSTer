<#
.SYNOPSIS
Copy the engineering RBF and MRA to a MiSTer over SSH and launch the core.

.DESCRIPTION
Stub: not yet exercised against real hardware. Enforces the card rules from
docs/STATUS.md: exactly one hunchback* RBF in _Arcade/cores, named after the
MRA <rbf> element; the previous card copy is backed up locally to
results/card-backups (never on the card); the SHA-256 is verified after copying.
Only the hunchback* glob is listed on the card, never the whole _Arcade tree.

Uses key-based SSH login (BatchMode, so it never stops at a password prompt).

.EXAMPLE
powershell -File scripts/deploy.ps1
powershell -File scripts/deploy.ps1 -MisterHost 192.168.75.57 -NoLoad
.EXAMPLE
powershell -File scripts/deploy.ps1 -Rbf results/x.rbf -BuildId v261019-152733
#>
param(
    [string]$MisterHost = '192.168.75.57',
    [string]$User = 'root',
    [string]$Rbf = 'output_files/Arcade-Hunchback.rbf',
    [string]$Mra = 'releases/Hunchback (CVS).mra',
    [string]$BuildId = '',
    [switch]$NoLoad,
    [switch]$NoBackup,
    # For a renamed release: back up differently named hunchback* RBFs
    # locally, then remove them from the card, keeping exactly one.
    [switch]$ReplaceOther
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$target = "$User@$MisterHost"
$cores = '/media/fat/_Arcade/cores'
$arcade = '/media/fat/_Arcade'

foreach ($f in @($Rbf, $Mra)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "Missing $f" }
}
[xml]$mraXml = Get-Content -LiteralPath $Mra -Raw
$rbfName = [string]$mraXml.misterromdescription.rbf
if (-not $rbfName) { throw "No <rbf> element in $Mra" }
$rbfName = "$rbfName.rbf"
$mraName = Split-Path -Leaf $Mra
$localHash = (Get-FileHash -LiteralPath $Rbf -Algorithm SHA256).Hash.ToLower()
$resolvedBuildId = $BuildId
if (-not $resolvedBuildId) {
    $rbfDir = Split-Path -Parent (Resolve-Path -LiteralPath $Rbf).Path
    if ((Split-Path -Leaf $rbfDir) -eq 'output_files') {
        $buildIdPath = Join-Path (Split-Path -Parent $rbfDir) 'build_id.v'
        if (Test-Path -LiteralPath $buildIdPath) {
            $m = Select-String -LiteralPath $buildIdPath -Pattern '"([^"]+)"' | Select-Object -First 1
            if ($m) { $resolvedBuildId = $m.Matches[0].Groups[1].Value }
        }
    }
}
$buildLabel = 'unknown'
if ($resolvedBuildId) { $buildLabel = $resolvedBuildId }
Write-Host "RBF $Rbf -> $cores/$rbfName"
Write-Host "    sha256 $localHash, build $buildLabel"

function Invoke-Remote([string]$cmd) {
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=10 $target $cmd
    if ($LASTEXITCODE -ne 0) { throw "ssh failed ($LASTEXITCODE): $cmd" }
    return $out
}

# 1. Precheck: only the expected hunchback RBF (or none) may exist.
$existing = @(Invoke-Remote "ls -1 $cores/hunchback* 2>/dev/null; true" | Where-Object { $_ })
$others = @($existing | Where-Object { (Split-Path -Leaf $_) -ne $rbfName })
if ($others.Count -gt 0 -and -not $ReplaceOther) {
    throw "Other hunchback RBFs on the card; rerun with -ReplaceOther or remove them by hand:`n$($others -join "`n")"
}

# 2. Back up every card copy locally (never on the card).
if ($existing.Count -gt 0 -and -not $NoBackup) {
    $backup = Join-Path $root ("results/card-backups/" + (Get-Date -Format 'yyyyMMddTHHmmss'))
    New-Item -ItemType Directory -Force $backup | Out-Null
    foreach ($f in $existing) {
        & scp -o BatchMode=yes "${target}:$f" "$backup/"
        if ($LASTEXITCODE -ne 0) { throw "Backup failed: $f" }
    }
    Write-Host "Backed up card RBF(s) to $backup"
}
if ($others.Count -gt 0) {
    if ($NoBackup) { throw '-ReplaceOther requires a backup; do not combine with -NoBackup' }
    foreach ($f in $others) {
        if ($f -notmatch '^/media/fat/_Arcade/cores/hunchback[^/]*\.rbf$') { throw "Refusing to remove $f" }
        Invoke-Remote "rm -f '$f'" | Out-Null
        Write-Host "Removed $f from the card (backed up)"
    }
}

# 3. Upload to /tmp (no spaces in remote paths), then move into place.
Copy-Item -LiteralPath $Mra -Destination "$env:TEMP\hunchback-deploy.mra" -Force
& scp -o BatchMode=yes $Rbf "$env:TEMP\hunchback-deploy.mra" "${target}:/tmp/"
if ($LASTEXITCODE -ne 0) { throw 'Upload failed' }
$rbfBase = Split-Path -Leaf $Rbf
$remote = "mv -f '/tmp/$rbfBase' '$cores/$rbfName' && " +
          "mv -f /tmp/hunchback-deploy.mra '$arcade/$mraName' && sync && " +
          "sha256sum '$cores/$rbfName'"
$sum = (Invoke-Remote $remote) -split '\s+' | Select-Object -First 1
if ($sum -ne $localHash) { throw "SHA-256 mismatch: card $sum, local $localHash" }
Write-Host "Card SHA-256 verified."

# 4. Launch through the MRA.
if (-not $NoLoad) {
    Invoke-Remote "echo 'load_core $arcade/$mraName' > /dev/MiSTer_cmd" | Out-Null
    Write-Host "Loaded $mraName."
}
if ($resolvedBuildId) {
    Write-Host "Confirm the OSD version line shows $resolvedBuildId before trusting any result."
} else {
    Write-Host "Build ID unknown for this RBF: read the OSD version line and record it before trusting any result (pass -BuildId to check it)."
}
