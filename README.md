# IIS Pivot

Custom PowerShell-based tool for migrating IIS-hosted websites between Windows servers — checkpointed/resumable steps, remote execution over WinRM, secure credential handling, and cloud storage backup.

**Status: Phase 1 core engine primitives proven — Phase 1 itself is not yet complete.** 12 individual capabilities verified end-to-end on a practice Windows Server 2016 environment (remote execution, checkpointing, secure credentials, Azure Blob round-trip). This is real, tested progress, but a private design/scope document (see note below) defines additional Phase 1 requirements not yet built. Not yet approved for use beyond the internal practice environment. See `docs/IIS-Pivot-Technical-Reference.md` for what's proven, and the "What's Still Needed" section in `docs/IIS-Pivot-Full-Configuration-Guide.md` for Phase 2 gating requirements.

## Start here

If you're picking this project up fresh, read in this order:
1. `docs/00-START-HERE.md` — orientation, current status, working style
2. Private design/scope document — **authoritative source of truth for project scope and architecture.** Not included in this repository — see the note below.
3. `docs/IIS-Pivot-Technical-Reference.md` — what's built so far, script inventory, environment identifiers
4. `docs/IIS-Pivot-Full-Configuration-Guide.md` — full environment setup steps, every gotcha hit along the way
5. `docs/Practice-Server-Setup-Guide.md` — companion doc for `Setup-PracticeServer.ps1`, explains what the seeded test fixture VM contains and why

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
