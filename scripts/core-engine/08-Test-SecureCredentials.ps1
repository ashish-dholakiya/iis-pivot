<#
  08-Test-SecureCredentials.ps1

  IIS PIVOT -- Piece #10 (secure credential storage)

  WHAT IT DOES: stores the server's credential securely using
  Microsoft.PowerShell.SecretStore (already installed earlier), then
  retrieves it automatically and uses it for a real WinRM command --
  proving future runs don't need Get-Credential typed in manually.

  RUN THIS ON: your laptop (the connecting/jumpbox side) -- NOT the
  server. This stores the credential used to REACH the server.

  SECURITY NOTE: SecretStore encrypts what it stores using a vault
  password you set on first use. This is meaningfully more secure than
  typing a password into a script or leaving it in plain text, but it
  is still a convenience store on a single machine -- fine for this
  practice/testing phase, not a substitute for the proper secrets
  management the design doc requires before wider use.

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp = '192.168.29.201'   # update if your server's IP has changed -- check the wallpaper
$secretName     = 'IISPivot-PracticeServer'

Write-Section "Checking SecretStore vault"

Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop

$vaultRegistered = Get-SecretVault -Name 'IISPivotVault' -ErrorAction SilentlyContinue
if (-not $vaultRegistered) {
    Write-Host "  Registering a new local secret vault..." -ForegroundColor Yellow
    Register-SecretVault -Name 'IISPivotVault' -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
    Write-Host "  Vault registered." -ForegroundColor Green
} else {
    Write-Host "  Vault already registered." -ForegroundColor Green
}

Write-Section "Storing the server credential (one-time)"

$existingSecret = Get-SecretInfo -Name $secretName -Vault 'IISPivotVault' -ErrorAction SilentlyContinue
if ($existingSecret) {
    Write-Host "  A credential is already stored for '$secretName'." -ForegroundColor Green
    Write-Host "  (To replace it with a different one, run: Remove-Secret -Name '$secretName' -Vault 'IISPivotVault', then re-run this script.)"
} else {
    Write-Host "  No credential stored yet -- you'll be prompted once now."
    Write-Host "  Username format: <SERVER-COMPUTERNAME>\Administrator (e.g. WIN-5T3OHIUJ7II\Administrator)"
    $cred = Get-Credential -Message "Enter the server's Administrator credential (one-time -- stored securely after this)"
    Set-Secret -Name $secretName -Secret $cred -Vault 'IISPivotVault'
    Write-Host "  Credential stored securely." -ForegroundColor Green
}

Write-Section "Retrieving the stored credential automatically (no prompt)"

$retrievedCred = Get-Secret -Name $secretName -Vault 'IISPivotVault'
Write-Host "  Retrieved credential for user: $($retrievedCred.UserName)" -ForegroundColor Green

Write-Section "Using it for a real remote command (no manual password entry)"

try {
    $result = Invoke-Command -ComputerName $targetServerIp -Credential $retrievedCred -ScriptBlock {
        Get-Website | Select-Object Name, State
    }
    $result | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "  SUCCESS -- remote command ran using the stored credential, no password typed this run." -ForegroundColor Green
} catch {
    Write-Host "  FAILED -- $($_.Exception.Message)" -ForegroundColor Red
}

Write-Section "Summary"
Write-Host "  If you saw the site list above with no Get-Credential prompt just now, secure credential storage is working."
Write-Host "  The vault itself is protected by a master password you may have been asked to set on first use -- keep that safe, it's not stored anywhere recoverable."
Write-Host "  Send back this full console output."
