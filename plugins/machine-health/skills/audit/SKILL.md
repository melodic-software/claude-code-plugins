---
name: audit
description: "Audits local workstation health and emits a findings report: runs OS-specific checks (disk, OS updates, security posture, CISA KEV) from a versioned catalog with trend-aware severity; remediation only when pre-approved. Use when: 'machine health check', 'health check', 'audit my machine', 'system health', 'workstation audit', 'check my computer', 'run health check', 'workstation status report', or when a scheduled weekly routine fires. Outputs a dated markdown report; updates append-only history state. Windows fully implemented; macOS/Linux scaffolded (reports UNKNOWN and stops)."
---

# machine-health

## Overview

This skill performs a **weekly workstation health audit** with a fail-safe posture: surface issues over silently fixing them. Findings always include reproduction commands so the human can rerun the check outside the skill. Remediations are narrow, logged, and only attempted when the OS-specific `remediation-policy.md` authorizes them. Severity is always trend-aware — a single reading is rarely load-bearing; history is consulted before finalizing severity.

The skill is stateless about scheduling; a separate routine (e.g., a Monday 08:00 scheduled task, or an ad-hoc `/machine-health:audit` invocation) calls into it.

**Progressive disclosure by OS.** The skill detects the host OS and loads only matching references and scripts. Windows is fully implemented. macOS and Linux are scaffolded as `NOT_IMPLEMENTED` stubs so they can be populated in future passes without restructuring.

## Resolving output locations (do this first)

Two roots, resolved through the plugin's configuration seams:

| Root | Holds | Resolution |
|---|---|---|
| **Report root** (`-OutputBase`) | `reports/` — the human-facing dated reports | `${user_config.report_dir}` when set to a non-empty path; if it is empty or still shows an unexpanded `${user_config.report_dir}` token (option unset), default to `$env:USERPROFILE\Documents\MachineHealth` |
| **State root** (`-StateBase`) | `state/` (history, latest snapshot, approvals), `logs/`, catalog overlay, custom checks, `TODO.md` proposals | `${CLAUDE_PLUGIN_DATA}` — the per-plugin data directory that survives plugin updates. No fallback path: the directory is named for the plugin's install identity, not the plugin, so a literal guess resolves to a different directory and splits state from the overlay. If the token is unexpanded (running outside plugin context), stop and report that the state root cannot be resolved — never substitute a guessed path |

Pass both explicitly to the orchestrator (`-OutputBase <report-root> -StateBase <state-root>`). Never write generated state into the plugin's own install directory — a plugin update replaces it.

Other runtime parameters the caller passes (via slash-command arguments, scheduled task arguments, or environment variables — the orchestrator accepts them as parameters):

| Parameter | Default | Meaning |
|---|---|---|
| `RunMode` | `weekly` | One of `weekly`, `on-demand`, `first-run`. `first-run` forces dry-run and seeds state. |
| `DryRun` | `$false` (on `weekly`/`on-demand`); `$true` (on `first-run`) | Skip all remediations; still produce a full report. |

## OS detection and routing

```text
# Detect current OS (the skill requires PowerShell 7.4+; launch pwsh, not
# Windows PowerShell 5.1, which cannot run the checks)
if   (PowerShell 7.4+)  use $IsWindows / $IsMacOS / $IsLinux
else                    non-PowerShell shell: uname -s -> Darwin|Linux

# Load references (shared first, then OS-specific)
Read references/shared/severity-rubric.md
Read references/shared/output-schema.md
Read references/shared/report-template.md
Read references/shared/discovery-guide.md
Read references/shared/remediation-philosophy.md
Read references/<os>/*.md

# If the detected OS folder contains NOT_IMPLEMENTED.md, STOP.
# Produce an UNKNOWN-severity report explaining the gap, link to
# references/shared/discovery-guide.md for porting guidance, and exit.
# Never attempt to execute Windows scripts on macOS/Linux.
```

Routing table:

| Detected OS | Orchestrator | Status |
|---|---|---|
| Windows | `scripts/windows/Invoke-MachineHealthCheck.ps1` | Implemented |
| macOS | `scripts/macos/NOT_IMPLEMENTED.md` | Stub — report UNKNOWN and stop |
| Linux | `scripts/linux/NOT_IMPLEMENTED.md` | Stub — report UNKNOWN and stop |

## High-level procedure

1. **Verify preconditions.** PowerShell 7.4+ (enforced by the orchestrator's `#Requires`; individual checks that need a still-newer cmdlet return UNKNOWN rather than aborting). The report and state roots are writable. Record elevation state via `scripts/<os>/lib/Test-IsElevated.ps1` — never prompt for UAC.
2. **Load and filter the catalog.** The orchestrator reads the shipped `catalog/checks.jsonc`, merges the machine-local overlay at `<StateBase>/catalog/checks.local.jsonc` when present (see `references/shared/catalog-overlay.md`), and keeps entries whose `os` list contains the current OS and where `enabled: true` and `deprecated: false`.
3. **Load trend context.** Read the tail of `<StateBase>/state/history.jsonl` (last 8 weeks) for each check. Pass the slice to each check script over stdin so checks can annotate deltas — but checks remain stateless themselves.
4. **Invoke the OS orchestrator.** Pass `OutputBase`, `StateBase`, and `RunMode`. The orchestrator dispatches checks under per-check 90s timeouts, collects JSON results, applies trend-aware severity adjustments, and — on non-dry runs — dispatches authorized remediations with before/after logging.
5. **Receive the structured result.** Run discovery per `references/shared/discovery-guide.md` — propose 1–3 OS-appropriate new checks. Straightforward read-only ones may be implemented as custom checks (script under `<StateBase>/scripts/<os>/checks/`, registered in the catalog overlay); anything needing new permissions or remediation lands in `<StateBase>/TODO.md` for human approval. Checks broadly useful to every consumer are best contributed to the plugin itself.
6. **Render the markdown report** from `references/shared/report-template.md` into `<OutputBase>/reports/health-<UTC-timestamp>.md` (one file per run, so a same-day rerun does not overwrite the earlier report).

   When the severity spread or trend deltas would read better visually, also offer a self-contained static HTML view of that report (color-coded CRIT/WARN/UNKNOWN, no remote fetch) — the markdown `.md` report stays the durable record.
7. **Update state.** Write `<StateBase>/state/latest.json`. Append one compact line to `<StateBase>/state/history.jsonl` — the trend source of truth.
8. **Verify and summarize.** Confirm the report exists. Print CRIT/WARN counts + report path to session output. A clean run may still include `UNKNOWN` findings — call those out too.

## Guardrails

- **Max total runtime:** 15 minutes. Partial results mark missing checks `UNKNOWN` with reason `"timeout"`.
- **Per-check timeout:** 90 seconds.
- **No interactive prompts.** Ever. The skill never pauses for input.
- **No retry loops on failure.** One attempt per check, one attempt per remediation.
- **First-run dry mode.** The first ever run (RunMode `first-run`) forces `DryRun = true`. Seeds state, produces the first report, queues remediation approval in `<StateBase>/TODO.md`.
- **Idempotency.** Two runs back-to-back produce two valid reports and two history entries with no partial state.
- **Egress allowlist.** Microsoft Update endpoints, winget sources, and the CISA KEV feed are the only permitted outbound URLs. Every outbound URL is logged to `<StateBase>/logs/run-YYYY-MM-DD.log`.
- **No `Invoke-Expression`** on any data the skill did not author itself in this session. No "run whatever came back" patterns.
- **Admin is not assumed.** Any check requiring elevation self-checks and returns `UNKNOWN` with `needs_admin: true` rather than prompting UAC.
- **Defer remediations under user load.** If the interactive session has had input in the last 60 seconds, log a note and run read-only checks only — defer remediations to next run.
- **Never write into the plugin install directory.** All generated state routes to `<StateBase>` / `<OutputBase>`; a plugin update replaces the install.

## Self-improvement hooks

The skill grows itself within narrow, auditable bounds:

- **Write to `<StateBase>/TODO.md`** when discovery proposes a check needing new permissions, network access, or remediation path. Human approval required before it becomes active.
- **Mark catalog entries `deprecated: true`** (never delete silently) with a `deprecation_reason` when a check has become meaningless for this host — via the catalog overlay (`references/shared/catalog-overlay.md`), never by editing the shipped catalog. Propose removal after 3 consecutive crashes (each increments `crash_count`).
- **Demote chronically quiet checks** — after 4 consecutive identical outputs, propose demotion to monthly cadence (write to `<StateBase>/TODO.md`; the approved demotion is an overlay `cadence` patch — don't reshuffle cadence on your own).
- **Refresh the CISA KEV cache** weekly via `scripts/<os>/lib/Get-CisaKevCache.ps1` (the winget-upgrades check does this automatically; the live cache lives under `$env:LOCALAPPDATA\machine-health\cache`, seeded from the shipped `catalog/cisa-kev.json` stub). Skip if younger than 7 days.
- **Never rewrite history.** `state/history.jsonl` is append-only. If a historical entry is wrong, add a correction entry; don't edit the old line.

## Consumer configuration

- **Report directory** — the `report_dir` plugin option (set at install or via `/plugin configure machine-health`).
- **Check catalog** — `/machine-health:setup` interviews and writes the machine-local overlay (disable/deprecate/demote shipped checks, register custom ones).
- **Remediation approvals** — `<StateBase>/state/approvals.json` per `references/shared/approvals.md`; nothing is approved by default. `/machine-health:setup` can seed it.

## Not in scope for this skill

- **Scheduling.** A separate routine creates the scheduled task. This skill is stateless about cadence.
- **Elevation prompts.** If admin is needed, report `UNKNOWN` and let the human decide whether to rerun elevated.
- **Cross-machine aggregation.** This skill is single-host. Multi-host dashboards are a separate concern.
