# IIS Pivot — Full Environment Configuration Guide
*Every step, in order, from a blank machine to a working test environment with IIS Pivot's core engine verified.*

---

## Important scope note

This guide documents how to set up the **internal practice/test environment** — the one used to build and verify IIS Pivot itself. Per the design reference document (§10), IIS Pivot is **Phase 1 — Internal Use Only** until Phase 2 hardening (full JEA enforcement, code signing, encryption-at-rest, audit trail) is complete. This guide does **not** cover deploying IIS Pivot against a real client server — that requires Phase 2 sign-off first.

---

## Part A — Practice Server: Operating System

### A1. Download Windows Server 2016 Evaluation
- Official link: `https://www.microsoft.com/en-us/evalcenter/download-windows-server-2016`
- Choose Standard or Datacenter edition (not Essentials).
- Evaluation expires 180 days after install; must activate online within 10 days or it auto-shuts down.

### A2. Create the VM in VirtualBox
- New VM, Type: Microsoft Windows, Version: Windows 2016 (64-bit).
- **Do not** use VirtualBox's built-in "Unattended Install" feature — it can generate an answer file that conflicts with Server edition licensing and produces a "cannot find Microsoft Software License Terms" error.
- Allocate at least 4 GB RAM, 60 GB disk.
- Attach the downloaded ISO manually.

### A3. Manual (interactive) Windows Setup
- Boot the VM, click through Setup normally — no autounattend.xml.
- Choose **Windows Server 2016 Standard (Desktop Experience)** — not Server Core — for a normal usable desktop.
- Choose Custom install (not Upgrade).
- Set the Administrator password when prompted.

---

## Part B — Remote Access (RDP)

### B1. Initial RDP attempt will likely fail with a CredSSP error
Fresh evaluation installs are unpatched, and modern client PCs block RDP to unpatched servers by default. Error looks like:
> "This could be due to CredSSP encryption oracle remediation"

### B2. Temporary workaround (on your laptop, NOT the server)
Only needed to get in long enough to update the server. Run as Administrator on your laptop:
```powershell
$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\CredSSP\Parameters'
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name 'AllowEncryptionOracle' -Value 2 -Type DWord
```
Revert later with the same path, value `0`, once the server is patched.

### B3. Patch the server (the real fix)
On the server itself (log in directly via VirtualBox, not RDP, the first time):
- Settings → Update & Security → Windows Update → Check for updates repeatedly (can take multiple rounds).
- **Faster alternative:** download the latest Cumulative Update manually from `https://www.catalog.update.microsoft.com` (search "Cumulative Update Windows Server 2016 x64", sort by date), copy the `.msu` onto the server, install directly:
  ```powershell
  wusa.exe "C:\path\to\file.msu" /quiet /norestart
  ```
- Restart when prompted. May take 20-60+ minutes on "Getting Windows ready" — this is normal for a first-time large cumulative update; do not interrupt it.
- Once patched, RDP should work with default (secure) settings — undo the B2 workaround if you applied it.

---

## Part C — Practice Server: IIS + Dependencies

Run `Setup-PracticeServer.ps1` (as Administrator, via RDP or console) on the freshly patched server. It handles, in order:

1. IIS role + 26 sub-features (static content, ASP.NET, management/scripting tools, WebSockets, etc.)
2. .NET Framework version check (warns if below 4.7.2 — non-blocking)
3. PowerShell 7 install (optional convenience, not required on target servers per design)
4. IIS PowerShell modules: `WebAdministration`, `IISAdministration`, `Microsoft.PowerShell.SecretManagement`, `Microsoft.PowerShell.SecretStore`
5. Web Deploy check (manual install if needed — no stable direct download link exists)
6. Seeds 3 test sites (`PivotTest-Alpha/Beta/Gamma`) with different app pool identities, one HTTPS binding with a self-signed cert, dummy multi-tenant "client data" folders, and firewall rules

**Before running it, apply this fix inside your PowerShell session** (needed on older Server 2016 for any HTTPS download to succeed):
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
```
(The current version of `Setup-PracticeServer.ps1` already has this built in.)

**Known gotcha:** `D:\` in a VirtualBox VM is often the virtual DVD/ISO drive, not a real writable disk — the script tests actual write access before using it, don't assume `Test-Path 'D:\'` alone means it's usable.

Safe to re-run — every step checks current state first.

---

## Part D — Running Scripts: PowerShell Session Setup

Every new, unsigned script triggers this error the first time in a fresh PowerShell window:
> "File ... cannot be loaded. The file ... is not digitally signed."

**Per-session fix** (needed again each new PowerShell window):
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
```

**Optional one-time permanent fix** (run once, as Administrator, on the server):
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
```

**File transfer note:** if copying scripts onto the server via RDP clipboard produces parser errors on lines that look fine, suspect character corruption (smart quotes, em-dashes) introduced in transit. Keep script files plain ASCII to avoid this entirely.

---

## Part E — Remote Execution Setup (WinRM)

This is the mechanism the real IIS Pivot jumpbox will use — running commands *against* the target server without RDP. Set up once from whichever machine will issue commands (your laptop, or eventually the jumpbox):

### E1. On the connecting machine (laptop/future jumpbox)
```powershell
Start-Service WinRM
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "<target-server-ip>" -Force
```
**Do NOT run `winrm quickconfig`** on the connecting machine — that configures it to *receive* remote commands, which is the wrong direction here.

### E2. Connecting
```powershell
$cred = Get-Credential
Invoke-Command -ComputerName <target-server-ip> -Credential $cred -ScriptBlock { <command> }
```
**Important:** in the credential prompt, the username must be prefixed with the target server's computer name, e.g. `WIN-5T3OHIUJ7II\Administrator` — not just `Administrator` — since these machines aren't on a shared domain.

### E3. Verify
```powershell
Invoke-Command -ComputerName <target-server-ip> -Credential $cred -ScriptBlock {
    Get-Website | Select-Object Name, State
}
```
Should return the live list of IIS sites on the target, run entirely remotely.

---

## Part F — IIS Pivot Core Scripts (run in this order)

All of these are checkpointed (each step tracked as NotStarted/InProgress/Completed/Failed) and were verified end-to-end on the practice server.

| # | Script | What it proves |
|---|---|---|
| 1 | `01-Inspect-IIS.ps1` | Read-only: can see sites, app pools, bindings; exports to JSON manifest |
| 2 | `02-Inspect-IIS-Detail.ps1` | Read-only: authentication settings, app pool recycling/timeout/start mode |
| 3 | `03-Checkpoint-Engine.ps1` | Checkpoint mechanism itself works (tracks success and deliberate failure correctly) |
| 4 | `04-Create-TestSite.ps1` | First real write: creates a new site, checkpointed, verified via actual HTTP request |
| 5 | `05-Clone-Site.ps1` | Reads an existing site's real config and recreates an equivalent site elsewhere |
| 6 | `06-Migrate-Certificate.ps1` | Reads an HTTPS cert/binding from one site and applies it to another |

All scripts write their checkpoint files to `C:\PivotCheckpoints` and any data exports to `C:\PivotExports` — both created automatically.

---

## Part G — Optional Convenience: Always-Visible IP

Since the practice server's IP is DHCP-assigned and can change, two scripts keep it visible without needing to check VirtualBox each time:
- `Update-IPWallpaper.ps1` — draws the current IP onto the desktop wallpaper
- `Install-IPWallpaperTask.ps1` — registers a Scheduled Task to run the above automatically at login and every 5 minutes, forever

Run `Install-IPWallpaperTask.ps1` once (both files must be in the same folder); no further action needed after that.

---

## Part H — Secure Credential Storage

Rather than typing the server password every time a remote command runs, store it once using `Microsoft.PowerShell.SecretManagement` + `Microsoft.PowerShell.SecretStore` (run `08-Test-SecureCredentials.ps1` — on your **laptop**):
- First run creates a local encrypted vault (`IISPivotVault`) and asks you to set a **master password** for it — this is separate from any server/Azure password, write it down, it's not recoverable.
- Then it asks for the server credential once (`WIN-5T3OHIUJ7II\Administrator` format), stores it encrypted.
- Every script after that retrieves it automatically — no more typing.

**Known gotcha:** the vault locks itself between PowerShell sessions and needs the master password again each time (`Unlock-SecretStore`) — this is expected security behavior, not a bug.

**If you ever accidentally paste a real credential/key into a chat or screenshot:** treat it as compromised. Rotate it at the source (Azure key rotation, Windows password change, etc.), then re-store the new value the same way — never keep using an exposed credential just because it still technically works.

---

## Part I — Azure Blob Storage Backend

### I1. Create the storage account (Azure Portal, browser)
- portal.azure.com → Storage accounts → Create
- Standard performance, **Locally-redundant storage (LRS)** (cheapest, fine for testing)
- Create a container inside it (e.g. `iis-pivot-test`)

### I2. Generate a SAS URL (not a raw connection string)
A **connection string** requires the `Az.Storage` PowerShell module, which had unresolvable version conflicts in this environment (multiple old versions installed via OneDrive-synced module paths — see Part J). A **SAS (Shared Access Signature) URL** avoids this entirely by working over plain HTTP requests.

- Inside the container → **Shared access tokens**
- Permissions: tick **Read, Write, List, Delete**
- Allowed resource types: tick **both Container and Object**
- Set a reasonable expiry (e.g. 1 year)
- Copy the full **Blob service SAS URL** (not just the "SAS token" — the URL already includes it combined)

### I3. Store it securely
Run `11-Store-AzureSasUrl.ps1` (**laptop**) — same vault pattern as the server credential, paste the SAS URL when asked.

### I4. Test it
Run `12-Test-AzureBlobUpload-REST.ps1` (**laptop**) — pulls live data from the server, uploads to Azure via direct REST calls, lists the container, downloads back, verifies the content matches exactly.

**Do not use `10-Test-AzureBlobUpload.ps1`** (the `Az.Storage` module version) — it's abandoned, see Part J.

---

## Part J — Azure `Az.Storage` Module: Abandoned Approach (for reference only)

If Azure work resumes and someone wants to revisit using the official `Az.Storage` PowerShell module instead of raw REST calls, here's what went wrong, so it isn't repeated blindly:

- The laptop had **three versions of `Az.Storage`** (1.7.0, 2.2.0, 9.7.2) and **three versions of `Az.Accounts`** (1.6.2, 1.9.0, 5.5.2), all installed under a OneDrive-synced path (`C:\Users\ashis\OneDrive\Documents\WindowsPowerShell\Modules\`).
- `Az.Storage 2.2.0`'s `Set-AzStorageBlobContent -File` threw "Illegal characters in path" on a completely valid path — a known bug in that old version's bundled transfer engine.
- Forcing the newest versions explicitly still failed with "This module requires Az.Accounts version 2.7.5 or greater" — something was loading an old version before the explicit import could take effect, and OneDrive's file sync (particularly "Files On-Demand" placeholders) is suspected as a contributing factor, though not confirmed.
- **Resolution:** abandoned the module entirely in favor of direct REST calls with a SAS URL (see Part I) — simpler, zero dependency conflicts, fully working.
- If revisiting: consider uninstalling all `Az.*` module versions cleanly, ensuring the module install path isn't inside a OneDrive-synced folder (or that folder is set to "Always keep on this device"), and installing a single current version fresh.

---

## Part K — What's Still Needed Before Wider ("General") Use

Per the design reference doc, the following are **required before Phase 1 → Phase 2 graduation** and before any use beyond internal, single-engineer testing:
- Full JEA (Just Enough Administration) enforcement on WinRM (currently using default/unconstrained admin credentials for testing)
- Code signing for all scripts (currently unsigned, requiring the execution-policy bypass covered in Part D)
- Encryption-at-rest for stored backups/exports
- Full audit trail of every operation
- Ephemeral-account lifecycle management (credentials created and expired automatically per engagement, not a standing Administrator account)
- Storage backend integration (Azure Blob / S3 / on-prem NAS) — not yet tested; all testing so far has used local disk only

None of these are optional polish — they're the explicit gate the design doc sets before this tool touches anything beyond a disposable practice VM.
