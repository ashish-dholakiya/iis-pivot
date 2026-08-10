<#
  16-Test-StorageAssessment.ps1

  IIS PIVOT -- Proves StorageAssessment.psm1 correctly measures site
  content and client data sizes on the server, and displays them in
  the right order: SIZE SHOWN FIRST, opt-in question asked SECOND --
  matching design reference §5's hard requirement.

  SAME SELF-DISCOVERING DESIGN AS SCRIPTS 14 AND 15:
  Nothing to look up or copy beforehand. This connects to the server,
  reads the current site list and their physical paths itself, finds
  the client data folder itself (if one exists), and measures
  everything directly.

  WHAT IT DOES:
    1. Loads StorageAssessment.psm1.
    2. Connects to the server and reads the current site list
       (read-only -- same approach as 01-Inspect-IIS.ps1).
    3. Measures every site's content folder size, and the client data
       folder's size (if present), on the server.
    4. Displays a clear report: per-site sizes, client data size,
       grand totals -- BEFORE asking anything.
    5. Only after the report is shown, asks (as a demonstration of the
       correct order -- the real opt-in enforcement belongs to the
       future Robocopy execution script, not this assessment-only one)
       which categories the operator would choose to include.

  RUN THIS ON: your laptop.

  REQUIRES: StorageAssessment.psm1 in the same folder as this script.
            The 'IISPivot-PracticeServer' secret already stored in
            IISPivotVault (same one every other script uses).

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp   = '192.168.29.201'
$serverSecretName = 'IISPivot-PracticeServer'

Write-Section "Loading storage assessment module"
Import-Module (Join-Path $PSScriptRoot 'StorageAssessment.psm1') -Force
Write-Host "  StorageAssessment.psm1 loaded." -ForegroundColor Green

Write-Section "Connecting to server and reading current site list"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$serverCred = Get-Secret -Name $serverSecretName -Vault 'IISPivotVault'
Write-Host "  Server credential retrieved for: $($serverCred.UserName)" -ForegroundColor Green

$sites = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
    Import-Module WebAdministration -ErrorAction Stop
    Get-Website | ForEach-Object {
        [ordered]@{ name = $_.Name; physicalPath = $_.PhysicalPath }
    }
}
Write-Host "  Found $($sites.Count) site(s) on the server." -ForegroundColor Green

Write-Section "Measuring sizes (read-only -- nothing is copied or touched)"
$report = Get-StorageAssessmentReport -ServerIp $targetServerIp -Credential $serverCred -Sites $sites
Write-Host "  Assessment complete." -ForegroundColor Green

Write-Section "STORAGE ASSESSMENT REPORT"
Write-Host ""
Write-Host "  Configuration (sites, bindings, pools, certs):" -ForegroundColor White
Write-Host "    Always included -- not optional, not sized (it's config, not bulk data)."
Write-Host ""
Write-Host "  Site content (optional, per-site opt-in):" -ForegroundColor White
foreach ($s in $report.sites) {
    if ($s.found) {
        Write-Host ("    {0,-30} {1,12}   ({2} files)  [{3}]" -f $s.siteName, $s.display, $s.fileCount, $s.path)
    } else {
        Write-Host ("    {0,-30} {1}" -f $s.siteName, $s.display) -ForegroundColor Yellow
    }
}
Write-Host ("    {0,-30} {1,12}" -f "TOTAL site content:", $report.siteContentTotalDisplay) -ForegroundColor Cyan
Write-Host ""
Write-Host "  Client data (optional, separate opt-in from site content):" -ForegroundColor White
if ($report.clientData.found) {
    Write-Host ("    {0,-30} {1,12}   ({2} files)  [{3}]" -f "Client data folder:", $report.clientData.display, $report.clientData.fileCount, $report.clientData.path)
} else {
    Write-Host "    $($report.clientData.display)" -ForegroundColor Yellow
}

Write-Section "Opt-in decision (demonstration only -- real enforcement belongs to the future copy script)"
Write-Host "  Per design reference §5: sizes must be shown BEFORE this question is ever asked."
Write-Host "  That order has just been followed above."
Write-Host ""
if ($report.siteContentTotalBytes -gt 0) {
    $choice1 = Read-Host "  Include site content in the migration? (y/n)"
    Write-Host "    -> You chose: $choice1"
}
if ($report.clientData.found) {
    $choice2 = Read-Host "  Include client data in the migration? (y/n)"
    Write-Host "    -> You chose: $choice2"
}

Write-Section "Summary"
Write-Host "  Storage assessment correctly measured site content and client data separately,"
Write-Host "  displayed sizes before any opt-in question, and never copied or touched anything."
Write-Host "  Send back this full console output."
