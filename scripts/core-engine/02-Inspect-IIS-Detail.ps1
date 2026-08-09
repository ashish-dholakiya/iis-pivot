<#
  02-Inspect-IIS-Detail.ps1

  IIS PIVOT -- Piece #3 (read-only, deeper config detail)

  WHAT IT DOES: extends the previous inspection with detail a real
  migration needs but we haven't captured yet:
    - Per-site authentication settings (anonymous / Windows / basic)
    - App pool recycling settings (periodic restart interval)
    - App pool idle timeout
    - App pool start mode (AlwaysRunning vs OnDemand)

  STILL FULLY READ-ONLY TOWARD IIS. Writes one new JSON file to
  C:\PivotExports (does not overwrite the previous one -- each export
  gets its own timestamped filename).

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

Write-Section "Loading IIS module"
Import-Module WebAdministration -ErrorAction Stop
Write-Host "  WebAdministration module loaded OK" -ForegroundColor Green

Write-Section "Reading sites and app pools"
$sites = Get-Website
$pools = Get-ChildItem IIS:\AppPools
Write-Host "  Found $($sites.Count) site(s) and $($pools.Count) app pool(s)."

# ---------------------------------------------------------------------
Write-Section "Per-site authentication settings"
# ---------------------------------------------------------------------
# Authentication is configured per-site (or per-app) under
# system.webServer/security/authentication in each site's web.config
# scope. Reading it via Get-WebConfigurationProperty at the site level.
$authTypes = @('anonymousAuthentication', 'windowsAuthentication', 'basicAuthentication')

$siteAuthInfo = @{}
foreach ($site in $sites) {
    $siteAuthInfo[$site.Name] = [ordered]@{}
    foreach ($authType in $authTypes) {
        try {
            $enabled = (Get-WebConfigurationProperty -Filter "/system.webServer/security/authentication/$authType" `
                        -Name enabled -PSPath "IIS:\Sites\$($site.Name)" -ErrorAction Stop).Value
        } catch {
            $enabled = "unknown"
        }
        $siteAuthInfo[$site.Name][$authType] = $enabled
    }

    Write-Host ""
    Write-Host "  Site: $($site.Name)" -ForegroundColor Green
    foreach ($authType in $authTypes) {
        Write-Host "    $authType : $($siteAuthInfo[$site.Name][$authType])"
    }
}

# ---------------------------------------------------------------------
Write-Section "App pool recycling / timeout / start mode"
# ---------------------------------------------------------------------
$poolDetail = @{}
foreach ($pool in $pools) {
    $recycleMinutes = $pool.recycling.periodicRestart.time.TotalMinutes
    $idleTimeoutMinutes = $pool.processModel.idleTimeout.TotalMinutes
    $startMode = [string]$pool.startMode

    $poolDetail[$pool.Name] = [ordered]@{
        periodicRestartMinutes = $recycleMinutes
        idleTimeoutMinutes     = $idleTimeoutMinutes
        startMode              = $startMode
    }

    Write-Host ""
    Write-Host "  App Pool: $($pool.Name)" -ForegroundColor Green
    Write-Host "    Periodic restart (minutes) : $recycleMinutes  (0 = disabled)"
    Write-Host "    Idle timeout (minutes)     : $idleTimeoutMinutes  (0 = disabled)"
    Write-Host "    Start mode                 : $startMode"
}

# ---------------------------------------------------------------------
Write-Section "Building extended JSON manifest"
# ---------------------------------------------------------------------
$siteExport = foreach ($site in $sites) {
    [ordered]@{
        name           = $site.Name
        id             = $site.ID
        applicationPool = $site.applicationPool
        authentication = $siteAuthInfo[$site.Name]
    }
}

$poolExport = foreach ($pool in $pools) {
    $detail = $poolDetail[$pool.Name]
    [ordered]@{
        name                    = $pool.Name
        periodicRestartMinutes  = $detail.periodicRestartMinutes
        idleTimeoutMinutes      = $detail.idleTimeoutMinutes
        startMode               = $detail.startMode
    }
}

$manifest = [ordered]@{
    schemaVersion  = "0.2-piece3-detail"
    exportedAt     = (Get-Date).ToString("o")
    sourceHostname = $env:COMPUTERNAME
    sites          = @($siteExport)
    appPools       = @($poolExport)
}

Write-Section "Writing JSON file"
$exportDir  = 'C:\PivotExports'
New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
$fileName   = "iis-detail-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$exportPath = Join-Path $exportDir $fileName
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $exportPath -Encoding UTF8
Write-Host "  Written to: $exportPath" -ForegroundColor Green

Write-Section "Summary"
Write-Host "  IIS itself was not touched -- only the JSON file above was created."
Write-Host "  Send back this full console output to confirm the result."
