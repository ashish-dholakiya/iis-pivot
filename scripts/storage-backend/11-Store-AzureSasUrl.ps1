<#
  11-Store-AzureSasUrl.ps1

  IIS PIVOT -- store the Azure Blob container SAS URL securely.

  RUN THIS ON: your laptop.
#>

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
Import-Module Microsoft.PowerShell.SecretStore -ErrorAction Stop

$secretName = 'IISPivot-AzureBlobSasUrl'

Write-Host ""
Write-Host "The vault may ask for its master password first -- enter that if prompted." -ForegroundColor Cyan
Write-Host "Then paste the full Blob SAS URL when asked (visible while pasting -- stays local only)." -ForegroundColor Cyan
Write-Host ""

try { Unlock-SecretStore } catch { }

$plainText = Read-Host -Prompt "Blob SAS URL"
$secureString = ConvertTo-SecureString -String $plainText -AsPlainText -Force
$plainText = $null

Set-Secret -Name $secretName -SecureStringSecret $secureString -Vault 'IISPivotVault'

Write-Host ""
Write-Host "Stored securely as '$secretName'." -ForegroundColor Green
