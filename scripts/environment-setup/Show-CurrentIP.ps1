<#
  Show-CurrentIP.ps1

  RUN THIS ON: the Windows Server VM (not your laptop).

  WHAT IT DOES: opens a window that always shows the server's current
  IPv4 address, refreshing every 15 seconds. Leave this window open on
  the desktop so you can glance at it any time — handy since your
  router assigns the IP automatically and it can change.

  HOW TO RUN:
    1. Save this file to the server's Desktop.
    2. Right-click it -> "Run with PowerShell"
    3. A window opens and stays open, showing the IP. Leave it running.

  TO MAKE IT START AUTOMATICALLY EVERY TIME THE SERVER BOOTS/LOGS IN:
    1. Press Windows key + R, type: shell:startup, press Enter
       (this opens the Startup folder)
    2. Right-click inside that folder -> New -> Shortcut
    3. For the location, paste this (adjust the path if you saved the
       script somewhere other than the Desktop):

       powershell.exe -ExecutionPolicy Bypass -WindowStyle Normal -File "C:\Users\Administrator\Desktop\Show-CurrentIP.ps1"

    4. Name the shortcut anything, e.g. "Current IP", click Finish.
    Now it will open automatically every time you log into the server.
#>

$Host.UI.RawUI.WindowTitle = "IIS Pivot Practice Server - Current IP"

while ($true) {
    Clear-Host

    # Grab active, non-loopback, non-virtual-switch IPv4 addresses.
    # (Excludes VirtualBox's internal loopback-style adapters so you
    # only see the address your router actually assigned.)
    $ips = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -ne '127.0.0.1' -and
            $_.PrefixOrigin -in @('Dhcp', 'Manual') -and
            $_.InterfaceAlias -notmatch 'Loopback|vEthernet'
        } |
        Select-Object -ExpandProperty IPAddress

    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "  IIS PIVOT PRACTICE SERVER - CURRENT IP" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Hostname: $env:COMPUTERNAME"
    Write-Host ""

    if ($ips) {
        foreach ($ip in $ips) {
            Write-Host "  IP Address: $ip" -ForegroundColor Green -BackgroundColor Black
        }
    } else {
        Write-Host "  No network adapter with an IP found yet..." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Last checked: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""
    Write-Host "  (Refreshes every 15 seconds. Leave this window open. Press Ctrl+C to stop.)" -ForegroundColor DarkGray

    Start-Sleep -Seconds 15
}
