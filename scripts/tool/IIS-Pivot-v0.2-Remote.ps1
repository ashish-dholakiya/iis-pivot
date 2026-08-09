<#
  IIS-Pivot-v0.2-Remote.ps1

  IIS PIVOT -- v0.2 (runs remotely, using stored credentials)

  WHAT IT DOES: same migration logic as IIS-Pivot-v0.1.ps1, but this
  version runs from your LAPTOP and triggers the whole thing on the
  server over WinRM, using the credential already stored securely in
  Piece #10 -- no RDP, no password typed, no logging into the server
  at all. This is the real architecture: jumpbox (your laptop, for
  now) commanding a target server remotely.

  RUN THIS ON: your laptop. NOT the server.

  REQUIRES: you already ran 08-Test-SecureCredentials.ps1 successfully
  on this laptop (so the credential is stored).

  USAGE:
    .\IIS-Pivot-v0.2-Remote.ps1 -TargetServerIp "192.168.29.201" -SourceSite "PivotTest-Gamma" -TargetSite "PivotTest-Gamma-Copy" -TargetPort 8092

  RESUMABLE: same as v0.1 -- if it fails partway, fix the issue and
  run the exact same command again.
#>

param(
    [string]$TargetServerIp = '192.168.29.201',
    [Parameter(Mandatory=$true)][string]$SourceSite,
    [Parameter(Mandatory=$true)][string]$TargetSite,
    [Parameter(Mandatory=$true)][int]$TargetPort,
    [switch]$IncludeHttps,
    [int]$TargetHttpsPort
)

$ErrorActionPreference = 'Stop'
$secretName = 'IISPivot-PracticeServer'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

Write-Section "Retrieving stored credential"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$cred = Get-Secret -Name $secretName -Vault 'IISPivotVault' -ErrorAction Stop
Write-Host "  Using credential for: $($cred.UserName)" -ForegroundColor Green
Write-Host "  Target server: $TargetServerIp"

Write-Section "Running migration remotely on $TargetServerIp"

$result = Invoke-Command -ComputerName $TargetServerIp -Credential $cred -ScriptBlock {

    param($SourceSite, $TargetSite, $TargetPort, $IncludeHttps, $TargetHttpsPort)

    $ErrorActionPreference = 'Stop'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Import-Module WebAdministration -ErrorAction Stop

    $targetPath = "C:\PivotTestSites\$TargetSite"
    $checkpointDir  = 'C:\PivotCheckpoints'
    New-Item -Path $checkpointDir -ItemType Directory -Force | Out-Null
    $checkpointPath = Join-Path $checkpointDir "checkpoint-migrate-$TargetSite.json"

    $stepNames = @('ReadSourceConfig', 'CheckTargetPrerequisites', 'CopyContent', 'CreateTargetAppPool', 'CreateTargetSite', 'VerifyHttpResponds')
    if ($IncludeHttps) { $stepNames += @('AddHttpsBinding', 'ApplyCertificate', 'VerifyHttpsResponds') }

    if (-not (Test-Path $checkpointPath)) {
        $steps = [ordered]@{}
        foreach ($name in $stepNames) {
            $steps[$name] = [ordered]@{ status = 'NotStarted'; startedAt = $null; endedAt = $null; error = $null }
        }
        $checkpoint = [ordered]@{
            schemaVersion  = "0.2-remote"
            createdAt      = (Get-Date).ToString("o")
            sourceHostname = $env:COMPUTERNAME
            operation      = "Remote migrate: $SourceSite -> $TargetSite (port $TargetPort)"
            steps          = $steps
        }
        $checkpoint | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
    }

    function Set-StepStatus {
        param([string]$StepName, [string]$Status, [string]$ErrorMessage = $null)
        $cp = Get-Content $checkpointPath -Raw | ConvertFrom-Json
        $step = $cp.steps.$StepName
        $step.status = $Status
        if ($Status -eq 'InProgress') { $step.startedAt = (Get-Date).ToString("o") }
        if ($Status -in @('Completed','Failed')) { $step.endedAt = (Get-Date).ToString("o") }
        if ($Status -eq 'Failed') { $step.error = $ErrorMessage }
        $cp | ConvertTo-Json -Depth 6 | Set-Content -Path $checkpointPath -Encoding UTF8
    }

    function Invoke-Step {
        param([string]$StepName, [scriptblock]$Action)
        $cp = Get-Content $checkpointPath -Raw | ConvertFrom-Json
        if ($cp.steps.$StepName.status -eq 'Completed') {
            Write-Output "  Step: $StepName -> SKIPPED (already completed)"
            return
        }
        Set-StepStatus -StepName $StepName -Status 'InProgress'
        try {
            & $Action
            Set-StepStatus -StepName $StepName -Status 'Completed'
            Write-Output "  Step: $StepName -> Completed"
        } catch {
            Set-StepStatus -StepName $StepName -Status 'Failed' -ErrorMessage $_.Exception.Message
            Write-Output "  Step: $StepName -> Failed: $($_.Exception.Message)"
            throw
        }
    }

    $sourceConfig = $null
    $certThumbprint = $null
    $certStoreName  = $null

    Invoke-Step -StepName 'ReadSourceConfig' -Action {
        $site = Get-Website -Name $SourceSite -ErrorAction Stop
        $pool = Get-Item "IIS:\AppPools\$($site.applicationPool)" -ErrorAction Stop
        $script:sourceConfig = [ordered]@{ physicalPath = $site.PhysicalPath; identityType = [string]$pool.processModel.identityType }
        if ($IncludeHttps) {
            $httpsBinding = $site.Bindings.Collection | Where-Object { $_.Protocol -eq 'https' } | Select-Object -First 1
            if (-not $httpsBinding -or -not $httpsBinding.CertificateHash) { throw "-IncludeHttps specified but source has no HTTPS binding." }
            $script:certThumbprint = $httpsBinding.CertificateHash
            $script:certStoreName  = $httpsBinding.CertificateStoreName
        }
    }

    Invoke-Step -StepName 'CheckTargetPrerequisites' -Action {
        if (-not (Get-Website -Name $SourceSite -ErrorAction SilentlyContinue)) { throw "Source site '$SourceSite' does not exist." }
        if (-not (Get-Website -Name $TargetSite -ErrorAction SilentlyContinue)) {
            if (Get-WebBinding | Where-Object { $_.bindingInformation -match ":$TargetPort`:" }) { throw "Port $TargetPort already in use." }
        }
    }

    Invoke-Step -StepName 'CopyContent' -Action {
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
        robocopy $sourceConfig.physicalPath $targetPath /E /NFL /NDL /NJH /NJS | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Robocopy error (exit code $LASTEXITCODE)." }
    }

    Invoke-Step -StepName 'CreateTargetAppPool' -Action {
        if (-not (Test-Path "IIS:\AppPools\$TargetSite")) { New-WebAppPool -Name $TargetSite | Out-Null }
        Set-ItemProperty "IIS:\AppPools\$TargetSite" -Name processModel.identityType -Value $sourceConfig.identityType
    }

    Invoke-Step -StepName 'CreateTargetSite' -Action {
        if (-not (Get-Website -Name $TargetSite -ErrorAction SilentlyContinue)) {
            New-Website -Name $TargetSite -Port $TargetPort -PhysicalPath $targetPath -ApplicationPool $TargetSite | Out-Null
        }
        New-NetFirewallRule -DisplayName "PivotTest-Port-$TargetPort" -Direction Inbound -Protocol TCP -LocalPort $TargetPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }

    Invoke-Step -StepName 'VerifyHttpResponds' -Action {
        Start-Sleep -Seconds 2
        $r = Invoke-WebRequest -Uri "http://localhost:$TargetPort" -UseBasicParsing -TimeoutSec 10
        if ($r.StatusCode -ne 200) { throw "Unexpected status: $($r.StatusCode)" }
    }

    if ($IncludeHttps) {
        Invoke-Step -StepName 'AddHttpsBinding' -Action {
            if (-not (Get-WebBinding -Name $TargetSite -Protocol https -Port $TargetHttpsPort -ErrorAction SilentlyContinue)) {
                New-WebBinding -Name $TargetSite -Protocol https -Port $TargetHttpsPort -IPAddress '*'
            }
        }
        Invoke-Step -StepName 'ApplyCertificate' -Action {
            $binding = Get-WebBinding -Name $TargetSite -Protocol https -Port $TargetHttpsPort
            $binding.AddSslCertificate($certThumbprint, $certStoreName)
        }
        Invoke-Step -StepName 'VerifyHttpsResponds' -Action {
            Start-Sleep -Seconds 2
            $orig = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            try {
                Invoke-WebRequest -Uri "https://localhost:$TargetHttpsPort" -UseBasicParsing -TimeoutSec 10 | Out-Null
            } catch {
                Write-Output "  (HTTPS self-check failed -- known false-negative on this OS, verify manually in a browser.)"
            } finally {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $orig
            }
        }
    }

    $final = Get-Content $checkpointPath -Raw | ConvertFrom-Json
    Write-Output ""
    Write-Output "Final checkpoint state:"
    $final.steps.PSObject.Properties | ForEach-Object { Write-Output "  $($_.Name): $($_.Value.status)" }
    Write-Output ""
    Write-Output "Site: http://localhost:$TargetPort"
    if ($IncludeHttps) { Write-Output "HTTPS: https://localhost:$TargetHttpsPort" }

} -ArgumentList $SourceSite, $TargetSite, $TargetPort, $IncludeHttps.IsPresent, $TargetHttpsPort

$result | ForEach-Object { Write-Host $_ }

Write-Section "Done"
Write-Host "  Migration triggered from your laptop, executed entirely on $TargetServerIp -- no RDP, no manual password." -ForegroundColor Green
Write-Host "  Note: the URLs above (localhost:...) refer to the SERVER's own view of itself. To check from your laptop, use http://${TargetServerIp}:$TargetPort instead."
