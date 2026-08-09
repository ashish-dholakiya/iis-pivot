<#
  05-Clone-Site.ps1

  IIS PIVOT -- Piece #6 (first real "migration-style" operation)

  WHAT IT DOES: reads the configuration of an EXISTING site
  (PivotTest-Delta, created in the last piece) and uses that data --
  not hardcoded values -- to create a new, equivalent site under a
  different name and port. This is the first piece that actually
  behaves like a migration: read config from a source, recreate it on
  a target, checkpointed the whole way.

  SOURCE SITE (read from): PivotTest-Delta
  TARGET SITE (created):   PivotTest-Delta-Clone, port 8086

  Content files are copied (not just referenced) so the clone is a
  real, independent site -- same idea as what a real cross-server
  migration will eventually do, just source and target are the same
  server for this test.

  SAFE / REVERSIBLE: creates one new site/pool/folder. Removal
  commands are printed at the end.

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output, AND confirm whether
  http://localhost:8086 loads and shows the same content as
  http://localhost:8085.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$sourceSiteName = 'PivotTest-Delta'
$targetSiteName = 'PivotTest-Delta-Clone'
$targetPort     = 8086
$targetPath     = 'C:\PivotTestSites\PivotTest-Delta-Clone'

$checkpointDir  = 'C:\PivotCheckpoints'
New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
$checkpointPath = Join-Path $checkpointDir "checkpoint-clone-site-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

# ---------------------------------------------------------------------
# Checkpoint engine (same mechanism as previous pieces)
# ---------------------------------------------------------------------

function New-Checkpoint {
    param([string[]]$StepNames)
    $steps = [ordered]@{}
    foreach ($name in $StepNames) {
        $steps[$name] = [ordered]@{ status = 'NotStarted'; startedAt = $null; endedAt = $null; error = $null }
    }
    $checkpoint = [ordered]@{
        schemaVersion  = "0.1-checkpoint"
        createdAt      = (Get-Date).ToString("o")
        sourceHostname = $env:COMPUTERNAME
        operation      = "Clone site: $sourceSiteName -> $targetSiteName"
        steps          = $steps
    }
    $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
}

function Set-StepStatus {
    param([string]$StepName, [ValidateSet('InProgress','Completed','Failed')][string]$Status, [string]$ErrorMessage = $null)
    $checkpoint = Get-Content $checkpointPath -Raw | ConvertFrom-Json
    $step = $checkpoint.steps.$StepName
    $step.status = $Status
    if ($Status -eq 'InProgress') { $step.startedAt = (Get-Date).ToString("o") }
    if ($Status -in @('Completed','Failed')) { $step.endedAt = (Get-Date).ToString("o") }
    if ($Status -eq 'Failed') { $step.error = $ErrorMessage }
    $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
}

function Invoke-CheckpointedStep {
    param([string]$StepName, [scriptblock]$Action)
    Write-Host ""
    Write-Host "  Step: $StepName" -ForegroundColor Yellow
    Set-StepStatus -StepName $StepName -Status 'InProgress'
    Write-Host "    Status -> InProgress"
    try {
        & $Action
        Set-StepStatus -StepName $StepName -Status 'Completed'
        Write-Host "    Status -> Completed" -ForegroundColor Green
    } catch {
        Set-StepStatus -StepName $StepName -Status 'Failed' -ErrorMessage $_.Exception.Message
        Write-Host "    Status -> Failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# ---------------------------------------------------------------------
Write-Section "Setup"
# ---------------------------------------------------------------------
Import-Module WebAdministration -ErrorAction Stop
$stepNames = @('ReadSourceConfig', 'CheckTargetPrerequisites', 'CopyContent', 'CreateTargetAppPool', 'CreateTargetSite', 'VerifyTargetResponds')
New-Checkpoint -StepNames $stepNames
Write-Host "  Checkpoint file: $checkpointPath" -ForegroundColor Green
Write-Host "  Source: $sourceSiteName  ->  Target: $targetSiteName (port $targetPort)"

# Holds data read from the source, used by later steps
$sourceConfig = $null

# ---------------------------------------------------------------------
Write-Section "Running steps"
# ---------------------------------------------------------------------

Invoke-CheckpointedStep -StepName 'ReadSourceConfig' -Action {
    $site = Get-Website -Name $sourceSiteName -ErrorAction Stop
    $pool = Get-Item "IIS:\AppPools\$($site.applicationPool)" -ErrorAction Stop

    $script:sourceConfig = [ordered]@{
        physicalPath = $site.PhysicalPath
        identityType = [string]$pool.processModel.identityType
    }

    Write-Host "    Read source physical path: $($script:sourceConfig.physicalPath)"
    Write-Host "    Read source pool identity : $($script:sourceConfig.identityType)"
}

Invoke-CheckpointedStep -StepName 'CheckTargetPrerequisites' -Action {
    if (Get-Website -Name $targetSiteName -ErrorAction SilentlyContinue) {
        throw "A site named '$targetSiteName' already exists -- refusing to overwrite. Delete it first for a clean re-run."
    }
    $portInUse = Get-WebBinding | Where-Object { $_.bindingInformation -match ":$targetPort`:" }
    if ($portInUse) {
        throw "Port $targetPort is already in use -- pick a different port."
    }
}

Invoke-CheckpointedStep -StepName 'CopyContent' -Action {
    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
    # Robocopy, copy-only, matching the design doc's principle of never
    # destructively touching the source -- this only reads from source,
    # writes to target.
    $result = robocopy $sourceConfig.physicalPath $targetPath /E /NFL /NDL /NJH /NJS
    # Robocopy's own exit codes: 0-7 are success variants, 8+ are real errors
    if ($LASTEXITCODE -ge 8) {
        throw "Robocopy reported an error copying site content (exit code $LASTEXITCODE)."
    }
}

Invoke-CheckpointedStep -StepName 'CreateTargetAppPool' -Action {
    New-WebAppPool -Name $targetSiteName | Out-Null
    Set-ItemProperty "IIS:\AppPools\$targetSiteName" -Name processModel.identityType -Value $sourceConfig.identityType
    Write-Host "    Created target pool with identity type: $($sourceConfig.identityType) (matched from source)"
}

Invoke-CheckpointedStep -StepName 'CreateTargetSite' -Action {
    New-Website -Name $targetSiteName -Port $targetPort -PhysicalPath $targetPath -ApplicationPool $targetSiteName | Out-Null
    New-NetFirewallRule -DisplayName "PivotTest-Port-$targetPort" -Direction Inbound -Protocol TCP -LocalPort $targetPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
}

Invoke-CheckpointedStep -StepName 'VerifyTargetResponds' -Action {
    Start-Sleep -Seconds 2
    $response = Invoke-WebRequest -Uri "http://localhost:$targetPort" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -ne 200) {
        throw "Target site responded with unexpected status code: $($response.StatusCode)"
    }
    if ($response.Content -notmatch [regex]::Escape($sourceSiteName)) {
        throw "Target site content doesn't match expected source content."
    }
}

# ---------------------------------------------------------------------
Write-Section "Final checkpoint state"
# ---------------------------------------------------------------------
$final = Get-Content $checkpointPath -Raw | ConvertFrom-Json
$final.steps.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value.status)"
}

Write-Section "Summary"
Write-Host "  Cloned '$sourceSiteName' -> '$targetSiteName' on port $targetPort, verified responding." -ForegroundColor Green
Write-Host "  Checkpoint file: $checkpointPath"
Write-Host ""
Write-Host "  TO UNDO / CLEAN UP LATER, run:" -ForegroundColor DarkGray
Write-Host "    Remove-Website -Name '$targetSiteName'" -ForegroundColor DarkGray
Write-Host "    Remove-WebAppPool -Name '$targetSiteName'" -ForegroundColor DarkGray
Write-Host "    Remove-Item -Path '$targetPath' -Recurse -Force" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Send back this full console output, and confirm both http://localhost:8085 and http://localhost:8086 show matching content."
