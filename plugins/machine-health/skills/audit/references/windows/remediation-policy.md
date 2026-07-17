# Windows remediation policy

This policy is the **only** authorization source for remediations on Windows. If a remediation is not listed here with exact conditions, it does not run — even if a check recommends it. Shared `references/shared/remediation-philosophy.md` still governs global behavior (one attempt, before/after logging, fail-safe posture).

Every authorized remediation has:

- **Trigger:** check ID(s) and severity condition that must hold.
- **Action:** single operation performed.
- **Script:** `.ps1` that does it.
- **Abort conditions:** when authorization is overridden.
- **Default state:** disabled until human approval in `<StateBase>/state/approvals.json` (see [`../shared/approvals.md`](../shared/approvals.md)).

Orchestrator consults this list after check execution and before any action.

---

## 1. Restart-StoppedService

- **Trigger:** `services` check returns `WARN` with one or more `Automatic` services in `Stopped` state (the `INFO` exception for Automatic-delayed-start with <10 min uptime does **not** trigger remediation).
- **Action:** one `Start-Service` attempt per stopped Automatic service. Each target gets its own remediation attempt record.
- **Script:** `scripts/windows/remediations/Restart-StoppedService.ps1`
- **Abort conditions:**
  - `DryRun -eq $true`.
  - User-load heuristic tripped.
  - Service name appears in `approvals.json` `check_overrides.services.service_exclusions` (per-host user curation).
  - `Start-Service` requires elevation the run lacks — log `UNKNOWN` for the remediation attempt, do not auto-elevate.
- **Default state:** **DISABLED** until user sets `remediations.restart-stopped-service.approved: true` in `<StateBase>/state/approvals.json`. First run dry-modes it regardless.
- **On failure:** corresponding `services` finding upgrades to `CRIT` with `"notes": "Restart-StoppedService failed for <svc>: <message>"`.

---

## 2. Clear-TempFiles

- **Trigger:** `storage` check returns `WARN` or `CRIT` for disk space on `C:` (free space <15%). Remediation targets temp paths regardless of which volume is low, since temp bloat is the most common single cause on `C:`.
- **Action:** delete files older than **7 days** from:
  - `$env:TEMP` (user-scoped)
  - `$env:LOCALAPPDATA\Temp` (same as TEMP in most cases; handle duplicate gracefully)
  - `C:\Windows\Temp` (system-scoped; silently skip per-file access-denied)
- **Script:** `scripts/windows/remediations/Clear-TempFiles.ps1`
- **Abort conditions:**
  - `DryRun -eq $true`.
  - User-load heuristic tripped.
  - Free space on `C:` >15% — no longer WARN/CRIT, so no action (idempotent re-run safety).
- **Default state:** **DISABLED** until the user sets `remediations.clear-temp-files.approved: true` in `<StateBase>/state/approvals.json`. First run dry-modes it regardless.
- **Output contract:**
  - `before`: `{ "temp_usage_bytes": <int>, "count": <int> }` for each target path.
  - `after`: same structure, recomputed post-delete.
  - `bytes_freed`: total freed (int, sum across paths).
  - Files held open by other processes silently skipped; count of skipped files goes in `detail.skipped_locked`.
- **Explicitly not deleted:**
  - Anything under `%USERPROFILE%\Documents`, `%USERPROFILE%\Desktop`, or OneDrive-synced folders.
  - Anything not matching the age filter.
  - Directories themselves — only files are removed; empty directories remain.

---

## Explicitly disabled (never allowed without further approval)

These remediations are proposed periodically in online discussions but are **not** authorized by this policy, regardless of user approval, until a new entry is vetted and added here.

- **Windows Update cache clear** (`net stop wuauserv; Remove-Item C:\Windows\SoftwareDistribution\Download\* -Recurse; net start wuauserv`). Risks: corrupts in-flight downloads, breaks signature validation, requires a service restart chain. If enabled in the future, it must skip when BITS has pending transfers (`Get-BitsTransfer -AllUsers | Where-Object JobState -in 'Transferring','Transferred'`).
- **Driver reinstall / rollback.** Wrong driver version can blue-screen the machine.
- **Defender signature force-update.** `Update-MpSignatures` is usually safe, but a failed update can leave Defender in an odd state; surface age as CRIT instead.
- **Registry cleanup of any kind.** No exceptions.
- **Network stack reset.** `netsh winsock reset`, `ipconfig /flushdns`, route table changes — all out.
- **Service configuration changes.** Start type, account, dependencies — read-only.
- **Reboots.** Period.

---

## Approval workflow

1. First scheduled run produces a report with remediations flagged `DISABLED (pending approval)`.
2. Human reviews the report, then approves via `/machine-health:setup` (or edits `<StateBase>/state/approvals.json` to set `remediations.<id>.approved: true`). See [`../shared/approvals.md`](../shared/approvals.md) for full schema and examples.
3. Next run sees the approval, flips authorization to enabled, and attempts the remediation.
4. If the remediation causes trouble, the human flips `approved: true` back to `false`; the skill respects the revocation immediately on next run.

`approvals.json` is the single source of truth. The `TODO.md` shipped with the plugin is policy documentation only -- no checkboxes drive behavior. On first run, checked boxes from a legacy `TODO.md` migrate into `approvals.json` (one-shot); after that, TODO.md is ignored.

---

## How the orchestrator reads this policy

The orchestrator matches check findings to remediations by:

1. For each check result with severity in the trigger set, look up the remediation entry above by (check category, check id, severity).
2. Call `Get-ApprovalState` (reads `<StateBase>/state/approvals.json`) and evaluate `Test-ApprovalGranted` for the remediation id.
3. Run abort-condition checks (`DryRun`, user load, per-host exclusions from `check_overrides`).
4. Dispatch the remediation script with check-result JSON passed as `-Finding`.
5. Collect and record the attempt in `<StateBase>/logs/remediation-YYYY-MM-DD.log` and in the run snapshot.
