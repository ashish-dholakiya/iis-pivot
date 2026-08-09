<#
  Update-IPWallpaper.ps1

  RUN THIS ON: the Windows Server VM.

  WHAT IT DOES: draws the server's hostname, current IP address, and
  last-updated time onto an image, and sets that image as the desktop
  wallpaper. Meant to be run automatically and repeatedly (see
  Install-IPWallpaperTask.ps1) so the wallpaper always shows the
  current IP, even after it changes or the server reboots.

  You normally do NOT need to run this file by hand — 
  Install-IPWallpaperTask.ps1 sets it up to run on its own.
#>

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# --- Get current IP (same logic as the console version) ---
$ip = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        $_.PrefixOrigin -in @('Dhcp', 'Manual') -and
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet'
    } |
    Select-Object -First 1 -ExpandProperty IPAddress

if (-not $ip) { $ip = '(no IP assigned yet)' }

$hostname  = $env:COMPUTERNAME
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# --- Build the wallpaper image ---
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp    = New-Object System.Drawing.Bitmap ($bounds.Width, $bounds.Height)
$g      = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAlias'

# Background
$g.Clear([System.Drawing.Color]::FromArgb(20, 24, 34))

# Fonts
$fontBig   = New-Object System.Drawing.Font('Segoe UI', 48, [System.Drawing.FontStyle]::Bold)
$fontSmall = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Regular)
$brushWhite = [System.Drawing.Brushes]::WhiteSmoke
$brushGreen = [System.Drawing.Brushes]::LightGreen
$brushGray  = [System.Drawing.Brushes]::Gray

$leftMargin = 60
$topStart   = $bounds.Height - 260

$g.DrawString("IIS Pivot Practice Server", $fontSmall, $brushGray, $leftMargin, $topStart)
$g.DrawString("IP: $ip", $fontBig, $brushGreen, $leftMargin, ($topStart + 30))
$g.DrawString("Host: $hostname   |   Last updated: $timestamp", $fontSmall, $brushWhite, $leftMargin, ($topStart + 120))

$g.Dispose()

# --- Save and apply as wallpaper ---
$wallpaperDir  = 'C:\PivotTools'
$wallpaperPath = Join-Path $wallpaperDir 'ip-wallpaper.bmp'
New-Item -Path $wallpaperDir -ItemType Directory -Force | Out-Null
$bmp.Save($wallpaperPath, [System.Drawing.Imaging.ImageFormat]::Bmp)
$bmp.Dispose()

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

# Wallpaper style: Fill (10), so it covers the whole screen regardless of resolution
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'
Set-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'

$SPI_SETDESKWALLPAPER = 20
$SPIF_UPDATEINIFILE   = 0x01
$SPIF_SENDCHANGE      = 0x02
[Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaperPath, ($SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)) | Out-Null
