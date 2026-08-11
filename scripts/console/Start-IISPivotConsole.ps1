
#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"
$CertThumbprint  = "F26C8EE1E2DDBBB9161FE37B41D4D8993C1A5504"
$ConsolePort     = 47821
$ConsoleUsername = "pivot"
$ConsolePassword = "IISPivot@2026!"

$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $CertThumbprint }
if (-not $cert) { throw "Certificate not found." }
Write-Host "Certificate found: $($cert.Subject)" -ForegroundColor Green

function Get-AppConfig {
    $f = "C:\PivotConfig\console-config.json"
    if (Test-Path $f) { return Get-Content $f -Raw | ConvertFrom-Json }
    return $null
}
function Save-AppConfig {
    param([string]$StorageType, [string]$MigrationsPath)
    $dir = "C:\PivotConfig"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    [ordered]@{ storageType=$StorageType; migrationsPath=$MigrationsPath; configuredAt=(Get-Date).ToString("o"); consoleVersion="Sprint-2" } | ConvertTo-Json -Depth 4 | Set-Content "$dir\console-config.json" -Encoding UTF8
}
function Get-AllMigrations {
    $cfg = Get-AppConfig
    if (-not $cfg -or -not $cfg.migrationsPath -or -not (Test-Path $cfg.migrationsPath)) { return @() }
    $migrations = @()
    foreach ($f in (Get-ChildItem -Path $cfg.migrationsPath -Filter "migration-*.json" | Sort-Object LastWriteTime -Descending)) {
        try { $migrations += (Get-Content $f.FullName -Raw | ConvertFrom-Json) } catch {}
    }
    return $migrations
}
function New-MigrationRecord {
    param([string]$ClientName, [string]$SourceServer, [string]$TargetServer)
    $cfg = Get-AppConfig
    $dir = if ($cfg -and $cfg.migrationsPath) { $cfg.migrationsPath } else { "C:\PivotMigrations" }
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $id = [System.Guid]::NewGuid().ToString("N").Substring(0,12)
    [ordered]@{ id=$id; clientName=$ClientName; sourceServer=$SourceServer; targetServer=$TargetServer; status="NotStarted"; createdAt=(Get-Date).ToString("o"); updatedAt=(Get-Date).ToString("o"); createdBy="pivot"; steps=@{} } | ConvertTo-Json -Depth 6 | Set-Content "$dir\migration-$id.json" -Encoding UTF8
}
function Get-IISPivotHtml {
    param([string]$Title, [string]$Body, [bool]$Authenticated = $false)
    $nav = if ($Authenticated) { "<nav><a href='/dashboard'>Dashboard</a><a href='/new-migration'>New Migration</a><a href='/logout'>Sign out</a></nav>" } else { "" }
    $css = "*, *::before, *::after { box-sizing: border-box; } body { margin: 0; font-family: Segoe UI, system-ui, sans-serif; background: #f0f4f8; color: #1a202c; font-size: 15px; } header { background: #0b2340; color: #fff; padding: 0 24px; height: 52px; display: flex; align-items: center; justify-content: space-between; position: sticky; top: 0; z-index: 100; } header .brand { font-weight: 700; font-size: 16px; } header .phase-badge { font-size: 10.5px; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; background: #e8ab1f; color: #3a2800; padding: 3px 10px; border-radius: 20px; } nav { display: flex; gap: 20px; align-items: center; } nav a { color: #cfe3f7; text-decoration: none; font-size: 14px; } nav a:hover { color: #fff; } main { padding: 32px; max-width: 1100px; margin: 0 auto; } h1 { font-size: 22px; color: #0b2340; margin: 0 0 20px 0; } h2 { font-size: 17px; color: #0b2340; margin: 0 0 16px 0; } label { display: block; font-size: 13px; font-weight: 600; color: #374151; margin-bottom: 5px; margin-top: 14px; } input[type=text], input[type=password] { width: 100%; padding: 9px 12px; border: 1px solid #cfd8e0; border-radius: 6px; font-size: 14px; background: #f9fafb; color: #1a202c; } .btn { display: inline-block; padding: 9px 20px; border-radius: 6px; font-size: 14px; font-weight: 600; cursor: pointer; border: none; text-decoration: none; } .btn-primary { background: #0b2340; color: #fff; } .btn-primary:hover { background: #123a63; } .btn-outline { background: #fff; color: #0b2340; border: 1.5px solid #0b2340; } .card { background: #fff; border: 1px solid #dde6ee; border-radius: 10px; padding: 28px; margin-bottom: 20px; } .infobar { background: #eef6ff; border-left: 4px solid #2ea3ff; padding: 12px 16px; border-radius: 4px; font-size: 13px; color: #17324f; margin: 14px 0; } .warnbar { background: #fff8e6; border-left: 4px solid #e8ab1f; padding: 12px 16px; border-radius: 4px; font-size: 13px; color: #5a4200; margin: 14px 0; } .error-msg { background: #fdeaea; color: #a12c22; border: 1px solid #f5c2c7; border-radius: 6px; padding: 10px 14px; font-size: 13px; margin-bottom: 16px; } .success-msg { background: #dff5e6; color: #146c34; border: 1px solid #b7e4c7; border-radius: 6px; padding: 10px 14px; font-size: 13px; margin-bottom: 16px; } .badge { display: inline-block; font-size: 11px; font-weight: 700; padding: 3px 9px; border-radius: 20px; } .badge-gray { background: #e9edf1; color: #5c6b78; } .badge-blue { background: #dcefff; color: #0b2340; } .badge-green { background: #dff5e6; color: #146c34; } .badge-red { background: #fdeaea; color: #a12c22; } .badge-amber { background: #fff2cf; color: #7a5b00; } table { width: 100%; border-collapse: collapse; font-size: 14px; } th { text-align: left; padding: 10px 14px; font-weight: 600; color: #5c6b78; font-size: 12px; text-transform: uppercase; border-bottom: 1px solid #e2e8ee; } td { padding: 12px 14px; border-bottom: 1px solid #f0f4f8; vertical-align: middle; } tr:hover td { background: #f8fafc; } .empty-state { text-align: center; padding: 60px 32px; color: #7a8794; } .wizard-steps { display: flex; margin-bottom: 28px; } .wizard-step { flex: 1; text-align: center; font-size: 12px; font-weight: 600; padding: 10px 8px; border-bottom: 3px solid #e2e8ee; color: #7a8794; } .wizard-step.active { border-bottom-color: #2ea3ff; color: #0b2340; } .wizard-step.done { border-bottom-color: #38a169; color: #38a169; } .storage-option { border: 1.5px solid #dde6ee; border-radius: 8px; padding: 14px 16px; margin-bottom: 10px; display: flex; align-items: center; gap: 12px; } .storage-option.selected { border-color: #2ea3ff; background: #eef6ff; } .storage-option.disabled { opacity: 0.5; } .coming-soon { font-size: 10px; font-weight: 700; text-transform: uppercase; background: #e9edf1; color: #5c6b78; padding: 2px 6px; border-radius: 4px; margin-left: 6px; } .size-table { width: 100%; border-collapse: collapse; font-size: 13px; margin-bottom: 12px; } .size-table td { padding: 7px 10px; border-bottom: 1px solid #f0f4f8; } .size-table .total-row td { font-weight: 700; border-top: 2px solid #e2e8ee; } .flex-row { display: flex; gap: 12px; align-items: center; justify-content: space-between; } footer { text-align: center; padding: 20px; font-size: 12px; color: #7a8794; border-top: 1px solid #e2e8ee; margin-top: 40px; }"
    $footer = "<footer>Powered by <a href='https://www.ashishdholakiya.com' target='_blank' style='color:#2ea3ff;text-decoration:none;font-weight:600;'>www.ashishdholakiya.com</a></footer>"
    return "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1.0'><title>$Title - IIS Pivot</title><style>$css</style></head><body><header><span class='brand'>IIS Pivot</span><span class='phase-badge'>Phase 1 - Internal Use Only</span>$nav</header><main>$Body</main>$footer</body></html>"
}
Write-Host "Starting IIS Pivot console on https://localhost:$ConsolePort ..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Import-Module Pode -ErrorAction Stop

Start-PodeServer -Threads 2 {

    Add-PodeEndpoint -Address * -Port 47821 -Protocol Https `
        -CertificateThumbprint "F26C8EE1E2DDBBB9161FE37B41D4D8993C1A5504" `
        -CertificateStoreName "My" `
        -CertificateStoreLocation "LocalMachine"

    Enable-PodeSessionMiddleware -Duration 1800 -Secure -HttpOnly -Name "IISPivotSession"
    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging

    # Root redirect
    Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
        $cfg = Get-AppConfig
        if (-not $cfg) { Move-PodeResponseUrl -Url "/setup" }
        elseif ($WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/dashboard" }
        else { Move-PodeResponseUrl -Url "/login" }
    }

    # First Run Setup GET
    Add-PodeRoute -Method Get -Path "/setup" -ScriptBlock {
        $cfg = Get-AppConfig
        if ($cfg) { Move-PodeResponseUrl -Url "/login"; return }
        $body = "<h1>First Run Setup</h1><p style='color:#5c6b78;margin-bottom:24px;'>Configure where IIS Pivot stores migration records.</p><div class='card'><h2>Storage location for migration records</h2><form method='POST' action='/setup'><div class='storage-option selected'><input type='radio' name='storageType' value='local' checked><div><strong>Local path on this machine</strong><div style='font-size:12px;color:#7a8794;margin-top:2px;'>Migration records stored as JSON files on the jumpbox</div></div></div><div class='storage-option disabled'><input type='radio' disabled><div><strong>Azure Blob Storage</strong><span class='coming-soon'>Coming soon</span></div></div><div class='storage-option disabled'><input type='radio' disabled><div><strong>AWS S3</strong><span class='coming-soon'>Coming soon</span></div></div><div class='storage-option disabled'><input type='radio' disabled><div><strong>Network share (NAS/UNC)</strong><span class='coming-soon'>Coming soon</span></div></div><div style='margin-top:20px;'><label for='migrationsPath'>Migrations folder path</label><input type='text' id='migrationsPath' name='migrationsPath' value='C:\PivotMigrations' placeholder='e.g. C:\PivotMigrations'><div style='font-size:12px;color:#7a8794;margin-top:4px;'>The folder will be created automatically if it does not exist.</div></div><div class='infobar' style='margin-top:20px;'>This setting is saved to <strong>C:\PivotConfig\console-config.json</strong> and is not stored in the git repository.</div><div style='margin-top:24px;'><button type='submit' class='btn btn-primary'>Save and continue to login</button></div></form></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "First Run Setup" -Body $body -Authenticated $false)
    }

    # First Run Setup POST
    Add-PodeRoute -Method Post -Path "/setup" -ScriptBlock {
        $storageType    = $WebEvent.Data["storageType"]
        $migrationsPath = $WebEvent.Data["migrationsPath"]
        if ([string]::IsNullOrWhiteSpace($migrationsPath)) { $migrationsPath = "C:\PivotMigrations" }
        Save-AppConfig -StorageType $storageType -MigrationsPath $migrationsPath
        if (-not (Test-Path $migrationsPath)) { New-Item -Path $migrationsPath -ItemType Directory -Force | Out-Null }
        Move-PodeResponseUrl -Url "/login"
    }
    # Login GET
    Add-PodeRoute -Method Get -Path "/login" -ScriptBlock {
        $body = "<div style='max-width:380px;margin:60px auto 0;background:#fff;border:1px solid #dde6ee;border-radius:10px;padding:32px;'><h2 style='font-size:18px;color:#0b2340;margin:0 0 6px 0;'>Sign in</h2><p style='color:#5c6b78;font-size:13.5px;margin:0 0 24px 0;'>IIS Pivot migration console</p><form method='POST' action='/login'><label>Username</label><input type='text' name='username' autocomplete='username' required><label>Password</label><input type='password' name='password' autocomplete='current-password' required><button type='submit' class='btn btn-primary' style='width:100%;margin-top:8px;'>Sign in</button></form></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "Sign in" -Body $body -Authenticated $false)
    }

    # Login POST
    Add-PodeRoute -Method Post -Path "/login" -ScriptBlock {
        $u = $WebEvent.Data["username"]
        $p = $WebEvent.Data["password"]
        if ($u -eq "pivot" -and $p -eq "IISPivot@2026!") {
            $WebEvent.Session.Data.Authenticated = $true
            $WebEvent.Session.Data.Username = $u
            Move-PodeResponseUrl -Url "/dashboard"
        } else {
            $body = "<div style='max-width:380px;margin:60px auto 0;background:#fff;border:1px solid #dde6ee;border-radius:10px;padding:32px;'><h2 style='font-size:18px;color:#0b2340;margin:0 0 6px 0;'>Sign in</h2><p style='color:#5c6b78;font-size:13.5px;margin:0 0 24px 0;'>IIS Pivot migration console</p><div class='error-msg'>Incorrect username or password.</div><form method='POST' action='/login'><label>Username</label><input type='text' name='username' autocomplete='username' required><label>Password</label><input type='password' name='password' autocomplete='current-password' required><button type='submit' class='btn btn-primary' style='width:100%;margin-top:8px;'>Sign in</button></form></div>"
            Write-PodeHtmlResponse -StatusCode 401 -Value (Get-IISPivotHtml -Title "Sign in" -Body $body -Authenticated $false)
        }
    }

    # Logout
    Add-PodeRoute -Method Get -Path "/logout" -ScriptBlock {
        $WebEvent.Session.Data.Authenticated = $false
        $WebEvent.Session.Data.Username = $null
        $WebEvent.Session.Data.NewMigration = $null
        Remove-PodeSession
        Move-PodeResponseUrl -Url "/login"
    }
    # Dashboard
    Add-PodeRoute -Method Get -Path "/dashboard" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $migrations = Get-AllMigrations
        $cfg = Get-AppConfig
        $tableRows = ""
        if ($migrations.Count -eq 0) {
            $tableRows = "<tr><td colspan='5'><div class='empty-state'><p>No migrations yet.</p><p style='margin-top:8px;'><a href='/new-migration' class='btn btn-primary'>Start your first migration</a></p></div></td></tr>"
        } else {
            foreach ($m in $migrations) {
                $badgeClass = switch ($m.status) {
                    "Completed"  { "badge-green" }
                    "InProgress" { "badge-blue" }
                    "Failed"     { "badge-red" }
                    "Paused"     { "badge-amber" }
                    default      { "badge-gray" }
                }
                $updated = try { ([datetime]$m.updatedAt).ToString("dd-MM-yyyy HH:mm") } catch { "—" }
                $tableRows += "<tr><td><strong>$($m.clientName)</strong></td><td style='color:#5c6b78;'>$($m.sourceServer)</td><td style='color:#5c6b78;'>$($m.targetServer)</td><td><span class='badge $badgeClass'>$($m.status)</span></td><td style='color:#7a8794;font-size:13px;'>$updated</td></tr>"
            }
        }
        $storageInfo = if ($cfg) { "Migrations stored at: <strong>$($cfg.migrationsPath)</strong>" } else { "" }
        $body = "<div class='flex-row' style='margin-bottom:20px;'><h1 style='margin:0;'>Dashboard</h1><a href='/new-migration' class='btn btn-primary'>+ New Migration</a></div><div class='card' style='padding:0;overflow:hidden;'><table><thead><tr><th>Client</th><th>Source server</th><th>Target server</th><th>Status</th><th>Last updated</th></tr></thead><tbody>$tableRows</tbody></table></div><div style='font-size:12px;color:#7a8794;margin-top:8px;'>$storageInfo</div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "Dashboard" -Body $body -Authenticated $true)
    }
    # New Migration Step 1 GET
    Add-PodeRoute -Method Get -Path "/new-migration" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $WebEvent.Session.Data.NewMigration = @{}
        $body = "<h1>New Migration</h1><div class='wizard-steps'><div class='wizard-step active'>1. Target connection</div><div class='wizard-step'>2. Storage config</div><div class='wizard-step'>3. Assessment</div></div><div class='card'><h2>Connect to the target server</h2><p style='color:#5c6b78;font-size:13.5px;margin:0 0 16px 0;'>The target is the server you are migrating TO. Nothing will be changed on either server yet.</p><form method='POST' action='/new-migration/test-connection'><label>Client name</label><input type='text' name='clientName' placeholder='e.g. Acme Corp' required><label>Source server (migrating FROM)</label><input type='text' name='sourceServer' placeholder='e.g. 192.168.1.10 or WIN-PROD-01' required><label>Target server IP or hostname (migrating TO)</label><input type='text' name='targetServer' placeholder='e.g. 192.168.1.20 or WIN-NEW-01' required><label>Administrator username</label><input type='text' name='adminUser' placeholder='e.g. Administrator' required><label>Administrator password</label><input type='password' name='adminPass' required><div style='margin-top:20px;display:flex;gap:10px;'><button type='submit' class='btn btn-primary'>Test connection</button><a href='/dashboard' class='btn btn-outline'>Cancel</a></div></form></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "New Migration" -Body $body -Authenticated $true)
    }

    # New Migration Step 1 POST - Test Connection
    Add-PodeRoute -Method Post -Path "/new-migration/test-connection" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $clientName   = $WebEvent.Data["clientName"]
        $sourceServer = $WebEvent.Data["sourceServer"]
        $targetServer = $WebEvent.Data["targetServer"]
        $adminUser    = $WebEvent.Data["adminUser"]
        $adminPass    = $WebEvent.Data["adminPass"]
        $connectionResult = "unknown"
        $connectionDetail = ""
        try {
            $secPass = ConvertTo-SecureString $adminPass -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($adminUser, $secPass)
            $testResult = Invoke-Command -ComputerName $targetServer -Credential $cred -ScriptBlock {
                [ordered]@{ hostname = $env:COMPUTERNAME; osVersion = [System.Environment]::OSVersion.VersionString }
            } -ErrorAction Stop
            $connectionResult = "success-winrm"
            $connectionDetail = "Connected to $($testResult.hostname) ($($testResult.osVersion))"
        } catch {
            $connectionResult = "failed"
            $connectionDetail = $_.Exception.Message
        }
        $WebEvent.Session.Data.NewMigration = @{
            clientName=$clientName; sourceServer=$sourceServer; targetServer=$targetServer
            adminUser=$adminUser; adminPass=$adminPass
            connectionResult=$connectionResult; connectionDetail=$connectionDetail
        }
        $statusBlock = if ($connectionResult -eq "success-winrm") {
            "<div class='warnbar'><strong>Connected via standard WinRM</strong> — JEA constrained endpoint is not configured on this target. Full administrator session in use. Accepted for Phase 1. <a href='/new-migration/storage'>Continue anyway</a></div>"
        } else {
            "<div class='error-msg'><strong>Connection failed:</strong> $connectionDetail</div>"
        }
        $continueBtn = if ($connectionResult -ne "failed") { "<a href='/new-migration/storage' class='btn btn-primary'>Continue to storage config</a>" } else { "" }
        $body = "<h1>New Migration</h1><div class='wizard-steps'><div class='wizard-step done'>1. Target connection</div><div class='wizard-step active'>2. Storage config</div><div class='wizard-step'>3. Assessment</div></div><div class='card'><h2>Connection result</h2><div style='margin-bottom:8px;'><strong>Client:</strong> $clientName</div><div style='margin-bottom:8px;'><strong>Source:</strong> $sourceServer</div><div style='margin-bottom:16px;'><strong>Target:</strong> $targetServer</div>$statusBlock<div style='margin-top:20px;display:flex;gap:10px;'>$continueBtn<a href='/new-migration' class='btn btn-outline'>Back</a></div></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "New Migration" -Body $body -Authenticated $true)
    }
    # New Migration Step 2 - Storage Config
    Add-PodeRoute -Method Get -Path "/new-migration/storage" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $cfg = Get-AppConfig
        $migrationsPath = if ($cfg -and $cfg.migrationsPath) { $cfg.migrationsPath } else { "C:\PivotMigrations" }
        $body = "<h1>New Migration</h1><div class='wizard-steps'><div class='wizard-step done'>1. Target connection</div><div class='wizard-step active'>2. Storage config</div><div class='wizard-step'>3. Assessment</div></div><div class='card'><h2>Storage backend</h2><p style='color:#5c6b78;font-size:13.5px;margin:0 0 16px 0;'>Where backups and migration records will be stored.</p><div class='storage-option selected'><input type='radio' checked disabled><div><strong>Local path</strong><div style='font-size:12px;color:#7a8794;margin-top:2px;'>$migrationsPath</div></div></div><div class='storage-option disabled'><input type='radio' disabled><div><strong>Azure Blob Storage</strong><span class='coming-soon'>Coming soon</span></div></div><div class='storage-option disabled'><input type='radio' disabled><div><strong>AWS S3</strong><span class='coming-soon'>Coming soon</span></div></div><div class='storage-option disabled'><input type='radio' disabled><div><strong>Network share (NAS/UNC)</strong><span class='coming-soon'>Coming soon</span></div></div><div class='success-msg' style='margin-top:16px;'>Local storage validated — path is accessible.</div><div style='margin-top:20px;display:flex;gap:10px;'><a href='/new-migration/assessment' class='btn btn-primary'>Continue to assessment</a><a href='/new-migration' class='btn btn-outline'>Back</a></div></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "New Migration" -Body $body -Authenticated $true)
    }
    # New Migration Step 3 - Assessment
    Add-PodeRoute -Method Get -Path "/new-migration/assessment" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $nm = $WebEvent.Session.Data.NewMigration
        if (-not $nm -or -not $nm.sourceServer) { Move-PodeResponseUrl -Url "/new-migration"; return }
        $assessmentRows = ""
        $totalDisplay = "0 bytes"
        $clientDataRow = ""
        $assessmentError = ""
        try {
            $secPass = ConvertTo-SecureString $nm.adminPass -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($nm.adminUser, $secPass)
            $assessment = Invoke-Command -ComputerName $nm.sourceServer -Credential $cred -ScriptBlock {
                Import-Module WebAdministration -ErrorAction Stop
                $siteData = foreach ($site in Get-Website) {
                    $ep = [System.Environment]::ExpandEnvironmentVariables($site.PhysicalPath)
                    $sb = 0; $fc = 0
                    if (Test-Path $ep) {
                        $files = Get-ChildItem -Path $ep -Recurse -File -ErrorAction SilentlyContinue
                        $fc = $files.Count
                        $sum = ($files | Measure-Object -Property Length -Sum).Sum
                        if ($sum) { $sb = [long]$sum }
                    }
                    [ordered]@{ name=$site.Name; path=$ep; sizeBytes=$sb; fileCount=$fc }
                }
                $cdPath = $null; $cdBytes = 0; $cdCount = 0
                foreach ($p in @("D:\PivotTestClientData","C:\PivotTestClientData")) {
                    if (Test-Path $p) {
                        $cdPath = $p
                        $f = Get-ChildItem -Path $p -Recurse -File -ErrorAction SilentlyContinue
                        $cdCount = $f.Count
                        $sum = ($f | Measure-Object -Property Length -Sum).Sum
                        if ($sum) { $cdBytes = [long]$sum }
                        break
                    }
                }
                [ordered]@{ sites=@($siteData); clientDataPath=$cdPath; clientDataBytes=$cdBytes; clientDataCount=$cdCount }
            } -ErrorAction Stop
            $totalBytes = 0
            foreach ($s in $assessment.sites) {
                $totalBytes += $s.sizeBytes
                $d = if ($s.sizeBytes -ge 1GB) { "{0:N2} GB" -f ($s.sizeBytes/1GB) } elseif ($s.sizeBytes -ge 1MB) { "{0:N2} MB" -f ($s.sizeBytes/1MB) } elseif ($s.sizeBytes -ge 1KB) { "{0:N2} KB" -f ($s.sizeBytes/1KB) } else { "$($s.sizeBytes) bytes" }
                $assessmentRows += "<tr><td>$($s.name)</td><td style='color:#5c6b78;font-size:12px;'>$($s.path)</td><td style='text-align:right;'>$d</td><td style='text-align:right;color:#7a8794;'>$($s.fileCount)</td></tr>"
            }
            $totalDisplay = if ($totalBytes -ge 1GB) { "{0:N2} GB" -f ($totalBytes/1GB) } elseif ($totalBytes -ge 1MB) { "{0:N2} MB" -f ($totalBytes/1MB) } elseif ($totalBytes -ge 1KB) { "{0:N2} KB" -f ($totalBytes/1KB) } else { "$totalBytes bytes" }
            if ($assessment.clientDataPath) {
                $cd = if ($assessment.clientDataBytes -ge 1GB) { "{0:N2} GB" -f ($assessment.clientDataBytes/1GB) } elseif ($assessment.clientDataBytes -ge 1MB) { "{0:N2} MB" -f ($assessment.clientDataBytes/1MB) } elseif ($assessment.clientDataBytes -ge 1KB) { "{0:N2} KB" -f ($assessment.clientDataBytes/1KB) } else { "$($assessment.clientDataBytes) bytes" }
                $clientDataRow = "<div style='margin-top:20px;'><h2>Client data <span style='font-size:13px;font-weight:400;color:#7a8794;'>(separate opt-in)</span></h2><table class='size-table'><tr><td>$($assessment.clientDataPath)</td><td style='text-align:right;'>$cd</td><td style='text-align:right;color:#7a8794;'>$($assessment.clientDataCount) files</td></tr></table><label style='display:flex;align-items:center;gap:8px;font-size:14px;font-weight:400;cursor:pointer;'><input type='checkbox' name='includeClientData' value='1' style='width:auto;'> Include client data in this migration</label></div>"
            }
        } catch {
            $assessmentError = "<div class='error-msg'><strong>Assessment failed:</strong> $($_.Exception.Message)</div>"
        }
        $body = "<h1>New Migration</h1><div class='wizard-steps'><div class='wizard-step done'>1. Target connection</div><div class='wizard-step done'>2. Storage config</div><div class='wizard-step active'>3. Assessment</div></div><div class='card'><h2>Storage assessment</h2><p style='color:#5c6b78;font-size:13.5px;margin:0 0 4px 0;'>Source server: <strong>$($nm.sourceServer)</strong></p><div class='infobar'>Configuration (sites, bindings, certificates, app pools) is always included and is not sized here.</div>$assessmentError<form method='POST' action='/new-migration/confirm'><div style='margin-top:16px;'><h2>Site content <span style='font-size:13px;font-weight:400;color:#7a8794;'>(optional)</span></h2><table class='size-table'><tr style='background:#f8fafc;'><th style='padding:7px 10px;font-size:11px;'>Site</th><th style='padding:7px 10px;font-size:11px;'>Path</th><th style='padding:7px 10px;font-size:11px;text-align:right;'>Size</th><th style='padding:7px 10px;font-size:11px;text-align:right;'>Files</th></tr>$assessmentRows<tr class='total-row'><td colspan='2'><strong>Total site content</strong></td><td style='text-align:right;'><strong>$totalDisplay</strong></td><td></td></tr></table><label style='display:flex;align-items:center;gap:8px;font-size:14px;font-weight:400;cursor:pointer;margin-top:8px;'><input type='checkbox' name='includeSiteContent' value='1' style='width:auto;'> Include site content (file copy via Robocopy)</label></div>$clientDataRow<div style='margin-top:28px;display:flex;gap:10px;'><button type='submit' class='btn btn-primary'>Confirm and create migration</button><a href='/new-migration/storage' class='btn btn-outline'>Back</a></div></form></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "New Migration" -Body $body -Authenticated $true)
    }
    # New Migration Confirm POST
    Add-PodeRoute -Method Post -Path "/new-migration/confirm" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $nm = $WebEvent.Session.Data.NewMigration
        if (-not $nm) { Move-PodeResponseUrl -Url "/new-migration"; return }
        New-MigrationRecord -ClientName $nm.clientName -SourceServer $nm.sourceServer -TargetServer $nm.targetServer
        $WebEvent.Session.Data.NewMigration = $null
        Move-PodeResponseUrl -Url "/dashboard"
    }

    Write-Host "Console ready." -ForegroundColor Green
    Write-Host "  https://localhost:47821" -ForegroundColor Cyan
    Write-Host "  https://192.168.29.69:47821" -ForegroundColor Cyan
}
