<#
  StorageBackend.psm1

  IIS PIVOT -- Storage abstraction layer.

  WHY THIS EXISTS:
  Script 12 (12-Test-AzureBlobUpload-REST.ps1) proved the Azure Blob
  round trip works, but it did so with Azure-specific REST calls
  written directly into the test script. Every future piece of the
  tool that needs to save or load a backup would have had to
  duplicate that same Azure-specific code, and swapping in a
  different backend later (S3, local disk, on-prem NAS) would have
  meant rewriting every caller.

  This module fixes that: it exposes three backend-agnostic functions
  -- Save-Backup, Get-Backup, Test-StorageConnection -- and hides all
  backend-specific logic (Azure SAS URLs, REST headers, XML parsing,
  etc.) behind them. Callers never touch Azure REST details directly;
  they pass a $StorageConfig object and a blob/item name, and the
  module figures out which backend implementation to call.

  ADDING A NEW BACKEND LATER (S3, local disk, ...):
  Add a new private Save-Backup-<Backend>/Get-Backup-<Backend>/
  Test-StorageConnection-<Backend> function following the same
  pattern as the Azure ones below, then add one branch to the
  dispatch logic in each public function. No caller code changes.

  RUN THIS ON: your laptop (this is a module, imported by other
  scripts -- it does nothing on its own).

  REQUIRES: 11-Store-AzureSasUrl.ps1 already run successfully, so the
  'IISPivot-AzureBlobSasUrl' secret exists in the IISPivotVault.
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# =======================================================================
# Public interface
# =======================================================================

function New-StorageConfig {
    <#
      Builds the $StorageConfig object every other function in this
      module expects. Keeping construction in one place means adding a
      new backend later only means adding one new -Backend value here
      and one new set of required parameters.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Azure')]   # add 'S3', 'LocalDisk', etc. here as they're built
        [string]$Backend,

        [string]$SasSecretName = 'IISPivot-AzureBlobSasUrl',
        [string]$ContainerName = 'iis-pivot-test',
        [string]$VaultName     = 'IISPivotVault'
    )

    switch ($Backend) {
        'Azure' {
            return [ordered]@{
                backend        = 'Azure'
                sasSecretName  = $SasSecretName
                containerName  = $ContainerName
                vaultName      = $VaultName
            }
        }
    }
}

function Test-StorageConnection {
    <#
      Verifies the configured backend is reachable and usable, without
      uploading or downloading anything. Returns $true/$false rather
      than throwing, so callers can check connectivity as a pre-flight
      gate before starting a real backup.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StorageConfig
    )

    switch ($StorageConfig.backend) {
        'Azure' { return Test-StorageConnection-Azure -Config $StorageConfig }
        default { throw "Test-StorageConnection: unsupported backend '$($StorageConfig.backend)'." }
    }
}

function Save-Backup {
    <#
      Uploads $Content (a string -- typically JSON) to the configured
      backend under $Name. Returns the backend-specific identifier
      needed to retrieve it again later (for Azure, that's the blob
      name; kept as a return value rather than assumed, since other
      backends may generate their own identifiers).
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StorageConfig,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Content
    )

    switch ($StorageConfig.backend) {
        'Azure' { return Save-Backup-Azure -Config $StorageConfig -Name $Name -Content $Content }
        default { throw "Save-Backup: unsupported backend '$($StorageConfig.backend)'." }
    }
}

function Get-Backup {
    <#
      Downloads and returns the content previously saved under $Name.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StorageConfig,

        [Parameter(Mandatory)]
        [string]$Name
    )

    switch ($StorageConfig.backend) {
        'Azure' { return Get-Backup-Azure -Config $StorageConfig -Name $Name }
        default { throw "Get-Backup: unsupported backend '$($StorageConfig.backend)'." }
    }
}

function Get-BackupList {
    <#
      Lists everything currently stored in the backend/container. Not
      in the original design-doc trio, but needed by the round-trip
      test script (and by any future "pick a backup to restore" UI),
      so it's here rather than duplicated per-caller.
    #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$StorageConfig
    )

    switch ($StorageConfig.backend) {
        'Azure' { return Get-BackupList-Azure -Config $StorageConfig }
        default { throw "Get-BackupList: unsupported backend '$($StorageConfig.backend)'." }
    }
}

# =======================================================================
# Private: Azure Blob (REST-based, no Az module dependency) implementation
# =======================================================================

function Get-AzureContainerUrlParts {
    # Shared helper: pulls the SAS URL from the vault and splits it into
    # a container base URL + token, same logic script 12 used inline.
    param([System.Collections.IDictionary]$Config)

    $sasUrl = Get-Secret -Name $Config.sasSecretName -Vault $Config.vaultName -AsPlainText
    $sasParts = $sasUrl -split '\?', 2
    $accountOrContainerBase = $sasParts[0].TrimEnd('/')
    $sasToken = $sasParts[1]

    if ($accountOrContainerBase -notmatch "/$($Config.containerName)$") {
        $containerBaseUrl = "$accountOrContainerBase/$($Config.containerName)"
    } else {
        $containerBaseUrl = $accountOrContainerBase
    }

    return [ordered]@{
        containerBaseUrl = $containerBaseUrl
        sasToken          = $sasToken
    }
}

function Test-StorageConnection-Azure {
    param([System.Collections.IDictionary]$Config)

    try {
        Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
        $parts = Get-AzureContainerUrlParts -Config $Config
        $listUrl = "$($parts.containerBaseUrl)`?restype=container&comp=list&$($parts.sasToken)"
        Invoke-WebRequest -Uri $listUrl -Method GET -UseBasicParsing | Out-Null
        return $true
    } catch {
        Write-Host "  Test-StorageConnection-Azure failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Save-Backup-Azure {
    param(
        [System.Collections.IDictionary]$Config,
        [string]$Name,
        [string]$Content
    )

    $parts = Get-AzureContainerUrlParts -Config $Config
    $blobUrl = "$($parts.containerBaseUrl)/$Name`?$($parts.sasToken)"

    $uploadHeaders = @{
        'x-ms-blob-type' = 'BlockBlob'
        'x-ms-version'   = '2021-08-06'
    }
    Invoke-WebRequest -Uri $blobUrl -Method PUT -Headers $uploadHeaders -Body $Content -ContentType 'application/json' -UseBasicParsing | Out-Null

    return $Name   # the identifier needed to Get-Backup it back later
}

function Get-Backup-Azure {
    param(
        [System.Collections.IDictionary]$Config,
        [string]$Name
    )

    $parts = Get-AzureContainerUrlParts -Config $Config
    $blobUrl = "$($parts.containerBaseUrl)/$Name`?$($parts.sasToken)"

    $response = Invoke-WebRequest -Uri $blobUrl -Method GET -UseBasicParsing
    return $response.Content
}

function Get-BackupList-Azure {
    param([System.Collections.IDictionary]$Config)

    $parts = Get-AzureContainerUrlParts -Config $Config
    $listUrl = "$($parts.containerBaseUrl)`?restype=container&comp=list&$($parts.sasToken)"

    $listResponse = Invoke-WebRequest -Uri $listUrl -Method GET -UseBasicParsing
    $rawXmlContent = $listResponse.Content
    $xmlStartIndex = $rawXmlContent.IndexOf('<')
    if ($xmlStartIndex -gt 0) {
        $rawXmlContent = $rawXmlContent.Substring($xmlStartIndex)
    }
    [xml]$listXml = $rawXmlContent
    return @($listXml.EnumerationResults.Blobs.Blob | ForEach-Object { $_.Name })
}

Export-ModuleMember -Function New-StorageConfig, Test-StorageConnection, Save-Backup, Get-Backup, Get-BackupList
