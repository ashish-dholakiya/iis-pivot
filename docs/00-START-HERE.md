# IIS Pivot — Project Orientation

**Read this file first, then the two linked below as needed.**

---

## One-paragraph status

IIS Pivot is a custom PowerShell-based tool for migrating IIS-hosted websites between Windows servers, with checkpointed/resumable steps, remote execution, secure credential handling, and cloud storage backup. **The core engine primitives are built and proven** — 12 separate capabilities tested end-to-end on a real Windows Server 2016 practice VM, including the hardest parts (remote execution, failure recovery, secure credentials, Azure Blob storage). This is genuine progress, but it is **not the same as "Phase 1 complete."** A private design/scope document (author's own IP, kept out of this repo entirely — see "Read next" below) defines additional Phase 1 requirements not yet built. The project is paused at a natural milestone: engine primitives proven, decision pending on whether to finish the remaining Phase 1 scope before considering Phase 2 (security hardening).

## Project context

The person driving this project is the **product owner**, not a developer — no assumed PowerShell/Windows Server background. Every script and instruction should state explicitly which machine it runs on ("Run on: your laptop" / "Run on: the server") — this avoided a lot of confusion once it became a consistent habit.

## Read next

- **Private design/scope document** — kept entirely local, outside version control (not referenced by filename or path here). **Authoritative source of truth** for what Phase 1 and Phase 2 actually consist of, system architecture, and security design. Read it before assuming anything is "done" — it's the reference the other docs are measured against. Anyone continuing this project should request it directly from the author.
- **`IIS-Pivot-Technical-Reference.md`** — what's been built so far, what's proven, every script and what it does, naming conventions, known environment identifiers (IPs, secret names, etc.)
- **`IIS-Pivot-Full-Configuration-Guide.md`** — how the practice environment was set up from scratch, and every gotcha hit along the way (useful if the environment needs to be rebuilt, or a similar issue resurfaces)
- **`Practice-Server-Setup-Guide.md`** — companion doc for `Setup-PracticeServer.ps1`; explains what the seeded test-fixture VM contains and why (it is not part of IIS Pivot itself — it's the disposable stand-in for a real client server)

## Immediate practical notes

- **Server IP may have changed.** It's DHCP-assigned and shown on the server's desktop wallpaper (a script keeps it updated automatically). Don't assume `192.168.29.201` is still current — check first.
- **The VM may not be running.** It's been powered off before (e.g., mid-Windows-Update). Confirm it's up before assuming any script will connect.
- **All scripts are plain ASCII.** Past corruption issues came from smart quotes/em-dashes in comments surviving copy-paste badly. Keep any new scripts ASCII-only.
- **Credentials live in a local SecretStore vault** (`IISPivotVault`) — see the technical reference for exact secret names. Nothing sensitive should need to be typed or pasted anywhere outside the one-time storage step; scripts should retrieve credentials from the vault instead.
- **If a key/credential is ever exposed accidentally** (pasted somewhere it shouldn't be, screenshotted, etc.), treat it as compromised: rotate it at the source (Azure, Windows, etc.) and re-store the new value the same way.

## Working approach established in this project (worth continuing)

- Small, single-purpose scripts, one capability at a time, tested before building on top of it — this caught real bugs early and cheaply. Combining everything into one large untested script was tried once and reverted in favor of this approach for anything new or risky; merging already-proven pieces into a combined tool was fine once each piece was individually verified.
- Every script states clearly which machine to run it on.
- When something fails, verify with evidence (diagnostic commands) rather than guessing twice in a row.
