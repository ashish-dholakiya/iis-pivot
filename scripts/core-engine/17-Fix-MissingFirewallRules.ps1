<#
  17-Fix-MissingFirewallRules.ps1

  IIS PIVOT -- Remediation for the firewall bug found by the smoke
  test (script 15): PivotTest-Delta-Clone and PivotTest-Alpha-Copy's
  HTTPS bindings had no matching firewall rule, so they worked when
  tested from the server itself (localhost bypasses the firewall
  entirely) but timed out from anywhere else on the network.

  ROOT CAUSE: 06-Migrate-Certificate.ps1 added new HTTPS bindings but
  never opened a firewall rule for the new port -- unlike
  05-Clone-Site.ps1, which does this correctly for HTTP ports. See
  06-Migrate-Certificate.ps1 for the going-forward fix; this script
  fixes what's ALREADY broken right now.

  SELF-DISCOVERING (same design as scripts 14-16): this does not
  assume which ports are affected. It reads every site's bindings
  from the server, checks each port against the server's actual
  firewall rules, and opens a rule for any port that's missing one --
  whether that's the two known-broken ports or something else
  entirely.

  SAFE: only ADDS inbound-allow firewall rules for ports that
  legitimate IIS site bindings are already using. Never removes or
  modifies an existing rule, never touches anything unrelated to site
  bindings.

  RUN THIS ON: your laptop.

  REQUIRES: The 'IISPivot-PracticeServer' secret already stored in
            IISPivotVault (same one every other script uses).

  WHAT TO REPORT BACK: the full console output. After this runs,
  re-run 15-Test-SmokeTestSuite.ps1 to confirm the previously-failing
  sites now pass.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp   = '192.168.29.201'
$serverSecretName = 'IISPivot-PracticeServer'

Write-Section "Connecting to server"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$serverCred = Get-Secret -Name $serverSecretName -Vault 'IISPivotVault'
Write-Host "  Server credential retrieved for: $($serverCred.UserName)" -ForegroundColor Green

Write-Section "Checking every site binding against the server's firewall rules"
$result = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
    Import-Module WebAdministration -ErrorAction Stop

    # Every port any site is actually bound to (http or https).
    $sites = Get-Website
    $boundPorts = foreach ($site in $sites) {
        foreach ($b in $site.Bindings.Collection) {
            if ($b.Protocol -in @('http', 'https')) {
                $parts = $b.bindingInformation -split ':'
                if ($parts.Count -ge 2 -and $parts[1] -match '^\d+$') {
                    [int]$parts[1]
                }
            }
        }
    }
    $boundPorts = $boundPorts | Sort-Object -Unique

    # Every port currently allowed inbound by an enabled firewall rule.
    $enabledAllowRules = Get-NetFirewallRule | Where-Object {
        $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow'
    }
    $openPorts = foreach ($rule in $enabledAllowRules) {
        $portFilter = $rule | Get-NetFirewallPortFilter
        if ($portFilter.Protocol -eq 'TCP' -and $portFilter.LocalPort -and $portFilter.LocalPort -ne 'Any') {
            $portFilter.LocalPort -split ',' | ForEach-Object { $_.Trim() }
        }
    }
    $openPorts = $openPorts | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Sort-Object -Unique

    $missingPorts = $boundPorts | Where-Object { $_ -notin $openPorts }

    $fixedPorts = @()
    foreach ($port in $missingPorts) {
        New-NetFirewallRule -DisplayName "PivotTest-Port-$port" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -ErrorAction Stop | Out-Null
        $fixedPorts += $port
    }

    [ordered]@{
        boundPorts   = @($boundPorts)
        openPorts    = @($openPorts)
        missingPorts = @($missingPorts)
        fixedPorts   = @($fixedPorts)
    }
}

Write-Host "  Ports any site is bound to      : $($result.boundPorts -join ', ')"
Write-Host "  Ports already allowed in firewall: $($result.openPorts -join ', ')"

if ($result.missingPorts.Count -eq 0) {
    Write-Host ""
    Write-Host "  No missing firewall rules found -- every bound port already has one. Nothing to fix." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  Ports that were MISSING a firewall rule: $($result.missingPorts -join ', ')" -ForegroundColor Yellow
    Write-Host "  Fixed (new inbound-allow rule added for): $($result.fixedPorts -join ', ')" -ForegroundColor Green
}

Write-Section "Summary"
Write-Host "  Firewall check complete. If any ports were fixed above, re-run"
Write-Host "  15-Test-SmokeTestSuite.ps1 now to confirm those sites pass over HTTPS/HTTP from the network."
Write-Host "  Send back this full console output."
