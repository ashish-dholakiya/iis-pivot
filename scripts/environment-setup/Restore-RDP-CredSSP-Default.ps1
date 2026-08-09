<#
  Restore-RDP-CredSSP-Default.ps1

  RUN THIS ON: your own computer, once the Windows Server VM has
  finished Windows Update and RDP is connecting fine.

  WHAT IT DOES: puts the Encryption Oracle Remediation setting back to
  its secure default ("Force Updated Clients"), undoing
  Fix-RDP-CredSSP-Error.ps1.

  HOW TO RUN: same as before — right-click -> "Run with PowerShell",
  allow the admin prompt.
#>

#Requires -RunAsAdministrator

$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters'

if (Test-Path $regPath) {
    Remove-ItemProperty -Path $regPath -Name 'AllowEncryptionOracle' -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Done. This computer is back to the secure default (Force Updated Clients)." -ForegroundColor Green
} else {
    Write-Host "Nothing to restore — the setting wasn't set." -ForegroundColor Green
}
