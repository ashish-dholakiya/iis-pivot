<#
  15-Test-SmokeTestSuite.ps1

  IIS PIVOT -- Proves SmokeTest.psm1 correctly detects whether each
  site on the practice server actually answers HTTP requests, not
  just whether IIS reports it as "Started".

  SAME SELF-DISCOVERING DESIGN AS SCRIPT 14:
  This script does NOT require you to know site names, ports, or
  anything else in advance. It connects to the server, asks IIS
  itself what sites exist and what state they're in, and tests
  whatever it finds. Nothing to look up or copy beforehand.

  WHAT IT DOES:
    1. Loads SmokeTest.psm1.
    2. Connects to the server and asks IIS for the current list of
       sites and their bindings (same read-only approach as
       01-Inspect-IIS.ps1 -- nothing on the server is touched or
       changed).
    3. Runs a real HTTP(S) request against every Started site's
       binding(s), from your laptop, over the network -- proving the
       site is actually reachable, not just that the IIS process is
       up.
    4. Prints a clear PASS/FAIL per site, plus a summary.

  RUN THIS ON: your laptop.

  REQUIRES: SmokeTest.psm1 in the same folder as this script.
            The 'IISPivot-PracticeServer' secret already stored in
            IISPivotVault (same one every other script uses).
            PowerShell 7 (for -SkipCertificateCheck support in
            Invoke-WebRequest).

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp   = '192.168.29.201'
$serverSecretName = 'IISPivot-PracticeServer'

Write-Section "Loading smoke test module"
Import-Module (Join-Path $PSScriptRoot 'SmokeTest.psm1') -Force
Write-Host "  SmokeTest.psm1 loaded." -ForegroundColor Green

Write-Section "Connecting to server and reading current site list"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$serverCred = Get-Secret -Name $serverSecretName -Vault 'IISPivotVault'
Write-Host "  Server credential retrieved for: $($serverCred.UserName)" -ForegroundColor Green

$sites = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
    Import-Module WebAdministration -ErrorAction Stop
    $allSites = Get-Website
    foreach ($site in $allSites) {
        $bindings = foreach ($b in $site.Bindings.Collection) {
            [ordered]@{
                protocol           = $b.Protocol
                bindingInformation = $b.BindingInformation
            }
        }
        [ordered]@{
            name     = $site.Name
            state    = [string]$site.State
            bindings = @($bindings)
        }
    }
}

if (-not $sites -or $sites.Count -eq 0) {
    Write-Host "  No sites found on the server at all. Nothing to smoke-test." -ForegroundColor Yellow
    return
}
Write-Host "  Found $($sites.Count) site(s) on the server:"
foreach ($s in $sites) {
    Write-Host "    - $($s.name)  [state: $($s.state)]"
}

Write-Section "Running smoke test against each Started site"
$results = Invoke-SmokeTestSuite -Sites $sites -ServerIp $targetServerIp

foreach ($r in $results) {
    Write-Host ""
    if ($r.skipped) {
        Write-Host "  $($r.siteName): SKIPPED -- $($r.reason)" -ForegroundColor Yellow
        continue
    }

    if ($r.overallPass) {
        Write-Host "  $($r.siteName): PASS" -ForegroundColor Green
    } else {
        Write-Host "  $($r.siteName): FAIL" -ForegroundColor Red
    }
    foreach ($ur in $r.urlResults) {
        if ($ur.success) {
            Write-Host "      $($ur.url)  -> responded, HTTP $($ur.statusCode)" -ForegroundColor DarkGray
        } else {
            Write-Host "      $($ur.url)  -> NO RESPONSE: $($ur.error)" -ForegroundColor Red
        }
    }
}

Write-Section "Summary"
$tested  = $results | Where-Object { -not $_.skipped }
$passed  = $tested  | Where-Object { $_.overallPass }
$failed  = $tested  | Where-Object { -not $_.overallPass }
$skipped = $results | Where-Object { $_.skipped }

Write-Host "  Sites tested : $($tested.Count)"
Write-Host "  Passed       : $($passed.Count)" -ForegroundColor Green
Write-Host "  Failed       : $($failed.Count)" -ForegroundColor $(if ($failed.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Skipped      : $($skipped.Count)"
Write-Host ""
Write-Host "  Send back this full console output."
