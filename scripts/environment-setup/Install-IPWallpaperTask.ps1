<#
  Install-IPWallpaperTask.ps1

  RUN THIS ON: the Windows Server VM, ONCE.

  WHAT IT DOES: sets up a Scheduled Task that runs
  Update-IPWallpaper.ps1 automatically — immediately, at every login,
  and every 5 minutes after that, forever. Once this is run one time,
  you never have to do anything again: the wallpaper keeps itself
  current on its own, even across reboots.

  BEFORE RUNNING: make sure Update-IPWallpaper.ps1 is saved in the
  SAME FOLDER as this script (e.g. both on the Desktop, or both in
  C:\PivotTools).

  HOW TO RUN:
    1. Right-click this file -> "Run with PowerShell"
       (allow the admin prompt if asked)
    2. That's it — the wallpaper will update within a few seconds and
       then keep itself current automatically from now on.
#>

#Requires -RunAsAdministrator

$scriptPath = Join-Path $PSScriptRoot 'Update-IPWallpaper.ps1'

if (-not (Test-Path $scriptPath)) {
    throw "Can't find Update-IPWallpaper.ps1 in the same folder as this script. Make sure both files are saved together, then try again."
}

$taskName = 'IIS Pivot - Update IP Wallpaper'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Trigger 1: run once at logon
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn

# Trigger 2: keep repeating every 5 minutes, for 10 years (effectively "forever" --
# Task Scheduler's XML format rejects TimeSpan.MaxValue as out of range)
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($logonTrigger, $repeatTrigger) `
    -Principal $principal -Settings $settings -Description 'Keeps the desktop wallpaper showing the current IP address for the IIS Pivot practice server.' | Out-Null

# Only report success if the task actually exists now
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Start-ScheduledTask -TaskName $taskName
    Write-Host ""
    Write-Host "Done. The wallpaper will update now, and automatically every 5 minutes from here on -- including after reboots." -ForegroundColor Green
    Write-Host "Give it about 10 seconds, then check your desktop background."
} else {
    Write-Host ""
    Write-Host "Something went wrong -- the task was not created. Scroll up to see the error above." -ForegroundColor Red
}
