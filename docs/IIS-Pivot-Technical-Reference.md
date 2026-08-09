# IIS Pivot — Technical Reference

## Environment identifiers (verify these are still current before use)

| Item | Value | Notes |
|---|---|---|
| Server hostname | `WIN-5T3OHIUJ7II` | Windows Server 2016 Standard Evaluation, Desktop Experience |
| Server IP | `192.168.29.201` (as of last session) | DHCP-assigned, check server's desktop wallpaper for current value |
| WinRM username format | `WIN-5T3OHIUJ7II\Administrator` | Must be prefixed with computer name — no domain in this environment |
| Local SecretStore vault name | `IISPivotVault` | Lives on the person's laptop |
| Stored secret: server login | `IISPivot-PracticeServer` | PSCredential object |
| Stored secret: Azure SAS URL | `IISPivot-AzureBlobSasUrl` | The one actually used — see Azure section below |
| Stored secret: Azure connection string | `IISPivot-AzureBlobConnectionString` | Stored but **not used** — the Az.Storage module approach was abandoned, see below |
| Azure storage account | `iispivotpractice` | |
| Azure blob container | `iis-pivot-test` | |

## What's proven — 12 capabilities, all verified end-to-end

1. **Read-only IIS visibility** — sites, app pools, bindings via `WebAdministration`/`IISAdministration`
2. **JSON manifest export** — structured export including binding/cert info
3. **Deep config detail** — per-site authentication settings, app pool recycling/idle-timeout/start-mode
4. **Checkpoint engine** — records step status (`NotStarted`/`InProgress`/`Completed`/`Failed`) to a JSON file
5. **Real site creation** — first genuine IIS write, checkpointed, verified via actual HTTP request
6. **Config-driven clone** — reads a real site's config and recreates an equivalent one elsewhere
7. **Certificate/HTTPS binding migration** — carries a self-signed cert from one site's binding to another
8. **Remote execution via WinRM** — `Invoke-Command` from a laptop against the server, no RDP
9. **Checkpoint resume** — proven to skip completed steps and only retry what failed
10. **Secure credential storage** — `Microsoft.PowerShell.SecretManagement`/`SecretStore`, no more manual password entry
11. **Combined remote tool** — full migration triggered from the laptop, executed on the server, using stored credentials
12. **Azure Blob storage round-trip** — upload/list/download verified identical, via direct REST calls (see note below on why)

## Script inventory

## Quick reference: which machine each script runs on

**On THE SERVER** (via RDP or VirtualBox console): `Setup-PracticeServer.ps1`, `Show-CurrentIP.ps1`, `Update-IPWallpaper.ps1`, `Install-IPWallpaperTask.ps1`, `01-Inspect-IIS.ps1`, `02-Inspect-IIS-Detail.ps1`, `03-Checkpoint-Engine.ps1`, `04-Create-TestSite.ps1`, `05-Clone-Site.ps1`, `06-Migrate-Certificate.ps1`, `07-Test-CheckpointResume.ps1`, `IIS-Pivot-v0.1.ps1`

**On YOUR LAPTOP (jumpbox role)** — no RDP needed: `Fix-RDP-CredSSP-Error.ps1`, `Restore-RDP-CredSSP-Default.ps1`, `08-Test-SecureCredentials.ps1`, `IIS-Pivot-v0.2-Remote.ps1`, `11-Store-AzureSasUrl.ps1`, `12-Test-AzureBlobUpload-REST.ps1`

Rule of thumb: scripts dealing with credentials, secrets, or explicitly "remote" in the name are laptop/jumpbox-role tasks. Everything that directly touches IIS itself runs on the server.

All scripts are plain ASCII (verified — past corruption came from smart quotes/em-dashes surviving copy-paste badly). Location: these were delivered as downloadable files during the session; the person has been saving them locally (mostly `C:\Users\Administrator\Desktop` on the server, `C:\Users\ashis\Downloads` on the laptop).

### Environment setup (run once each)
| Script | Run on | Purpose |
|---|---|---|
| `Setup-PracticeServer.ps1` | Server | Installs IIS + dependencies, seeds test sites/data |
| `Fix-RDP-CredSSP-Error.ps1` / `Restore-RDP-CredSSP-Default.ps1` | Laptop | Temporary/revert RDP CredSSP workaround for unpatched servers |
| `Show-CurrentIP.ps1` | Server | Standalone console window showing current IP (superseded by wallpaper version) |
| `Update-IPWallpaper.ps1` + `Install-IPWallpaperTask.ps1` | Server | Automatic wallpaper showing current IP, refreshes every 5 min via Scheduled Task |

### Core engine pieces (individually tested)
| Script | Run on | Proves |
|---|---|---|
| `01-Inspect-IIS.ps1` | Server | Combined read-only visibility + JSON export (merged from two earlier separate scripts) |
| `02-Inspect-IIS-Detail.ps1` | Server | Auth settings, recycling/timeout/start-mode detail |
| `03-Checkpoint-Engine.ps1` | Server | Checkpoint recording mechanism (simulated steps, one designed to fail) |
| `04-Create-TestSite.ps1` | Server | First real IIS write, checkpointed |
| `05-Clone-Site.ps1` | Server | Read-then-recreate migration pattern |
| `06-Migrate-Certificate.ps1` | Server | Certificate/HTTPS binding migration |
| `07-Test-CheckpointResume.ps1` | Server | Resume capability (run twice to see the effect) |
| `08-Test-SecureCredentials.ps1` | Laptop | SecretStore vault setup + credential retrieval + real remote command |

### Assembled tool
| Script | Run on | Purpose |
|---|---|---|
| `IIS-Pivot-v0.1.ps1` | Server | Combined migration tool — params: `-SourceSite -TargetSite -TargetPort [-IncludeHttps -TargetHttpsPort]`. Run locally on the server. |
| `IIS-Pivot-v0.2-Remote.ps1` | Laptop | Same logic, triggered remotely via WinRM using the stored credential — no RDP needed at all |

### Azure Blob storage
| Script | Run on | Status |
|---|---|---|
| `09-Store-AzureConnectionString.ps1` | Laptop | Stores connection string securely — **superseded, see note below** |
| `10-Test-AzureBlobUpload.ps1` | Laptop | Uses `Az.Storage` PowerShell module — **abandoned, do not use.** Hit unresolvable module version conflicts (multiple old `Az.Accounts`/`Az.Storage` versions installed via OneDrive-synced module path, `-File` parameter bug in `Az.Storage` 2.2.0, then `Az.Accounts` version mismatch even after updating). Rather than keep fighting it, switched to direct REST calls instead. |
| `11-Store-AzureSasUrl.ps1` | Laptop | Stores the Blob SAS URL securely — **this is the one actually used** |
| `12-Test-AzureBlobUpload-REST.ps1` | Laptop | **Working version** — direct HTTP PUT/GET calls against Azure Blob using the SAS URL, no Az module dependency at all. Fully verified: upload, list, download, integrity match. |

**Important:** if continuing Azure work, build on `12-Test-AzureBlobUpload-REST.ps1`'s approach (raw REST + SAS URL), not the `Az.Storage` module — that path is a dead end on this particular laptop until/unless someone cleans up the module installation properly (multiple conflicting versions under `C:\Users\ashis\OneDrive\Documents\WindowsPowerShell\Modules\`).

## Known environment gotchas (condensed — see setup guide for full detail)

- **TLS 1.2 must be forced explicitly** in any script making HTTPS requests on this server (`[Net.ServicePointManager]::SecurityProtocol = ... -bor [Net.SecurityProtocolType]::Tls12`) — old .NET Framework default breaks otherwise.
- **`D:\` in VirtualBox is often the virtual DVD/ISO drive**, not a writable disk — test actual write access, don't assume.
- **Execution policy resets every new PowerShell window** — `Set-ExecutionPolicy -Scope Process Bypass -Force` needed each fresh session, or set `RemoteSigned` at `CurrentUser` scope once for a permanent (safe) fix.
- **WinRM username needs computer-name prefix**: `WIN-5T3OHIUJ7II\Administrator`, not just `Administrator`.
- **SecretStore vault locks between PowerShell sessions** — needs its master password again each new session via `Unlock-SecretStore` (scripts handle this, just expect the prompt).
- **A PowerShell HTTPS self-check can produce a false failure** on this server/OS combo even when the real site works fine in a browser — confirmed via direct browser test once, not something to keep chasing if it recurs; downgrade to a warning rather than a hard failure.
- **Azure's List Blobs REST response includes a BOM-like prefix** that breaks naive `[xml]` casting — strip everything before the first `<` character before parsing.
