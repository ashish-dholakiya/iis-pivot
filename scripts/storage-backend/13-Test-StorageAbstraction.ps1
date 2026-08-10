<#
  13-Test-StorageAbstraction.ps1

  IIS PIVOT -- Proves the new storage abstraction layer
  (StorageBackend.psm1) works exactly like script 12 did, but through
  Save-Backup / Get-Backup / Test-StorageConnection instead of
  Azure-specific REST calls written directly into this script.

  WHAT IT DOES:
    1. Loads StorageBackend.psm1 and builds an Azure storage config.
    2. Runs Test-StorageConnection as a pre-flight check.
    3. Pulls a fresh manifest from the server (same as script 12).
    4. Saves it via Save-Backup (backend-agnostic).
    5. Lists the container's contents via Get-BackupList.
    6. Retrieves it back via Get-Backup and verifies it matches exactly.

  RUN THIS ON: your laptop.

  REQUIRES: 11-Store-AzureSasUrl.ps1 already run successfully.
            StorageBackend.psm1 in the same folder as this script
            (or update the Import-Module path below).

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp   = '192.168.29.201'
$serverSecretName = 'IISPivot-PracticeServer'

Write-Section "Loading storage abstraction module"
Import-Module (Join-Path $PSScriptRoot 'StorageBackend.psm1') -Force
Write-Host "  StorageBackend.psm1 loaded." -ForegroundColor Green

$storageConfig = New-StorageConfig -Backend Azure
Write-Host "  Storage config built for backend: $($storageConfig.backend)" -ForegroundColor Green

Write-Section "Step 1: Pre-flight -- Test-StorageConnection"
$connectionOk = Test-StorageConnection -StorageConfig $storageConfig
if (-not $connectionOk) {
    throw "Test-StorageConnection reported the backend is not reachable/usable. Stopping before touching anything else."
}
Write-Host "  Connection check passed." -ForegroundColor Green

Write-Section "Step 2: Retrieving stored server credential"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$serverCred = Get-Secret -Name $serverSecretName -Vault 'IISPivotVault'
Write-Host "  Server credential retrieved for: $($serverCred.UserName)" -ForegroundColor Green

Write-Section "Step 3: Generating a fresh manifest on the server (remote)"
$manifestJson = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
    Import-Module WebAdministration -ErrorAction Stop
    $sites = Get-Website
    $siteExport = foreach ($site in $sites) {
        [ordered]@{ name = $site.Name; id = $site.ID; state = [string]$site.State; physicalPath = $site.PhysicalPath }
    }
    $manifest = [ordered]@{
        schemaVersion  = "0.1-storage-abstraction-test"
        exportedAt     = (Get-Date).ToString("o")
        sourceHostname = $env:COMPUTERNAME
        sites          = @($siteExport)
    }
    $manifest | ConvertTo-Json -Depth 6
}
Write-Host "  Retrieved manifest ($($manifestJson.Length) characters) from the server." -ForegroundColor Green

Write-Section "Step 4: Save-Backup (backend-agnostic)"
$backupName = "iis-manifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$savedName  = Save-Backup -StorageConfig $storageConfig -Name $backupName -Content $manifestJson
Write-Host "  Saved as: $savedName" -ForegroundColor Green

Write-Section "Step 5: Get-BackupList (backend-agnostic)"
$allBackups = Get-BackupList -StorageConfig $storageConfig
Write-Host "  Items currently in storage:"
$allBackups | ForEach-Object { Write-Host "    - $_" }

Write-Section "Step 6: Get-Backup and verify integrity (backend-agnostic)"
$retrievedContent = Get-Backup -StorageConfig $storageConfig -Name $savedName

if ($manifestJson -eq $retrievedContent) {
    Write-Host "  MATCH -- retrieved content is identical to what was saved." -ForegroundColor Green
} else {
    Write-Host "  MISMATCH -- retrieved content differs. Needs investigation." -ForegroundColor Red
}

Write-Section "Summary"
Write-Host "  Full round trip tested through the storage abstraction layer: server -> Save-Backup -> Get-BackupList -> Get-Backup -> verified."
Write-Host "  No Azure-specific code was written in this script -- all of it lives in StorageBackend.psm1 now."
Write-Host "  Send back this full console output."
