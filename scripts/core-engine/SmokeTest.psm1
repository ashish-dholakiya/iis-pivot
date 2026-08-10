<#
  SmokeTest.psm1

  IIS PIVOT -- Per-site smoke test.

  WHY THIS EXISTS:
  Up to now, "did the restore work" has only ever meant "did IIS
  start without an error" -- which is not the same as "does each site
  actually serve a page." A site can show as State=Started in IIS
  while still being broken (wrong physical path, missing app pool,
  bad binding, etc.) and nothing existing would catch that.

  This module fixes that: it takes a list of sites (as returned by
  Get-Website on the server) and sends a real HTTP request to each
  one's binding, checking that something actually answers -- not
  just that the IIS process is up.

  RUN THIS ON: your laptop (this is a module, imported by other
  scripts -- it does nothing on its own).
#>

$ErrorActionPreference = 'Stop'

function Get-SiteTestUrls {
    <#
      Turns a site's raw IIS bindings into testable URLs. IIS binding
      strings look like "*:8081:" or "*:8444:sitename.local" -- this
      pulls out the protocol, port, and (if present) hostname, and
      builds a URL using the server's IP address (since the practice
      VM's bindings use "*" rather than a specific hostname most of
      the time).
    #>
    param(
        [Parameter(Mandatory)]
        $Site,

        [Parameter(Mandatory)]
        [string]$ServerIp
    )

    $urls = @()
    foreach ($binding in $Site.bindings) {
        # bindingInformation format: "ipOrStar:port:hostheader"
        $parts = $binding.bindingInformation -split ':'
        if ($parts.Count -lt 2) { continue }
        $port = $parts[1]
        $hostHeader = if ($parts.Count -ge 3 -and $parts[2]) { $parts[2] } else { $null }

        $protocol = $binding.protocol
        if ($protocol -notin @('http', 'https')) { continue }   # skip net.tcp, net.pipe, etc.

        $urls += "$protocol`://$ServerIp`:$port/"
    }
    return $urls
}

function Test-SiteSmoke {
    <#
      Sends a single HTTP(S) request to $Url and reports whether
      something answered. "Success" here means the server responded
      at all with a status code (even a 403/404 counts as "answered"
      -- the point is proving the site is reachable and IIS is
      actually routing to it, not judging whether the content itself
      is correct). Self-signed certs (HTTPS test sites) are allowed
      through without validation, since the practice environment uses
      one deliberately.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [int]$TimeoutSec = 10
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec $TimeoutSec -SkipCertificateCheck -UseBasicParsing
        return [ordered]@{
            url        = $Url
            success    = $true
            statusCode = [int]$response.StatusCode
            error      = $null
        }
    } catch [System.Net.WebException], [Microsoft.PowerShell.Commands.HttpResponseException] {
        # Even an HTTP error response (4xx/5xx) proves the site answered --
        # only a connection-level failure (below) should count as "down".
        if ($_.Exception.Response) {
            return [ordered]@{
                url        = $Url
                success    = $true
                statusCode = [int]$_.Exception.Response.StatusCode
                error      = $null
            }
        }
        return [ordered]@{
            url        = $Url
            success    = $false
            statusCode = $null
            error      = $_.Exception.Message
        }
    } catch {
        return [ordered]@{
            url        = $Url
            success    = $false
            statusCode = $null
            error      = $_.Exception.Message
        }
    }
}

function Invoke-SmokeTestSuite {
    <#
      Runs Test-SiteSmoke against every started site's bindings.
      $Sites is expected in the same shape 01-Inspect-IIS.ps1 and the
      other scripts already produce: an array of objects with at
      least .name, .state, and .bindings (each with .protocol and
      .bindingInformation).

      Returns an array of per-site results, each with the site name,
      every URL tested, and whether the site as a whole passed (all
      its tested URLs answered) or failed (at least one did not).
    #>
    param(
        [Parameter(Mandatory)]
        $Sites,

        [Parameter(Mandatory)]
        [string]$ServerIp,

        [int]$TimeoutSec = 10
    )

    $results = @()

    foreach ($site in $Sites) {
        if ($site.state -ne 'Started') {
            $results += [ordered]@{
                siteName    = $site.name
                skipped     = $true
                reason      = "Site state is '$($site.state)', not 'Started' -- not tested."
                urlResults  = @()
                overallPass = $null
            }
            continue
        }

        $urls = Get-SiteTestUrls -Site $site -ServerIp $ServerIp
        if ($urls.Count -eq 0) {
            $results += [ordered]@{
                siteName    = $site.name
                skipped     = $true
                reason      = "No testable http/https bindings found."
                urlResults  = @()
                overallPass = $null
            }
            continue
        }

        $urlResults = foreach ($url in $urls) {
            Test-SiteSmoke -Url $url -TimeoutSec $TimeoutSec
        }

        $results += [ordered]@{
            siteName    = $site.name
            skipped     = $false
            reason      = $null
            urlResults  = $urlResults
            overallPass = -not ($urlResults | Where-Object { -not $_.success })
        }
    }

    return $results
}

Export-ModuleMember -Function Get-SiteTestUrls, Test-SiteSmoke, Invoke-SmokeTestSuite
