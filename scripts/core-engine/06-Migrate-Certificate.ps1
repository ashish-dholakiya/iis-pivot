<#
  06-Migrate-Certificate.ps1

  IIS PIVOT -- Piece #7 (certificate / HTTPS binding migration)

  WHAT IT DOES: reads the HTTPS binding and certificate currently on
  PivotTest-Alpha (created back in Setup-PracticeServer.ps1), and
  applies that SAME certificate to a new site, PivotTest-Delta-Clone
  (created in the previous piece) -- adding an HTTPS binding to it on
  a new port. This proves IIS Pivot can carry over not just site
  config and content, but the certificate binding itself, which the
  design doc specifically flags as one of the gaps plain Web Deploy
  doesn't handle well.

  SOURCE: PivotTest-Alpha's HTTPS binding + certificate (port 8444)
  TARGET: PivotTest-Delta-Clone gets a new HTTPS binding (port 8446)
          using the SAME certificate (by thumbprint), not a new one.

  SAFE / REVERSIBLE: adds one binding to an existing test site. No
  certificate is deleted or modified -- only read and re-applied.
  Removal instructions are at the bottom of this file.

  RUN THIS ON: the practice server, as Administrator.

  WHAT TO REPORT BACK: the full console output, AND confirm whether
  https://localhost:8446 loads (your browser will show a certificate
  warning -- that's expected and fine, since it's a self-signed test
  certificate. Click through/accept it to confirm the page loads).
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

# ---------------------------------------------------------------------
Write-Section "Setup"
# ---------------------------------------------------------------------
Import-Module WebAdministration -ErrorAction Stop
$stepNames = @('ReadSourceCertificate', 'CheckTargetPrerequisites', 'AddTargetBinding', 'ApplyCertificate', 'VerifyHttpsResponds')
New-Checkpoint -StepNames $stepNames
Write-Host "  Checkpoint file: $checkpointPath" -ForegroundColor Green
Write-Host "  Source: $sourceSiteName (HTTPS cert)  ->  Target: $targetSiteName (new HTTPS binding, port $targetHttpsPort)"

$certThumbprint = $null
$certStoreName  = $null

# ---------------------------------------------------------------------
Write-Section "Running steps"
# ---------------------------------------------------------------------

Invoke-CheckpointedStep -StepName 'ReadSourceCertificate' -Action {
    $site = Get-Website -Name $sourceSiteName -ErrorAction Stop
    $httpsBinding = $site.Bindings.Collection | Where-Object { $_.Protocol -eq 'https' } | Select-Object -First 1

    if (-not $httpsBinding) {
        throw "'$sourceSiteName' has no HTTPS binding -- nothing to migrate. Check the practice server setup script ran correctly."
    }
    if (-not $httpsBinding.CertificateHash) {
        throw "'$sourceSiteName' has an HTTPS binding but no certificate attached -- nothing to migrate."
    }

    $script:certThumbprint = $httpsBinding.CertificateHash
    $script:certStoreName  = $httpsBinding.CertificateStoreName

    Write-Host "    Found certificate thumbprint: $($script:certThumbprint)"
    Write-Host "    Certificate store: $($script:certStoreName)"

    # Confirm the certificate actually exists in the local cert store --
    # the binding could theoretically reference a thumbprint that's no
    # longer present, which would be a real-world migration gotcha worth
    # catching here rather than failing later with a confusing error.
    $certPath = "Cert:\LocalMachine\$($script:certStoreName)\$($script:certThumbprint)"
    if (-not (Test-Path $certPath)) {
        throw "Certificate with thumbprint $($script:certThumbprint) not found in Cert:\LocalMachine\$($script:certStoreName). The binding references a cert that isn't actually installed."
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
}

Invoke-CheckpointedStep -StepName 'ApplyCertificate' -Action {
    $binding = Get-WebBinding -Name $targetSiteName -Protocol https -Port $targetHttpsPort
    $binding.AddSslCertificate($certThumbprint, $certStoreName)
    Write-Host "    Applied certificate $certThumbprint to $targetSiteName on port $targetHttpsPort"
}

Invoke-CheckpointedStep -StepName 'VerifyHttpsResponds' -Action {
    Start-Sleep -Seconds 2

    # Same root cause as the earlier PowerShell 7 install failure: this
    # server's .NET Framework defaults to older TLS versions, which
    # breaks the HTTPS handshake unless TLS 1.2 is explicitly enabled
    # for this session.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    # Self-signed test cert won't be trusted by default, so certificate
    # validation needs to be temporarily bypassed for this check only.
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

# ---------------------------------------------------------------------
Write-Section "Final checkpoint state"
# ---------------------------------------------------------------------
$final = Get-Content $checkpointPath -Raw | ConvertFrom-Json
$final.steps.PSObject.Properties | ForEach-Object {
    Write-Host "  $($_.Name): $($_.Value.status)"
}

Write-Section "Summary"
Write-Host "  Certificate migrated from '$sourceSiteName' to '$targetSiteName' (port $targetHttpsPort), verified responding over HTTPS." -ForegroundColor Green
Write-Host "  Checkpoint file: $checkpointPath"
Write-Host ""
Write-Host "  TO UNDO LATER, run:" -ForegroundColor DarkGray
Write-Host "    Remove-WebBinding -Name '$targetSiteName' -Protocol https -Port $targetHttpsPort" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Send back this full console output, and confirm https://localhost:$targetHttpsPort loads (a certificate warning in your browser is expected -- click through/accept it, since this is a self-signed test cert)."
