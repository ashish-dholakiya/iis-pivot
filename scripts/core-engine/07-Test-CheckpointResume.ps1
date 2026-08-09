<#
  07-Test-CheckpointResume.ps1

  IIS PIVOT -- Piece #8 (checkpoint RESUME capability)

  WHAT IT DOES: this is the other half of the checkpoint system we
  built earlier. Piece #4 proved checkpoints correctly RECORD success
  and failure. This piece proves the tool can actually RESUME from a
  checkpoint -- skipping steps already marked Completed, and only
  running what's left. That's the real reason checkpointing exists.

  HOW THE TEST WORKS:
    - Run this script normally: steps 1 and 2 succeed, step 3 is
      designed to fail on the FIRST run only (controlled by a marker
      file, not randomness).
    - Run the exact same script a second time: it reads the existing
      checkpoint file, sees steps 1 and 2 are already Completed, SKIPS
      them entirely, and only attempts step 3 again -- which succeeds
      this time.

  STILL NO REAL IIS CHANGES -- same simulated steps as Piece #4, just
  testing the resume logic this time instead of the recording logic.

  RUN THIS ON: the practice server, as Administrator.
  RUN IT TWICE, back to back, and send back BOTH outputs.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

# Fixed filename (not timestamped) so the SAME checkpoint file is reused
# across multiple runs -- that's what makes resume possible.
$checkpointDir  = 'C:\PivotCheckpoints'
New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
$checkpointPath = Join-Path $checkpointDir 'checkpoint-resume-test.json'

# This marker file simulates "the underlying problem got fixed between
# runs" -- on a real operation, this would be you fixing whatever broke
# (wrong port, missing prerequisite, etc.) before re-running. Delete
# this test's checkpoint + marker file to start the test over from
# scratch: Remove-Item C:\PivotCheckpoints\checkpoint-resume-test.json, C:\PivotCheckpoints\resume-test-marker.txt
$markerPath = Join-Path $checkpointDir 'resume-test-marker.txt'

$stepNames = @('Step-CheckPrerequisites', 'Step-ReadConfig', 'Step-FailsFirstTimeOnly')

# ---------------------------------------------------------------------
# Checkpoint engine, extended with resume logic
# ---------------------------------------------------------------------

function Get-OrCreateCheckpoint {
    if (Test-Path $checkpointPath) {
        Write-Host "  Existing checkpoint found -- resuming." -ForegroundColor Yellow
        return (Get-Content $checkpointPath -Raw | ConvertFrom-Json)
    }

    Write-Host "  No existing checkpoint -- starting fresh." -ForegroundColor Yellow
    $steps = [ordered]@{}
    foreach ($name in $stepNames) {
        $steps[$name] = [ordered]@{ status = 'NotStarted'; startedAt = $null; endedAt = $null; error = $null }
    }
    $checkpoint = [ordered]@{
        schemaVersion  = "0.1-checkpoint"
        createdAt      = (Get-Date).ToString("o")
        sourceHostname = $env:COMPUTERNAME
        operation      = "Resume capability test"
        steps          = $steps
    }
    $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
    return (Get-Content $checkpointPath -Raw | ConvertFrom-Json)
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

    # THE RESUME LOGIC: check current status before doing anything.
    $checkpoint = Get-Content $checkpointPath -Raw | ConvertFrom-Json
    $currentStatus = $checkpoint.steps.$StepName.status

    Write-Host ""
    Write-Host "  Step: $StepName" -ForegroundColor Yellow

    if ($currentStatus -eq 'Completed') {
        Write-Host "    Status -> SKIPPED (already Completed from a previous run)" -ForegroundColor DarkGray
        return
    }

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
Get-OrCreateCheckpoint | Out-Null
Write-Host "  Checkpoint file: $checkpointPath" -ForegroundColor Green

# ---------------------------------------------------------------------
Write-Section "Running steps"
# ---------------------------------------------------------------------

Invoke-CheckpointedStep -StepName 'Step-CheckPrerequisites' -Action {
    Start-Sleep -Milliseconds 300
}

Invoke-CheckpointedStep -StepName 'Step-ReadConfig' -Action {
    Start-Sleep -Milliseconds 300
}

try {
    Invoke-CheckpointedStep -StepName 'Step-FailsFirstTimeOnly' -Action {
        if (-not (Test-Path $markerPath)) {
            # First time only: fail, and leave a marker so next run knows to succeed.
            New-Item -Path $markerPath -ItemType File -Force | Out-Null
            throw "Simulated failure -- this is expected on the FIRST run only. Run this script again to see it succeed."
        }
        # Marker exists = this is a re-run, simulate the problem being fixed.
        Start-Sleep -Milliseconds 300
    }
} catch {
    Write-Host ""
    Write-Host "  (Expected on first run -- re-run this exact script to test resume.)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
Write-Section "Final checkpoint state"
# ---------------------------------------------------------------------
$final = Get-Content $checkpointPath -Raw | ConvertFrom-Json
$final.steps.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value.status)"
}

Write-Section "Summary"
if (Test-Path $markerPath) {
    $allDone = ($final.steps.PSObject.Properties | Where-Object { $_.Value.status -ne 'Completed' }).Count -eq 0
    if ($allDone) {
        Write-Host "  ALL STEPS COMPLETED. Resume worked correctly -- steps 1 and 2 were skipped this run." -ForegroundColor Green
        Write-Host "  To reset and test again from scratch:"
        Write-Host "    Remove-Item '$checkpointPath', '$markerPath'"
    } else {
        Write-Host "  Not all steps completed yet -- this was the first run. Run this script again now." -ForegroundColor Yellow
    }
} else {
    Write-Host "  First run complete (step 3 failed as designed). Run this exact script again to test resume." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Send back this full console output."
