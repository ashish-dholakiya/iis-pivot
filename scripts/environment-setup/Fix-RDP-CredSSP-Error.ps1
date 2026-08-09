<#
  Fix-RDP-CredSSP-Error.ps1

  RUN THIS ON: your own computer (the one you use to connect via Remote
  Desktop). NOT on the Windows Server VM.

  WHAT IT DOES: temporarily relaxes the "Encryption Oracle Remediation"
  security check so your PC will tolerate connecting to an unpatched
  Windows Server VM. This is the same setting Group Policy Editor
  (gpedit.msc) would change — this script does it without needing
  gpedit, which isn't available on Windows Home editions.

  IMPORTANT: This is a TEMPORARY workaround. Once the server has
  finished Windows Update, run Restore-RDP-CredSSP-Default.ps1 to put
  this setting back to its secure default.

  HOW TO RUN:
    1. Right-click this file -> "Run with PowerShell"
       (if that option doesn't appear: open PowerShell, type
        Set-ExecutionPolicy -Scope Process Bypass -Force
        then run:  .\Fix-RDP-CredSSP-Error.ps1 )
    2. If Windows asks "Do you want to allow this app to make changes
       to your device?" click Yes.
    3. Try your Remote Desktop connection again afterward.
#>

#Requires -RunAsAdministrator

$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters'

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# 0 = Force Updated Clients (secure default)
# 1 = Mitigated
# 2 = Vulnerable  <-- allows connecting to unpatched servers (temporary use only)
Set-ItemProperty -Path $regPath -Name 'AllowEncryptionOracle' -Value 2 -Type DWord

Write-Host ""
Write-Host "Done. This setting has been temporarily relaxed on THIS computer." -ForegroundColor Green
Write-Host "Try your Remote Desktop connection again now."
Write-Host ""
Write-Host "Reminder: once the server finishes Windows Update, run" -ForegroundColor Yellow
Write-Host "Restore-RDP-CredSSP-Default.ps1 on this same computer to put this back to secure." -ForegroundColor Yellow
