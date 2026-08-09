<#
  04-Create-TestSite.ps1

  IIS PIVOT -- Piece #5 (FIRST REAL IIS WRITE OPERATION)

  WHAT IT DOES: creates one new, small, reversible IIS site
  ("PivotTest-Delta" on port 8085), running every step through the
  same checkpoint engine verified in the previous piece. This is the
  first script in the whole project that actually changes IIS instead
  of just reading it.

  SAFE / REVERSIBLE: creates exactly one new site, one new app pool,
  and one small folder. Nothing existing is touched. Full removal
  instructions are at the bottom of this file if you want to undo it
  afterward.

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output, AND confirm whether
  http://localhost:8085 loads afterward.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

# --- Config for this test site ---
$siteName    = 'PivotTest-Delta'
$sitePort    = 8085
$sitePath    = 'C:\PivotTestSites\PivotTest-Delta'
$poolName    = $siteName

$checkpointDir  = 'C:\PivotCheckpoints'
New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
$checkpointPath = Join-Path $checkpointDir "checkpoint-create-site-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

# ---------------------------------------------------------------------
# Checkpoint engine (same mechanism as the previous piece)
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
        operation      = "Create test site: $siteName"
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
$stepNames = @('CheckPrerequisites', 'CreateSiteFolder', 'CreateAppPool', 'CreateSite', 'VerifySiteResponds')
New-Checkpoint -StepNames $stepNames
Write-Host "  Checkpoint file: $checkpointPath" -ForegroundColor Green
Write-Host "  Target site: $siteName on port $sitePort"

# ---------------------------------------------------------------------
Write-Section "Running steps"
# ---------------------------------------------------------------------

Invoke-CheckpointedStep -StepName 'CheckPrerequisites' -Action {
    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        throw "A site named '$siteName' already exists -- refusing to overwrite. Delete it first if you want a clean re-run."
    }
    $portInUse = Get-WebBinding | Where-Object { $_.bindingInformation -match ":$sitePort`:" }
    if ($portInUse) {
        throw "Port $sitePort is already in use by another site -- pick a different port."
    }
}

Invoke-CheckpointedStep -StepName 'CreateSiteFolder' -Action {
    New-Item -Path $sitePath -ItemType Directory -Force | Out-Null
    $html = "<html><body><h1>$siteName</h1><p>Created by IIS Pivot test piece #5, $(Get-Date -Format o)</p></body></html>"
    Set-Content -Path (Join-Path $sitePath 'index.html') -Value $html -Encoding UTF8
}

Invoke-CheckpointedStep -StepName 'CreateAppPool' -Action {
    New-WebAppPool -Name $poolName | Out-Null
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType -Value 'ApplicationPoolIdentity'
}

Invoke-CheckpointedStep -StepName 'CreateSite' -Action {
    New-Website -Name $siteName -Port $sitePort -PhysicalPath $sitePath -ApplicationPool $poolName | Out-Null
    New-NetFirewallRule -DisplayName "PivotTest-Port-$sitePort" -Direction Inbound -Protocol TCP -LocalPort $sitePort -Action Allow -ErrorAction SilentlyContinue | Out-Null
}

Invoke-CheckpointedStep -StepName 'VerifySiteResponds' -Action {
    Start-Sleep -Seconds 2   # give IIS a moment to bind
    $response = Invoke-WebRequest -Uri "http://localhost:$sitePort" -UseBasicParsing -TimeoutSec 10
    if ($response.StatusCode -ne 200) {
        throw "Site responded with unexpected status code: $($response.StatusCode)"
    }
    if ($response.Content -notmatch [regex]::Escape($siteName)) {
        throw "Site responded but content doesn't look right -- expected to find '$siteName' in the response."
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
Write-Host "  Site '$siteName' created and verified responding on port $sitePort." -ForegroundColor Green
Write-Host "  Checkpoint file: $checkpointPath"
Write-Host ""
Write-Host "  TO UNDO / CLEAN UP THIS TEST SITE LATER, run:" -ForegroundColor DarkGray
Write-Host "    Remove-Website -Name '$siteName'" -ForegroundColor DarkGray
Write-Host "    Remove-WebAppPool -Name '$poolName'" -ForegroundColor DarkGray
Write-Host "    Remove-Item -Path '$sitePath' -Recurse -Force" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Send back this full console output, and confirm whether http://localhost:$sitePort loads for you."
