<#
  12-Test-AzureBlobUpload-REST.ps1

  IIS PIVOT -- Azure Blob test using plain web requests + a SAS URL,
  instead of the Az.Storage module (which had unresolvable version
  conflicts on this laptop).

  WHAT IT DOES:
    1. Pulls a fresh manifest from the server (remote, using the
       already-stored server credential).
    2. Uploads it directly to Azure Blob via a plain HTTP PUT request.
    3. Lists the container's contents via a plain HTTP GET request.
    4. Downloads the same blob back and verifies it matches exactly.

  RUN THIS ON: your laptop.

  REQUIRES: 11-Store-AzureSasUrl.ps1 already run successfully.

  WHAT TO REPORT BACK: the full console output.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

$targetServerIp   = '192.168.29.201'
$serverSecretName = 'IISPivot-PracticeServer'
$sasSecretName    = 'IISPivot-AzureBlobSasUrl'

Write-Section "Retrieving stored credentials"
Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
$serverCred = Get-Secret -Name $serverSecretName -Vault 'IISPivotVault'
$sasUrl     = Get-Secret -Name $sasSecretName -Vault 'IISPivotVault' -AsPlainText
Write-Host "  Server credential retrieved for: $($serverCred.UserName)" -ForegroundColor Green
Write-Host "  SAS URL retrieved." -ForegroundColor Green

# Split the SAS URL into its base address and its token (everything
# after the ?). Handles both container-level SAS URLs (already include
# the container name) and account-level SAS URLs (don't) by explicitly
# ensuring the container name is present in the base address.
$containerName = 'iis-pivot-test'
$sasParts   = $sasUrl -split '\?', 2
$accountOrContainerBase = $sasParts[0].TrimEnd('/')
$sasToken   = $sasParts[1]

if ($accountOrContainerBase -notmatch "/$containerName$") {
    $containerBaseUrl = "$accountOrContainerBase/$containerName"
} else {
    $containerBaseUrl = $accountOrContainerBase
}

Write-Section "Step 1: Generating a fresh manifest on the server (remote)"
$manifestJson = Invoke-Command -ComputerName $targetServerIp -Credential $serverCred -ScriptBlock {
    Import-Module WebAdministration -ErrorAction Stop
    $sites = Get-Website
    $siteExport = foreach ($site in $sites) {
        [ordered]@{ name = $site.Name; id = $site.ID; state = [string]$site.State; physicalPath = $site.PhysicalPath }
    }
    $manifest = [ordered]@{
        schemaVersion  = "0.1-blob-rest-test"
        exportedAt     = (Get-Date).ToString("o")
        sourceHostname = $env:COMPUTERNAME
        sites          = @($siteExport)
    }
    $manifest | ConvertTo-Json -Depth 6
}
Write-Host "  Retrieved manifest ($($manifestJson.Length) characters) from the server." -ForegroundColor Green

Write-Section "Step 2: Uploading to Azure Blob (direct HTTP PUT)"
$blobName = "iis-manifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$blobUrl  = "$containerBaseUrl/$blobName`?$sasToken"

$uploadHeaders = @{
    'x-ms-blob-type' = 'BlockBlob'
    'x-ms-version'   = '2021-08-06'
}
Invoke-WebRequest -Uri $blobUrl -Method PUT -Headers $uploadHeaders -Body $manifestJson -ContentType 'application/json' -UseBasicParsing | Out-Null
Write-Host "  Uploaded as blob: $blobName" -ForegroundColor Green

Write-Section "Step 3: Listing blobs in the container (direct HTTP GET)"
$listUrl = "$containerBaseUrl`?restype=container&comp=list&$sasToken"
$listResponse = Invoke-WebRequest -Uri $listUrl -Method GET -UseBasicParsing
$rawXmlContent = $listResponse.Content
$xmlStartIndex = $rawXmlContent.IndexOf('<')
if ($xmlStartIndex -gt 0) {
    $rawXmlContent = $rawXmlContent.Substring($xmlStartIndex)   # strip any garbled BOM/prefix characters before the actual XML
}
[xml]$listXml = $rawXmlContent
$blobNames = $listXml.EnumerationResults.Blobs.Blob | ForEach-Object { $_.Name }
Write-Host "  Blobs currently in container:"
$blobNames | ForEach-Object { Write-Host "    - $_" }

Write-Section "Step 4: Downloading it back and verifying integrity"
$downloadResponse = Invoke-WebRequest -Uri $blobUrl -Method GET -UseBasicParsing
$downloadedContent = $downloadResponse.Content

if ($manifestJson -eq $downloadedContent) {
    Write-Host "  MATCH -- downloaded content is identical to what was uploaded." -ForegroundColor Green
} else {
    Write-Host "  MISMATCH -- downloaded content differs. Needs investigation." -ForegroundColor Red
}

Write-Section "Summary"
Write-Host "  Full round trip tested via direct REST calls (no Az module needed): server -> Azure Blob -> verified."
Write-Host "  Send back this full console output."
