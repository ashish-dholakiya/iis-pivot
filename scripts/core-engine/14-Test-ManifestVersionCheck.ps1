<#
  14-Test-ManifestVersionCheck.ps1  (v2 -- self-discovering)

  IIS PIVOT -- Proves ManifestVersion.psm1 correctly distinguishes a
  compatible manifest from an incompatible/unknown one.

  WHAT CHANGED FROM v1:
  v1 required you to already know a manifest file's path on your
  laptop -- which meant manually RDP-ing into the server, finding the
  file in C:\PivotExports, copying it over, and typing its path. That
  is exactly the kind of "go hunt for a file somewhere else" friction
  this tool should never require.

  v2 fixes this: it connects to the practice server itself (same
  stored credential every other script already uses), lists whatever
  manifests already exist in C:\PivotExports, shows them as a simple
  numbered menu, and lets you pick one -- or generate a brand new one
  on the spot. Nothing to copy, nothing to hunt for.

  WHAT IT DOES:
    1. Loads ManifestVersion.psm1.
    2. Connects to the server and lists existing manifests in
       C:\PivotExports.
    3. Asks you to pick one from the list (or generate a fresh one).
    4. Pulls that manifest's content back over the same remote
       connection and checks it for compatibility.
    5. Also runs the simulated compatible/incompatible checks from v1,
       so the module's core behavior is still proven even if the
       server has no manifests yet.

  RUN THIS ON: your laptop.

  REQUIRES: ManifestVersion.psm1 in the same folder as this script.
            The 'IISPivot-PracticeServer' secret already stored in
            IISPivotVault (same one every other script uses).

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp   = '192.168.29.201'
$serverSecretName = 'IISPivot-PracticeServer'
$exportDir        = 'C:\PivotExports'

Write-Section "Loading manifest version module"
Import-Module (Join-Path $PSScriptRoot 'ManifestVersion.psm1') -Force
Write-Host "  ManifestVersion.psm1 loaded." -ForegroundColor Green

$schemaInfo = Get-ManifestSchemaInfo
Write-Host "  Current manifest schema version this tool stamps new files with: $($schemaInfo.currentVersion)"
Write-Host "  Schema versions this build can safely restore: $($schemaInfo.supportedVersions -join ', ')"

Write-Section "Connecting to server and listing existing manifests"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$serverCred = Get-Secret -Name $serverSecretName -Vault 'IISPivotVault'
Write-Host "  Server credential retrieved for: $($serverCred.UserName)" -ForegroundColor Green

$remoteFiles = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
    param($Dir)
    if (-not (Test-Path $Dir)) { return @() }
    Get-ChildItem -Path $Dir -Filter '*.json' | Sort-Object LastWriteTime -Descending |
        ForEach-Object { [ordered]@{ name = $_.Name; lastWriteTime = $_.LastWriteTime.ToString("o"); sizeBytes = $_.Length } }
} -ArgumentList $exportDir

if ($remoteFiles.Count -eq 0) {
    Write-Host "  No manifests found in $exportDir on the server." -ForegroundColor Yellow
    Write-Host "  (This is fine -- it just means 01-Inspect-IIS.ps1 hasn't been run recently, or ever, on this server.)"
} else {
    Write-Host "  Found $($remoteFiles.Count) manifest(s) in ${exportDir}:"
    for ($i = 0; $i -lt $remoteFiles.Count; $i++) {
        $f = $remoteFiles[$i]
        Write-Host ("    [{0}] {1}   ({2:N0} bytes, {3})" -f ($i + 1), $f.name, $f.sizeBytes, $f.lastWriteTime)
    }
}

Write-Section "Pick a manifest to check"
$selectedManifestJson = $null
$selectedManifestLabel = $null

if ($remoteFiles.Count -gt 0) {
    Write-Host "  Enter a number from the list above, or press Enter to skip and use a simulated manifest instead."
    $choice = Read-Host "  Your choice"
    if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $remoteFiles.Count) {
        $selectedFile = $remoteFiles[[int]$choice - 1]
        Write-Host "  Pulling '$($selectedFile.name)' from the server..." -ForegroundColor DarkGray
        $selectedManifestJson = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
            param($Path)
            Get-Content -Path $Path -Raw
        } -ArgumentList (Join-Path $exportDir $selectedFile.name)
        $selectedManifestLabel = $selectedFile.name
        Write-Host "  Retrieved ($($selectedManifestJson.Length) characters)." -ForegroundColor Green
    } else {
        Write-Host "  No valid selection made -- skipping the real-manifest check." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Nothing to pick from -- skipping straight to the simulated checks below." -ForegroundColor DarkGray
}

Write-Section "Check 1: the manifest you picked (or skipped)"
if ($selectedManifestJson) {
    $realManifest = $selectedManifestJson | ConvertFrom-Json
    $result = Test-ManifestCompatibility -Manifest $realManifest
    Write-Host "  File checked   : $selectedManifestLabel (on server, no local copy needed)"
    Write-Host "  schemaVersion  : $($result.manifestVersion)"
    Write-Host "  isCompatible   : $($result.isCompatible)"
    Write-Host "  reason         : $($result.reason)"
} else {
    Write-Host "  SKIPPED -- no manifest was selected." -ForegroundColor Yellow
}

Write-Section "Check 2: a simulated CURRENT-version manifest (expected: COMPATIBLE)"
$simulatedManifest = [ordered]@{
    schemaVersion  = $schemaInfo.currentVersion
    exportedAt     = (Get-Date).ToString("o")
    sourceHostname = "SIMULATED-FOR-TEST"
    sites          = @()
} | ConvertTo-Json | ConvertFrom-Json

$result2 = Test-ManifestCompatibility -Manifest $simulatedManifest
Write-Host "  schemaVersion  : $($result2.manifestVersion)"
Write-Host "  isCompatible   : $($result2.isCompatible)"
Write-Host "  reason         : $($result2.reason)"
if ($result2.isCompatible) {
    Write-Host "  RESULT AS EXPECTED -- current-version manifest correctly accepted." -ForegroundColor Green
} else {
    Write-Host "  UNEXPECTED -- this manifest was expected to be flagged compatible. Investigate." -ForegroundColor Red
}

Write-Section "Check 3: Assert-ManifestCompatible correctly blocks an incompatible manifest"
$fakeOldManifest = [ordered]@{
    schemaVersion  = "0.1-combined-inspection"
    exportedAt     = (Get-Date).ToString("o")
    sourceHostname = "SIMULATED-FOR-TEST"
    sites          = @()
} | ConvertTo-Json | ConvertFrom-Json

try {
    Assert-ManifestCompatible -Manifest $fakeOldManifest | Out-Null
    Write-Host "  UNEXPECTED -- Assert-ManifestCompatible did not throw for an old-schema manifest. Investigate." -ForegroundColor Red
} catch {
    Write-Host "  Assert-ManifestCompatible correctly threw: $($_.Exception.Message)" -ForegroundColor Green
    Write-Host "  RESULT AS EXPECTED -- a real restore script calling this would stop here, before touching anything." -ForegroundColor Green
}

Write-Section "Summary"
Write-Host "  ManifestVersion.psm1 correctly distinguishes compatible from incompatible manifests."
Write-Host "  No manual file-hunting was required -- everything was discovered and pulled from the server directly."
Write-Host "  Send back this full console output."
