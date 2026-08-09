<#
  03-Checkpoint-Engine.ps1

  IIS PIVOT -- Piece #4 (checkpoint/state mechanism, still no IIS changes)

  WHAT IT DOES: implements and demonstrates the checkpoint system that
  every future real operation (site creation, binding restore, etc.)
  will run through. A checkpoint file tracks each named step's status
  (NotStarted / InProgress / Completed / Failed), so if something ever
  fails partway through a real migration, we know exactly which step
  broke and can resume from there instead of starting over or guessing.

  THIS SCRIPT DOES NOT TOUCH IIS AT ALL. It only demonstrates the
  checkpoint mechanism using three fake/simulated steps, so we can
  verify the mechanism itself works correctly before any real
  operation ever depends on it.

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output, AND the contents of
  the checkpoint JSON file (path printed at the end).
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$checkpointDir  = 'C:\PivotCheckpoints'
New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
$checkpointPath = Join-Path $checkpointDir "checkpoint-test-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

# ---------------------------------------------------------------------
# Checkpoint engine functions
# ---------------------------------------------------------------------

function New-Checkpoint {
    param([string[]]$StepNames)

    $steps = [ordered]@{}
    foreach ($name in $StepNames) {
        $steps[$name] = [ordered]@{
            status    = 'NotStarted'
            startedAt = $null
            endedAt   = $null
            error     = $null
        }
    }

    $checkpoint = [ordered]@{
        schemaVersion = "0.1-checkpoint"
        createdAt     = (Get-Date).ToString("o")
        sourceHostname = $env:COMPUTERNAME
        steps         = $steps
    }

    $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
    return $checkpoint
}

function Set-StepStatus {
    param(
        [string]$StepName,
        [ValidateSet('InProgress', 'Completed', 'Failed')]
        [string]$Status,
        [string]$ErrorMessage = $null
    )

    $checkpoint = Get-Content $checkpointPath -Raw | ConvertFrom-Json

    $step = $checkpoint.steps.$StepName
    $step.status = $Status
    if ($Status -eq 'InProgress') {
        $step.startedAt = (Get-Date).ToString("o")
    }
    if ($Status -in @('Completed', 'Failed')) {
        $step.endedAt = (Get-Date).ToString("o")
    }
    if ($Status -eq 'Failed') {
        $step.error = $ErrorMessage
    }

    $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
}

function Invoke-CheckpointedStep {
    param(
        [string]$StepName,
        [scriptblock]$Action
    )

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
Write-Section "Creating checkpoint file"
# ---------------------------------------------------------------------
$stepNames = @('SimulatedStep-CheckPrerequisites', 'SimulatedStep-ReadConfig', 'SimulatedStep-WillFailOnPurpose')
New-Checkpoint -StepNames $stepNames | Out-Null
Write-Host "  Checkpoint file created: $checkpointPath" -ForegroundColor Green

# ---------------------------------------------------------------------
Write-Section "Running simulated steps through the checkpoint engine"
# ---------------------------------------------------------------------

# Step 1: a fake step that succeeds
Invoke-CheckpointedStep -StepName 'SimulatedStep-CheckPrerequisites' -Action {
    Start-Sleep -Milliseconds 300   # pretend to do some work
}

# Step 2: another fake step that succeeds
Invoke-CheckpointedStep -StepName 'SimulatedStep-ReadConfig' -Action {
    Start-Sleep -Milliseconds 300
}

# Step 3: deliberately fails, to prove the checkpoint correctly records
# a Failed state with an error message instead of silently continuing
# or crashing without a trace.
try {
    Invoke-CheckpointedStep -StepName 'SimulatedStep-WillFailOnPurpose' -Action {
        throw "This is a deliberate test failure -- proving the checkpoint engine correctly records failures."
    }
} catch {
    Write-Host ""
    Write-Host "  (Expected: the step above was designed to fail, to prove failure handling works.)" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------
Write-Section "Final checkpoint state"
# ---------------------------------------------------------------------
$final = Get-Content $checkpointPath -Raw | ConvertFrom-Json
$final.steps.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value.status)"
}

Write-Section "Summary"
Write-Host "  IIS was not touched -- this tested only the checkpoint mechanism itself."
Write-Host "  Checkpoint file: $checkpointPath"
Write-Host "  Expected result: first two steps Completed, third step Failed (on purpose)."
Write-Host "  Send back this full console output, plus the checkpoint file contents (Get-Content $checkpointPath)."
