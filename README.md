# IIS Pivot

Custom PowerShell-based tool for migrating IIS-hosted websites between Windows servers — checkpointed/resumable steps, remote execution over WinRM, secure credential handling, and cloud storage backup.

**Status: Phase 1 core engine complete and proven — only the console remains.** Every engine-side Phase 1 capability is built and tested end-to-end on a practice Windows Server 2016 environment: remote execution, checkpointing, secure credentials, Azure Blob storage, a pluggable storage abstraction layer, manifest version checking, a per-site smoke test (which caught and led to fixing a real HTTPS/firewall bug), and a storage/client-data sizing assessment. The one remaining Phase 1 item is the Pode web console itself — not yet built, but fully scoped with an approved sprint plan (private) and previewed in `docs/IIS-Pivot-Console-User-Guide.pdf`. Not yet approved for use beyond the internal practice environment. See `docs/IIS-Pivot-Technical-Reference.md` for what's proven, and the "What's Still Needed" section in `docs/IIS-Pivot-Full-Configuration-Guide.md` for Phase 2 gating requirements.

## Start here

If you're picking this project up fresh, read in this order:
1. `docs/00-START-HERE.md` — orientation, current status, working style
2. Private design/scope document — **authoritative source of truth for project scope and architecture.** Not included in this repository — see the note below.
3. `docs/IIS-Pivot-Technical-Reference.md` — what's built so far, script inventory, environment identifiers
4. `docs/IIS-Pivot-Full-Configuration-Guide.md` — full environment setup steps, every gotcha hit along the way
5. `docs/Practice-Server-Setup-Guide.md` — companion doc for `Setup-PracticeServer.ps1`, explains what the seeded test fixture VM contains and why
6. `docs/IIS-Pivot-Console-User-Guide.pdf` — visual, plain-language walkthrough of the planned console GUI, screen by screen. **Note: describes the planned design (mockups), not a built product** — the Pode console itself hasn't been implemented yet (see the console sprint plan). Useful now for previewing the intended experience; will describe the real thing once the console is actually built.

> **Note on the design reference document:** a design/scope document exists that is the author's own intellectual property. It is deliberately **not published or referenced by name/path in this repository**, and is kept entirely local, outside version control. Anyone continuing this project with direct access to the author should request it separately; everything a new contributor needs to work safely from the public repo alone (what's built, what's proven, environment setup, gotchas) is covered by the other docs listed above.

## Folder structure

```
IIS-Pivot/
├── docs/                     Project documentation and handover notes
├── scripts/
│   ├── environment-setup/    Run ONCE to provision the practice server + laptop-side RDP/network fixes
│   ├── core-engine/          Individually-tested capability scripts (read, write, checkpoint, clone, cert migration...)
│   ├── tool/                 The assembled migration tool (local and remote-triggered versions)
│   └── storage-backend/      Azure Blob storage integration (SAS-URL-based, REST calls)
```

## Where each script runs

See the "Quick reference: which machine each script runs on" table in `docs/IIS-Pivot-Technical-Reference.md`. Short version: most `scripts/core-engine/` and `scripts/environment-setup/Setup-PracticeServer.ps1` run **on the server**; credential/secret/remote-labeled scripts run **on the jumpbox (laptop)**.

## Security notes — read before committing anything new

- **Never commit real credentials, connection strings, SAS URLs, or `.json` checkpoint/export files that may contain server details.** See `.gitignore` — it already excludes the common cases, but double-check before `git add`.
- **The private design/scope document stays out of version control entirely** — it must never be added to this repo under any path, and no future edit to these docs should name its filename or restate its architecture/security specifics in detail. General status references (e.g. "a private design doc governs additional requirements") are fine; naming specific components, method names, or internal security mechanisms is not.
- All secrets used by these scripts are pulled from a local `SecretManagement`/`SecretStore` vault (`IISPivotVault`) on the jumpbox — never hardcoded into scripts.
- If a credential is ever accidentally committed or shared, rotate it at the source immediately, don't just remove it from a later commit (git history retains it).

## Setting up version control

```powershell
cd "C:\Projects\IIS Pivot"
git init
git add .
git commit -m "Initial commit: Phase 1 core engine, proven end-to-end"
```

Then connect it to a GitHub remote of your choice (`git remote add origin <url>`, `git push -u origin main`).

## Author

This project was developed by **Ashish Dholakiya**.
Learn more at [www.ashishdholakiya.com](https://www.ashishdholakiya.com).

## Support

For questions, issues, or support regarding this project, please reach out at **akdholakiya83@gmail.com**.
