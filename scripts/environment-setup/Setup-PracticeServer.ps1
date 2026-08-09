#Requires -RunAsAdministrator
<#
.SYNOPSIS
    IIS Pivot -- Practice Server Provisioning Script

.DESCRIPTION
    Prepares a FRESH, THROWAWAY Windows Server 2016 evaluation VM so it has
    everything needed to test IIS Pivot pieces against, per the project's
    human-in-the-loop testing methodology (design doc Section 11).

    This script is NOT part of IIS Pivot itself. It is test-fixture scaffolding:
    it installs IIS + supporting dependencies, then creates a handful of
    dummy sites, app pools, and "client data" folders so there is something
    realistic to migrate/inspect during testing.

    Safe to re-run -- every step checks current state before acting.

.NOTES
    Run this ONLY on the disposable practice/evaluation VM.
    Never run this against a production server.

    Author context: prepared for the Sr. Full-Stack / IIS Pivot dev team.
    See companion doc: Practice-Server-Setup-Guide.md
#>

[CmdletBinding()]
param(
    # Skip PowerShell 7 install if you'd rather test purely against the
    # PS 5.1 floor the design doc specifies as the minimum target baseline.
    [switch]$SkipPowerShell7,

    # Skip seeding test sites/data -- useful if you only want the raw
    # IIS + dependency install and will seed data separately.
    [switch]$SkipTestData
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # keeps Invoke-WebRequest fast

# Windows Server 2016 defaults to old TLS settings, and PowerShell 5.1 does
# not automatically negotiate TLS 1.2 for web requests. Most Microsoft
# download endpoints now require it -- without this line, PowerShell 7
# install and PSGallery module installs below fail with an SSL/TLS error.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Write-Section($title) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor DarkGray }
function Write-Warn2($msg){ Write-Host "  [WARN] $msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
Write-Section "0. Environment sanity check"
# ---------------------------------------------------------------------------

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "  OS: $($os.Caption) (Build $($os.BuildNumber))"
Write-Host "  PowerShell: $($PSVersionTable.PSVersion)"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run from an elevated (Administrator) PowerShell session."
}
Write-Ok "Running elevated."

# ---------------------------------------------------------------------------
Write-Section "1. IIS role + sub-features"
# ---------------------------------------------------------------------------

# Feature set chosen to cover what IIS Pivot needs to inspect/migrate:
# static content, ASP.NET app pools, management tools/console (for
# WebAdministration + IISAdministration modules), scripting tools,
# common auth providers, health/logging, and WebSockets (used by the
# jumpbox console design and handy to have on a realistic test site).
$iisFeatures = @(
    'Web-Server'
    'Web-Common-Http'
    'Web-Default-Doc'
    'Web-Dir-Browsing'
    'Web-Http-Errors'
    'Web-Static-Content'
    'Web-Http-Logging'
    'Web-Log-Libraries'
    'Web-Request-Monitor'
    'Web-Http-Tracing'
    'Web-Security'
    'Web-Filtering'
    'Web-Basic-Auth'
    'Web-Windows-Auth'
    'Web-App-Dev'
    'Web-Net-Ext45'
    'Web-Asp-Net45'
    'Web-ISAPI-Ext'
    'Web-ISAPI-Filter'
    'Web-WebSockets'
    'Web-Mgmt-Tools'
    'Web-Mgmt-Console'
    'Web-Mgmt-Compat'
    'Web-Metabase'
    'Web-Scripting-Tools'
    'Web-Mgmt-Service'
)

$result = Install-WindowsFeature -Name $iisFeatures -IncludeManagementTools
if ($result.RestartNeeded -eq 'Yes') {
    Write-Warn2 "A restart is required after this run. Re-run the script after rebooting to continue."
}
Write-Ok "IIS role + $($iisFeatures.Count) sub-features installed (or already present)."

# Enable remote management via WMSvc (useful for later Web Deploy testing)
Set-Service -Name WMSVC -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name WMSVC -ErrorAction SilentlyContinue
Write-Ok "Web Management Service (WMSvc) set to automatic."

# ---------------------------------------------------------------------------
Write-Section "2. .NET Framework check"
# ---------------------------------------------------------------------------

# ASP.NET 4.x features above pull in .NET Framework as a dependency, but
# confirm explicitly since app pool identity / config work depends on it.
$netRelease = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
if ($netRelease -ge 461808) {
    Write-Ok ".NET Framework 4.7.2+ present (release $netRelease)."
} else {
    Write-Warn2 ".NET Framework 4.7.2+ not detected (release=$netRelease). Install the latest .NET Framework from https://dotnet.microsoft.com/download/dotnet-framework before continuing -- Web Deploy and modern ASP.NET features need it."
}

# ---------------------------------------------------------------------------
Write-Section "3. PowerShell 7+ (optional but recommended)"
# ---------------------------------------------------------------------------

if ($SkipPowerShell7) {
    Write-Skip "PowerShell 7 install skipped (-SkipPowerShell7)."
}
elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
    Write-Skip "PowerShell 7 already installed: $(pwsh -v)"
}
else {
    Write-Host "  Installing PowerShell 7 via Microsoft's official install script..."
    # Official Microsoft-hosted installer, documented at:
    # https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows
    & ([scriptblock]::Create((Invoke-RestMethod https://aka.ms/install-powershell.ps1))) -UseMSI -Quiet
    Write-Ok "PowerShell 7 installed. (Target-server baseline per design is still PS 5.1 -- this is for convenience/testing parity with the jumpbox, which does require PS7.)"
}

# ---------------------------------------------------------------------------
Write-Section "4. IIS PowerShell modules"
# ---------------------------------------------------------------------------

# WebAdministration ships automatically with Web-Mgmt-Tools/Web-Scripting-Tools
# above -- just confirm it's importable.
if (Get-Module -ListAvailable -Name WebAdministration) {
    Write-Ok "WebAdministration module present."
} else {
    Write-Warn2 "WebAdministration module not found even after installing management tools -- check the Web-Scripting-Tools feature installed correctly."
}

# IISAdministration is the newer, cross-platform-friendly module. Needs
# internet access to PSGallery.
try {
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap | Out-Null
    }
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

    if (-not (Get-Module -ListAvailable -Name IISAdministration)) {
        Install-Module -Name IISAdministration -Force -Scope AllUsers -AllowClobber
        Write-Ok "IISAdministration module installed."
    } else {
        Write-Skip "IISAdministration module already installed."
    }
}
catch {
    Write-Warn2 "Could not install IISAdministration from PSGallery (no internet on this VM?). WebAdministration alone is enough for the first test scripts. Error: $($_.Exception.Message)"
}

# SecretManagement / SecretStore -- not needed for today's read-only test,
# but it's the credential-storage control called out in the design doc
# (Section 7), so getting it in place now saves a round trip later.
try {
    foreach ($mod in @('Microsoft.PowerShell.SecretManagement', 'Microsoft.PowerShell.SecretStore')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Install-Module -Name $mod -Force -Scope AllUsers -AllowClobber
            Write-Ok "$mod installed."
        } else {
            Write-Skip "$mod already installed."
        }
    }
}
catch {
    Write-Warn2 "Could not install SecretManagement modules (no internet?). Not required for the first test piece -- safe to install later. Error: $($_.Exception.Message)"
}

# ---------------------------------------------------------------------------
Write-Section "5. Web Deploy (msdeploy)"
# ---------------------------------------------------------------------------

$webDeployInstalled = Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy'
if ($webDeployInstalled) {
    Write-Ok "Web Deploy already installed."
} else {
    Write-Warn2 "Web Deploy is NOT installed. Microsoft doesn't provide a single stable direct-download link for the MSI (it moves between releases), so this step is manual:"
    Write-Host "    1. Go to https://www.microsoft.com/en-us/download/details.aspx?id=106070 (or search 'Web Deploy' on microsoft.com/download)"
    Write-Host "    2. Download WebDeploy_amd64_en-US.msi"
    Write-Host "    3. Run it, choose 'Complete' setup (not 'Typical' -- Typical skips the server components IIS Pivot needs)"
    Write-Host "    4. Re-run this script afterward to confirm detection"
}

# ---------------------------------------------------------------------------
Write-Section "6. Seed test sites, app pools, and data"
# ---------------------------------------------------------------------------

if ($SkipTestData) {
    Write-Skip "Test data seeding skipped (-SkipTestData)."
}
else {
    Import-Module WebAdministration -ErrorAction Stop

    $siteRoot = 'C:\PivotTestSites'   # deliberately NOT under C:\inetpub, and never touches C:\ as a "storage" location -- just local site content
    New-Item -Path $siteRoot -ItemType Directory -Force | Out-Null

    # --- Three test sites on distinct ports, each with a distinguishable
    #     app pool identity type, to exercise the app-pool-identity
    #     restoration path the design doc flags as a Web Deploy gap.
    $testSites = @(
        @{ Name = 'PivotTest-Alpha'; Port = 8081; PoolIdentity = 'ApplicationPoolIdentity' }
        @{ Name = 'PivotTest-Beta';  Port = 8082; PoolIdentity = 'NetworkService' }
        @{ Name = 'PivotTest-Gamma'; Port = 8083; PoolIdentity = 'LocalService' }
    )

    foreach ($site in $testSites) {
        $sitePath = Join-Path $siteRoot $site.Name
        New-Item -Path $sitePath -ItemType Directory -Force | Out-Null

        $html = @"
<!DOCTYPE html>
<html><head><title>$($site.Name)</title></head>
<body>
  <h1>$($site.Name)</h1>
  <p>IIS Pivot practice-server test site. Port $($site.Port). Seeded $(Get-Date -Format o).</p>
</body></html>
"@
        Set-Content -Path (Join-Path $sitePath 'index.html') -Value $html -Encoding UTF8

        # App pool
        if (-not (Test-Path "IIS:\AppPools\$($site.Name)")) {
            New-WebAppPool -Name $site.Name | Out-Null
        }
        Set-ItemProperty "IIS:\AppPools\$($site.Name)" -Name processModel.identityType -Value $site.PoolIdentity

        # Site
        if (-not (Get-Website -Name $site.Name -ErrorAction SilentlyContinue)) {
            New-Website -Name $site.Name -Port $site.Port -PhysicalPath $sitePath -ApplicationPool $site.Name | Out-Null
        } else {
            Set-ItemProperty "IIS:\Sites\$($site.Name)" -Name physicalPath -Value $sitePath
        }

        Write-Ok "Site '$($site.Name)' on port $($site.Port), pool identity '$($site.PoolIdentity)'."
    }

    # --- Self-signed cert + HTTPS binding on one site, to exercise the
    #     certificate migration path.
    $certSite = 'PivotTest-Alpha'
    $existingCert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -eq 'CN=pivottest.local' } | Select-Object -First 1
    if (-not $existingCert) {
        $existingCert = New-SelfSignedCertificate -DnsName 'pivottest.local' -CertStoreLocation Cert:\LocalMachine\My -FriendlyName 'IIS Pivot Test Cert'
        Write-Ok "Self-signed test certificate created (CN=pivottest.local)."
    } else {
        Write-Skip "Self-signed test certificate already exists."
    }

    $httpsBindingExists = Get-WebBinding -Name $certSite -Protocol https -ErrorAction SilentlyContinue
    if (-not $httpsBindingExists) {
        New-WebBinding -Name $certSite -Protocol https -Port 8444 -IPAddress '*'
        $binding = Get-WebBinding -Name $certSite -Protocol https
        $binding.AddSslCertificate($existingCert.Thumbprint, 'My')
        Write-Ok "HTTPS binding (port 8444) added to '$certSite' using the test certificate."
    } else {
        Write-Skip "HTTPS binding already present on '$certSite'."
    }

    # --- Dummy "client data" folders -- simulate the multi-tenant client
    #     data the design doc says is excluded from migration by default
    #     (Section 5). A few small placeholder files, not real bulk data -- the
    #     point is to prove the exclusion/opt-in logic sees them, not to
    #     actually move gigabytes on a test VM.
    $clientDataRoot = 'D:\PivotTestClientData'
    $dDriveWritable = $false
    if (Test-Path 'D:\') {
        try {
            $testFile = 'D:\pivot-write-test.tmp'
            [IO.File]::WriteAllText($testFile, 'test')
            Remove-Item $testFile -Force
            $dDriveWritable = $true
        } catch {
            $dDriveWritable = $false
        }
    }
    if (-not $dDriveWritable) {
        Write-Warn2 "D:\ is not writable (it's commonly the VM's virtual DVD/ISO drive, not a real disk) -- using C:\PivotTestClientData instead. (Design doc requires client data/storage staging never live on C:\ in real use; this practice-VM fallback is fine for a read-only inventory test, just don't treat it as a real target path pattern.)"
        $clientDataRoot = 'C:\PivotTestClientData'
    }
    foreach ($client in @('ClientA', 'ClientB', 'ClientC')) {
        $clientPath = Join-Path $clientDataRoot $client
        New-Item -Path $clientPath -ItemType Directory -Force | Out-Null
        1..3 | ForEach-Object {
            Set-Content -Path (Join-Path $clientPath "sample-file-$_.txt") -Value ("Sample client data for $client, file $_.") -Encoding UTF8
        }
    }
    Write-Ok "Dummy client-data folders created under $clientDataRoot (ClientA/B/C, 3 sample files each)."

    # --- Firewall rules for the test ports, so the sites are actually reachable.
    foreach ($port in ($testSites.Port + 8444)) {
        $ruleName = "PivotTest-Port-$port"
        if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        }
    }
    Write-Ok "Firewall rules opened for test site ports."
}

# ---------------------------------------------------------------------------
Write-Section "Summary"
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Practice server provisioning complete." -ForegroundColor Cyan
Write-Host "Reboot if a restart was flagged above, then re-run this script once more to confirm everything reports [OK]/[SKIP] with no [WARN]."
Write-Host ""
Write-Host "Next step: run the read-only IIS-visibility check script against this server and report the output back."
