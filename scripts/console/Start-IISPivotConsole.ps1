#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$CertThumbprint  = "F26C8EE1E2DDBBB9161FE37B41D4D8993C1A5504"
$ConsolePort     = 47821
$ConsoleUsername = "pivot"
$ConsolePassword = "IISPivot@2026!"

$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $CertThumbprint }
if (-not $cert) { throw "Certificate not found." }
Write-Host "Certificate found: $($cert.Subject)" -ForegroundColor Green

function Get-IISPivotHtml {
    param([string]$Title, [string]$Body, [bool]$Authenticated = $false)
    $nav = if ($Authenticated) { "<nav><a href='/dashboard'>Dashboard</a><a href='/logout'>Sign out</a></nav>" } else { "" }
    return "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><title>$Title - IIS Pivot</title><style>*,*::before,*::after{box-sizing:border-box}body{margin:0;font-family:'Segoe UI',sans-serif;background:#f0f4f8;color:#1a202c;font-size:15px}header{background:#0b2340;color:#fff;padding:0 24px;height:52px;display:flex;align-items:center;justify-content:space-between}header .brand{font-weight:700;font-size:16px}header .phase-badge{font-size:10.5px;font-weight:700;text-transform:uppercase;letter-spacing:1px;background:#e8ab1f;color:#3a2800;padding:3px 10px;border-radius:20px}nav{display:flex;gap:20px}nav a{color:#cfe3f7;text-decoration:none;font-size:14px}main{padding:40px 32px;max-width:960px;margin:0 auto}h1{font-size:22px;color:#0b2340;margin:0 0 20px 0}.card{background:#fff;border:1px solid #dde6ee;border-radius:10px;padding:32px;max-width:380px;margin:60px auto 0}.card h2{font-size:18px;color:#0b2340;margin:0 0 6px 0}.card p{color:#5c6b78;font-size:13.5px;margin:0 0 24px 0}label{display:block;font-size:13px;font-weight:600;margin-bottom:5px}input{width:100%;padding:9px 12px;border:1px solid #cfd8e0;border-radius:6px;font-size:14px;margin-bottom:16px;background:#f9fafb}button{width:100%;padding:10px;background:#0b2340;color:#fff;border:none;border-radius:6px;font-size:14px;font-weight:600;cursor:pointer}.error-msg{background:#fdeaea;color:#a12c22;border:1px solid #f5c2c7;border-radius:6px;padding:9px 12px;font-size:13px;margin-bottom:16px}.stub-box{background:#fff;border:1px solid #dde6ee;border-radius:10px;padding:48px 32px;text-align:center;color:#7a8794}.stub-box p{margin:0;font-size:14px}</style></head><body><header><span class='brand'>IIS Pivot</span><span class='phase-badge'>Phase 1 - Internal Use Only</span>$nav</header><main>$Body</main></body></html>"
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

    Add-PodeRoute -Method Get -Path "/" -ScriptBlock {
        if ($WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/dashboard" }
        else { Move-PodeResponseUrl -Url "/login" }
    }

    Add-PodeRoute -Method Get -Path "/login" -ScriptBlock {
        $b = "<div class='card'><h2>Sign in</h2><p>IIS Pivot migration console</p><form method='POST' action='/login'><label>Username</label><input type='text' name='username' required><label>Password</label><input type='password' name='password' required><button type='submit'>Sign in</button></form></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "Sign in" -Body $b -Authenticated $false)
    }

    Add-PodeRoute -Method Post -Path "/login" -ScriptBlock {
        $u = $WebEvent.Data["username"]
        $p = $WebEvent.Data["password"]
        Write-Host "DEBUG: user=[$u] pass=[$p]" -ForegroundColor Yellow
        if ($u -eq "pivot" -and $p -eq "IISPivot@2026!") {
            $WebEvent.Session.Data.Authenticated = $true
            $WebEvent.Session.Data.Username = $u
            Move-PodeResponseUrl -Url "/dashboard"
        } else {
            $b = "<div class='card'><h2>Sign in</h2><p>IIS Pivot migration console</p><div class='error-msg'>Incorrect username or password.</div><form method='POST' action='/login'><label>Username</label><input type='text' name='username' required><label>Password</label><input type='password' name='password' required><button type='submit'>Sign in</button></form></div>"
            Write-PodeHtmlResponse -StatusCode 401 -Value (Get-IISPivotHtml -Title "Sign in" -Body $b -Authenticated $false)
        }
    }

    Add-PodeRoute -Method Get -Path "/dashboard" -ScriptBlock {
        if (-not $WebEvent.Session.Data.Authenticated) { Move-PodeResponseUrl -Url "/login"; return }
        $user = $WebEvent.Session.Data.Username
        $b = "<h1>Dashboard</h1><div class='stub-box'><p>Signed in as <strong>$user</strong> - console is running correctly.</p><p style='margin-top:8px;font-size:13px;'>Migration list will appear here in Sprint 2.</p></div>"
        Write-PodeHtmlResponse -Value (Get-IISPivotHtml -Title "Dashboard" -Body $b -Authenticated $true)
    }

    Add-PodeRoute -Method Get -Path "/logout" -ScriptBlock {
        $WebEvent.Session.Data.Authenticated = $false
        $WebEvent.Session.Data.Username = $null
        Remove-PodeSession
        Move-PodeResponseUrl -Url "/login"
    }

    Write-Host "Console ready." -ForegroundColor Green
    Write-Host "  https://localhost:47821" -ForegroundColor Cyan
    Write-Host "  https://192.168.29.69:47821" -ForegroundColor Cyan
}
