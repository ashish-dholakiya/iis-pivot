# IIS Pivot — Practice Server Setup Guide
*Prepared for: Sr. Full-Stack Developer, UI/UX Developer, Project Manager*
*Prepared by: Enterprise & Automation / Security / UI-UX architecture (combined, per design reference doc)*
*Companion script: `Setup-PracticeServer.ps1`*

---

## 1. Purpose

This document explains what `Setup-PracticeServer.ps1` does, why each piece is there, and what the team needs to know before running it. It provisions the **disposable Windows Server 2016 evaluation VM** that stands in for a real client server during development — per the testing methodology locked in the design reference (§11): no live sandbox access exists for AI-assisted development, so every real script runs by a human, on this VM, with results reported back.

**This script is not part of IIS Pivot.** It's test fixture scaffolding — it makes a bare VM realistic enough to test against (IIS installed, a few sample sites, dummy client data) so the first real IIS Pivot components have something to inspect and migrate.

---

## 2. Prerequisites before running the script

| Item | Note |
|---|---|
| Windows Server 2016 evaluation VM | Freshly installed, per the link shared earlier (`microsoft.com/en-us/evalcenter/download-windows-server-2016`) |
| Internet access on the VM | Required for PowerShell 7 install, PSGallery modules, and Windows Update servicing packages. If the VM is intentionally offline/isolated, use `-SkipPowerShell7` and expect the PSGallery module steps to warn and skip gracefully. |
| Local administrator access | Script requires elevation (`#Requires -RunAsAdministrator`) — run PowerShell "as Administrator" |
| Activated within 10 days | Evaluation builds must activate over the internet within 10 days of install or they auto-shut down — do this before extended testing |
| Latest servicing package | Recommended before running: Microsoft Update Catalog → search "Windows Server 2016" → install the latest cumulative update. Saves hitting known old-build bugs mid-test. |

---

## 3. What the script installs

1. **IIS role + sub-features** — static content, ASP.NET 4.5, management tools/console, scripting tools, common auth providers, health/logging, WebSockets. Chosen to cover what IIS Pivot's Phase 1 engine needs to read and later migrate.
2. **.NET Framework check** — confirms 4.7.2+ is present (pulled in by the ASP.NET feature above); warns if not, since Web Deploy needs it.
3. **PowerShell 7** (optional, on by default) — installed via Microsoft's official `aka.ms/install-powershell.ps1` script. Not required on target servers per the design (5.1 is the floor), but useful here for parity with the jumpbox, which does require PS7.
4. **IIS PowerShell modules** — confirms `WebAdministration` (ships with the management tools feature), installs `IISAdministration` from PSGallery, and installs `Microsoft.PowerShell.SecretManagement` / `SecretStore` now so the credential-storage control from the design doc (§7) is ready ahead of when we actually need it.
5. **Web Deploy (msdeploy)** — checked, not auto-installed. Microsoft doesn't keep a stable direct MSI link across releases, so the script detects presence and prints manual download instructions (official page: `microsoft.com/en-us/download/details.aspx?id=106070`) rather than risk pulling a stale or wrong link.
6. **Seeded test data** (skippable via `-SkipTestData`):
   - **Three test sites** (`PivotTest-Alpha/Beta/Gamma`) on ports 8081–8083, each with a **different app pool identity type** (`ApplicationPoolIdentity`, `NetworkService`, `LocalService`) — this directly exercises the app-pool-identity restoration gap called out in the design doc's Web Deploy comparison (§3).
   - **One self-signed certificate + HTTPS binding** (port 8444) on `PivotTest-Alpha`, to exercise the certificate migration path later.
   - **Dummy "client data" folders** (`ClientA/B/C`, a few small text files each) under `D:\PivotTestClientData` (or `C:\PivotTestClientData` if no D: drive exists on the VM) — small stand-ins for the multi-tenant client data the design doc says is excluded from migration by default and only moved on explicit opt-in (§5). These are placeholder files, not bulk data — the point is to prove the exclusion/opt-in logic sees them.
   - **Firewall rules** opened for the test ports so sites are actually reachable during manual verification.

Every step checks current state before acting, so the script is safe to re-run (e.g., after a reboot the install triggers).

---

## 4. What to do

1. Run `Setup-PracticeServer.ps1` (as Administrator) on the practice VM.
2. If a restart is flagged, reboot, then re-run the script once more — every line should report `[OK]` or `[SKIP]`, with no `[WARN]`.
3. Report back: full console output, especially any `[WARN]` lines, and confirm whether the three test sites answer at `http://<vm-ip>:8081`, `:8082`, `:8083`.
4. Once confirmed, we move to the first real IIS Pivot piece: the read-only "confirm PowerShell can see IIS correctly" script, run against this now-seeded environment.

---

## 5. Notes for the Project Manager

- This step covers **environment setup only** — no IIS Pivot code has been written or tested yet. Actual Phase 1 development (checkpointing, storage abstraction, IIS config capture/restore) starts once this VM is confirmed working.
- Every future implementation step follows the same loop: a small script is handed over, a human runs it on this VM and reports results, issues get fixed, then the next piece builds on top. This is deliberately incremental — no big-bang delivery, per §11 of the design reference.
- The practice VM's evaluation license is time-limited (180 days from install) — worth tracking as a light project-timeline dependency.

---

*This guide accompanies `Setup-PracticeServer.ps1`. Both should be reviewed together before running against the practice server.*
