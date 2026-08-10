<#
  StorageAssessment.psm1

  IIS PIVOT -- Storage assessment / sizing.

  WHY THIS EXISTS:
  Design reference §5: "Storage assessment before anything else runs.
  The tool inventories and sizes the source server's content before
  any backup or copy starts... This is a hard gate, not an
  afterthought." Also: "Client data folders are excluded by default...
  only copied when explicitly opted in, after the size is shown to
  the operator."

  This module does the measuring half of that requirement. It never
  copies anything, never asks for an opt-in decision itself -- it
  only inventories and reports sizes, so that whatever asks for the
  opt-in decision (a future Robocopy execution script) has real
  numbers to show before asking.

  THREE THINGS THIS MEASURES, KEPT SEPARATE (per project decision):
    1. Configuration (sites, bindings, pools, certs) -- NOT measured
       here at all. That's always included, never optional, and it's
       tiny (JSON, not files) -- no sizing question applies to it.
    2. Each site's own content folder (e.g. wwwroot-equivalent) --
       optional to copy, measured per-site so the operator can choose
       per-site if they want.
    3. Client data folder(s) (multi-tenant customer data, separate
       from site content -- e.g. the practice environment's
       ClientA/B/C folders under C:\PivotTestClientData or
       D:\PivotTestClientData) -- optional to copy, measured
       separately from site content, its own opt-in.

  RUN THIS ON: your laptop (this is a module, imported by other
  scripts -- it does nothing on its own).
#>

$ErrorActionPreference = 'Stop'

function Format-ByteSize {
    <#
      Turns a raw byte count into a human-readable string (KB/MB/GB),
      since a non-technical operator reading an assessment report
      needs "2.3 GB", not "2469396480".
    #>
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-RemoteFolderSize {
    <#
      Measures a folder's total size ON THE SERVER, over the same
      remote connection every other script uses -- never copies
      anything, purely read-only (Get-ChildItem + Measure-Object).
      Returns $null if the path doesn't exist on the server, rather
      than throwing, so callers can treat "not present" as a normal,
      expected case (e.g. no client data folder on this server).
    #>
    param(
        [Parameter(Mandatory)][string]$ServerIp,
        [Parameter(Mandatory)]$Credential,
        [Parameter(Mandatory)][string]$Path
    )

    $result = Invoke-Command -ComputerName $ServerIp -Credential $Credential -ScriptBlock {
        param($TargetPath)
        # IIS often stores paths like "%SystemDrive%\inetpub\wwwroot" literally
        # -- PowerShell does NOT auto-expand % variables in a plain string (that's
        # cmd.exe behavior, not native PowerShell), so this must be done explicitly
        # or paths like the Default Web Site's will incorrectly show as "not found".
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($TargetPath)
        if (-not (Test-Path $expandedPath)) {
            return $null
        }
        $files = Get-ChildItem -Path $expandedPath -Recurse -File -ErrorAction SilentlyContinue
        $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
        if (-not $totalBytes) { $totalBytes = 0 }
        [ordered]@{
            path       = $expandedPath
            fileCount  = $files.Count
            totalBytes = [long]$totalBytes
        }
    } -ArgumentList $Path

    return $result
}

function Get-SiteContentSizes {
    <#
      Measures every given site's physical content folder, one at a
      time, on the server. $Sites is expected in the same shape other
      scripts already produce (.name, .physicalPath).
    #>
    param(
        [Parameter(Mandatory)][string]$ServerIp,
        [Parameter(Mandatory)]$Credential,
        [Parameter(Mandatory)]$Sites
    )

    $results = @()
    foreach ($site in $Sites) {
        $sizeInfo = Get-RemoteFolderSize -ServerIp $ServerIp -Credential $Credential -Path $site.physicalPath
        if ($null -eq $sizeInfo) {
            $results += [ordered]@{
                siteName   = $site.name
                path       = $site.physicalPath
                found      = $false
                fileCount  = 0
                totalBytes = 0
                display    = "(path not found on server)"
            }
        } else {
            $results += [ordered]@{
                siteName   = $site.name
                path       = $sizeInfo.path
                found      = $true
                fileCount  = $sizeInfo.fileCount
                totalBytes = $sizeInfo.totalBytes
                display    = Format-ByteSize -Bytes $sizeInfo.totalBytes
            }
        }
    }
    return $results
}

function Get-ClientDataAssessment {
    <#
      Looks for the client data folder in the two conventional
      locations this project has used (D: preferred, C: fallback --
      matching Setup-PracticeServer.ps1's own convention), and
      measures it if found. Returns found=$false (not an error) if
      neither location has one -- plenty of real servers won't have a
      separate client-data area at all.
    #>
    param(
        [Parameter(Mandatory)][string]$ServerIp,
        [Parameter(Mandatory)]$Credential
    )

    $candidatePaths = @('D:\PivotTestClientData', 'C:\PivotTestClientData')

    foreach ($path in $candidatePaths) {
        $sizeInfo = Get-RemoteFolderSize -ServerIp $ServerIp -Credential $Credential -Path $path
        if ($null -ne $sizeInfo) {
            return [ordered]@{
                found      = $true
                path       = $sizeInfo.path
                fileCount  = $sizeInfo.fileCount
                totalBytes = $sizeInfo.totalBytes
                display    = Format-ByteSize -Bytes $sizeInfo.totalBytes
            }
        }
    }

    return [ordered]@{
        found      = $false
        path       = $null
        fileCount  = 0
        totalBytes = 0
        display    = "(no client data folder found at either conventional location)"
    }
}

function Get-StorageAssessmentReport {
    <#
      The main entry point: runs both assessments (site content,
      client data) and returns one combined report object, plus a
      grand total, ready to be displayed to the operator BEFORE any
      opt-in decision is asked -- exactly the order the design
      reference requires.
    #>
    param(
        [Parameter(Mandatory)][string]$ServerIp,
        [Parameter(Mandatory)]$Credential,
        [Parameter(Mandatory)]$Sites
    )

    $siteResults  = Get-SiteContentSizes -ServerIp $ServerIp -Credential $Credential -Sites $Sites
    $clientData   = Get-ClientDataAssessment -ServerIp $ServerIp -Credential $Credential

    # NOTE: deliberately NOT using Measure-Object -Property here. $siteResults is
    # an array of [ordered] hashtables, and Measure-Object -Property does not
    # reliably sum hashtable keys the way it does real object properties (this
    # silently returned 0 during testing) -- a plain manual loop is used instead.
    $siteTotalBytes = 0
    foreach ($s in $siteResults) { $siteTotalBytes += $s.totalBytes }

    return [ordered]@{
        generatedAt          = (Get-Date).ToString("o")
        serverIp             = $ServerIp
        sites                = $siteResults
        siteContentTotalBytes = [long]$siteTotalBytes
        siteContentTotalDisplay = Format-ByteSize -Bytes $siteTotalBytes
        clientData           = $clientData
    }
}

Export-ModuleMember -Function Format-ByteSize, Get-RemoteFolderSize, Get-SiteContentSizes, Get-ClientDataAssessment, Get-StorageAssessmentReport
