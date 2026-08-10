<#
  06-Migrate-Certificate.ps1

  IIS PIVOT -- Piece #7 (certificate / HTTPS binding migration)

  WHAT IT DOES: reads the HTTPS binding and certificate currently on
  PivotTest-Alpha, and applies that SAME certificate to
  PivotTest-Delta-Clone -- adding an HTTPS binding to it on a new port.

  SOURCE: PivotTest-Alpha's HTTPS binding + certificate (port 8444)
  TARGET: PivotTest-Delta-Clone gets a new HTTPS binding (port 8446)

  BUG FIX (found via smoke test, script 15): the original version of
  this script added the HTTPS binding but never opened a matching
  firewall rule for the new port. The AddTargetBinding step now opens
  the firewall rule too, matching the pattern 05-Clone-Site.ps1 already
  used correctly for HTTP ports.

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output, AND confirm whether
  https://localhost:8446 loads (certificate warning expected, click
  through/accept it).
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$sourceSiteName = 'PivotTest-Alpha'
$targetSiteName = 'PivotTest-Delta-Clone'
$targetHttpsPort = 8446

$checkpointDir  = 'C:\PivotCheckpoints'
New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
$checkpointPath = Join-Path $checkpointDir "checkpoint-migrate-cert-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

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
        operation      = "Migrate certificate: $sourceSiteName -> $targetSiteName"
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

Write-Section "Setup"
Import-Module WebAdministration -ErrorAction Stop
$stepNames = @('ReadSourceCertificate', 'CheckTargetPrerequisites', 'AddTargetBinding', 'ApplyCertificate', 'VerifyHttpsResponds')
New-Checkpoint -StepNames $stepNames
Write-Host "  Checkpoint file: $checkpointPath" -ForegroundColor Green
Write-Host "  Source: $sourceSiteName (HTTPS cert)  ->  Target: $targetSiteName (new HTTPS binding, port $targetHttpsPort)"

$certThumbprint = $null
$certStoreName  = $null

Write-Section "Running steps"

Invoke-CheckpointedStep -StepName 'ReadSourceCertificate' -Action {
    $site = Get-Website -Name $sourceSiteName -ErrorAction Stop
    $httpsBinding = $site.Bindings.Collection | Where-Object { $_.Protocol -eq 'https' } | Select-Object -First 1

    if (-not $httpsBinding) {
        throw "'$sourceSiteName' has no HTTPS binding -- nothing to migrate."
    }
    if (-not $httpsBinding.CertificateHash) {
        throw "'$sourceSiteName' has an HTTPS binding but no certificate attached -- nothing to migrate."
    }

    $script:certThumbprint = $httpsBinding.CertificateHash
    $script:certStoreName  = $httpsBinding.CertificateStoreName

    Write-Host "    Found certificate thumbprint: $($script:certThumbprint)"
    Write-Host "    Certificate store: $($script:certStoreName)"

    $certPath = "Cert:\LocalMachine\$($script:certStoreName)\$($script:certThumbprint)"
    if (-not (Test-Path $certPath)) {
        throw "Certificate with thumbprint $($script:certThumbprint) not found."
    }
}

Invoke-CheckpointedStep -StepName 'CheckTargetPrerequisites' -Action {
    if (-not (Get-Website -Name $targetSiteName -ErrorAction SilentlyContinue)) {
        throw "Target site '$targetSiteName' doesn't exist yet -- run 05-Clone-Site.ps1 first."
    }
    $portInUse = Get-WebBinding | Where-Object { $_.bindingInformation -match ":$targetHttpsPort`:" }
    if ($portInUse) {
        throw "Port $targetHttpsPort is already in use -- pick a different port."
    }
}

Invoke-CheckpointedStep -StepName 'AddTargetBinding' -Action {
    New-WebBinding -Name $targetSiteName -Protocol https -Port $targetHttpsPort -IPAddress '*'

    New-NetFirewallRule -DisplayName "PivotTest-Port-$targetHttpsPort" -Direction Inbound -Protocol TCP -LocalPort $targetHttpsPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Write-Host "    Opened firewall rule for port $targetHttpsPort"
}

Invoke-CheckpointedStep -StepName 'ApplyCertificate' -Action {
    $binding = Get-WebBinding -Name $targetSiteName -Protocol https -Port $targetHttpsPort
    $binding.AddSslCertificate($certThumbprint, $certStoreName)
    Write-Host "    Applied certificate $certThumbprint to $targetSiteName on port $targetHttpsPort"
}

Invoke-CheckpointedStep -StepName 'VerifyHttpsResponds' -Action {
    Start-Sleep -Seconds 2
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $originalCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    try {
        $response = Invoke-WebRequest -Uri "https://localhost:$targetHttpsPort" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -ne 200) {
            throw "HTTPS site responded with unexpected status code: $($response.StatusCode)"
        }
    } finally {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $originalCallback
    }
}

Write-Section "Final checkpoint state"
$final = Get-Content $checkpointPath -Raw | ConvertFrom-Json
$final.steps.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value.status)"
}

Write-Section "Summary"
Write-Host "  Certificate migrated from '$sourceSiteName' to '$targetSiteName' (port $targetHttpsPort), verified responding over HTTPS (localhost)." -ForegroundColor Green
Write-Host "  Checkpoint file: $checkpointPath"
Write-Host ""
Write-Host "  TO UNDO LATER, run:" -ForegroundColor DarkGray
Write-Host "    Remove-WebBinding -Name '$targetSiteName' -Protocol https -Port $targetHttpsPort" -ForegroundColor DarkGray
Write-Host "    Remove-NetFirewallRule -DisplayName 'PivotTest-Port-$targetHttpsPort'" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Send back this full console output, and confirm https://localhost:$targetHttpsPort loads."
Write-Host "  For a real network-reachability check, also run 15-Test-SmokeTestSuite.ps1 from your laptop."
