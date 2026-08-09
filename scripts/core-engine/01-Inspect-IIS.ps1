<#
  01-Inspect-IIS.ps1

  IIS PIVOT -- Combined read-only inspection (merges former Piece #1
  and Piece #2, both already verified working on this server).

  WHAT IT DOES:
    1. Prints IIS sites and app pools to the console (visibility check).
    2. Exports that same data as a structured JSON manifest file
       (the beginning of the real migration manifest format).

  STILL FULLY READ-ONLY TOWARD IIS: no site, app pool, or binding is
  created, modified, or deleted. The only thing written to disk is the
  JSON export file in C:\PivotExports.

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output. If you want to double
  check the JSON file's contents too, run afterward:
    Get-Content (the path printed at the end)
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------
Write-Section "Environment"
# ---------------------------------------------------------------------
Write-Host "  Computer name : $env:COMPUTERNAME"
Write-Host "  PowerShell    : $($PSVersionTable.PSVersion)"
Write-Host "  OS            : $((Get-CimInstance Win32_OperatingSystem).Caption)"

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
Write-Host "  Elevated      : $($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

# ---------------------------------------------------------------------
Write-Section "Loading IIS module"
# ---------------------------------------------------------------------
Import-Module WebAdministration -ErrorAction Stop
Write-Host "  WebAdministration module loaded OK" -ForegroundColor Green

try {
    Import-Module IISAdministration -ErrorAction Stop
    Write-Host "  IISAdministration module loaded OK" -ForegroundColor Green
} catch {
    Write-Host "  IISAdministration module not available (not critical -- WebAdministration covers this script)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------
Write-Section "Reading IIS configuration"
# ---------------------------------------------------------------------
$sites = Get-Website
$pools = Get-ChildItem IIS:\AppPools
Write-Host "  Found $($sites.Count) site(s) and $($pools.Count) app pool(s)."

$poolLookup = @{}
foreach ($pool in $pools) {
    $poolLookup[$pool.Name] = [ordered]@{
        name           = $pool.Name
        state          = [string]$pool.State
        managedRuntime = $pool.managedRuntimeVersion
        pipelineMode   = [string]$pool.managedPipelineMode
        identityType   = [string]$pool.processModel.identityType
    }
}

# ---------------------------------------------------------------------
Write-Section "IIS Sites (console view)"
# ---------------------------------------------------------------------
foreach ($site in $sites) {
    Write-Host ""
    Write-Host "  Site: $($site.Name)" -ForegroundColor Green
    Write-Host "    State         : $($site.State)"
    Write-Host "    ID            : $($site.ID)"
    Write-Host "    Physical Path : $($site.PhysicalPath)"
    Write-Host "    Bindings      : $(($site.Bindings.Collection | ForEach-Object { $_.Protocol + '://' + $_.BindingInformation }) -join ', ')"
    Write-Host "    App Pool      : $($site.applicationPool)"
}

# ---------------------------------------------------------------------
Write-Section "Application Pools (console view)"
# ---------------------------------------------------------------------
foreach ($pool in $pools) {
    Write-Host ""
    Write-Host "  App Pool: $($pool.Name)" -ForegroundColor Green
    Write-Host "    State         : $($pool.State)"
    Write-Host "    .NET Version  : $($pool.managedRuntimeVersion)"
    Write-Host "    Identity Type : $($pool.processModel.identityType)"
}

# ---------------------------------------------------------------------
Write-Section "Building JSON manifest"
# ---------------------------------------------------------------------
$siteExport = foreach ($site in $sites) {
    $bindings = foreach ($b in $site.Bindings.Collection) {
        [ordered]@{
            protocol              = $b.Protocol
            bindingInformation    = $b.BindingInformation
            certificateHash       = $b.CertificateHash
            certificateStoreName  = $b.CertificateStoreName
        }
    }
    $poolName = $site.applicationPool
    $poolInfo = if ($poolLookup.ContainsKey($poolName)) { $poolLookup[$poolName] } else { $null }

    [ordered]@{
        name            = $site.Name
        id              = $site.ID
        state           = [string]$site.State
        physicalPath    = $site.PhysicalPath
        bindings        = @($bindings)
        applicationPool = $poolInfo
    }
}

$manifest = [ordered]@{
    schemaVersion  = "0.1-combined-inspection"
    exportedAt     = (Get-Date).ToString("o")
    sourceHostname = $env:COMPUTERNAME
    siteCount      = $sites.Count
    sites          = @($siteExport)
}

# ---------------------------------------------------------------------
Write-Section "Writing JSON file"
# ---------------------------------------------------------------------
$exportDir  = 'C:\PivotExports'
New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
$fileName   = "iis-manifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$exportPath = Join-Path $exportDir $fileName
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $exportPath -Encoding UTF8
Write-Host "  Written to: $exportPath" -ForegroundColor Green

# ---------------------------------------------------------------------
Write-Section "Summary"
# ---------------------------------------------------------------------
Write-Host "  IIS itself was not touched -- only the JSON file above was created."
Write-Host "  Send back this full console output to confirm the result."
