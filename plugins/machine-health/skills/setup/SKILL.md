---
name: setup
description: "Configure the machine-health plugin for this machine. check (read-only): report the effective catalog overlay, remediation approvals, and pending proposals against the shipped catalog. apply: write the machine-local overlay (disable/deprecate/demote checks, register custom ones) and seed remediation approvals. Use when: 'set up machine-health', 'configure machine health', 'disable a health check', 'approve a remediation', 'add a custom health check', or the audit skill proposes catalog changes needing approval. Actions: check (read-only verification, default) | apply (write the machine-local overlay and approvals). Re-runnable and safe."
argument-hint: "check | apply [disable=<check-id> | deprecate=<check-id> | demote=<check-id> | approve=<remediation-id>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Inspect and customize `/machine-health:audit` on this host per the uniform setup contract:
`check` reads the effective configuration and reports, `apply` writes it. The machine-local
surface is the catalog overlay at `<StateBase>/catalog/checks.local.jsonc` and the remediation
approvals at `<StateBase>/state/approvals.json`. Configuration here is machine-local by design —
a workstation's check tuning does not belong in any repository. Idempotent: re-running reads the
existing files and offers updates rather than overwriting blind.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation. When `apply` is given complete write arguments (`disable=`, `deprecate=`, `demote=`,
`approve=`) it applies them non-interactively; with no arguments in an interactive session it runs
the full interview below. Custom-check registration is inherently interactive (it authors a script)
and always interviews.

## Resolving the state root

`<StateBase>` is `${CLAUDE_PLUGIN_DATA}` — the per-plugin data directory that survives plugin
updates. Create it if missing.

**There is no hardcoded fallback path, and inventing one is a defect rather than a safety net.** The
directory under `~/.claude/plugins/data/` is named for the plugin's *install identity*
(`<name>-<marketplace>`, or `<name>-inline` for a `--plugin-dir` session), not for the plugin. Any
literal path written here therefore resolves to a **different** directory than the one this plugin
actually reads and writes — so the overlay and approvals land in one place while the audit's state
and logs live in another, each half looking complete to whoever wrote it, and the operator's
disabled checks silently stop taking effect.

So when `${CLAUDE_PLUGIN_DATA}` renders as the literal unexpanded token, **stop**: report that the
skill is running outside plugin context and cannot resolve its state root, and change nothing.
Every probe below then reports UNKNOWN rather than INFO — with the root unresolved, an absent
overlay is indistinguishable from an unreadable one, and reporting "shipped defaults in effect"
would assert more than the evidence supports.

**Split-state-root report.** Because an earlier version of this skill did write a hardcoded
`~/.claude/plugins/data/machine-health`, `check` reports a split when it finds one: probe that exact
legacy path and any `machine-health-*` sibling of the resolved `<StateBase>`, and for each that
exists and is not `<StateBase>`, name it and list what it holds. Only `<StateBase>` is read.
Consolidating is the operator's move — moving or deleting the stray root is a decision about their
data, and this skill neither relocates nor removes files.

## `check` (read-only)

The shipped catalog (`${CLAUDE_PLUGIN_ROOT}/skills/audit/catalog/checks.jsonc`) is the single
source of truth for what checks exist and their defaults. **Read it first**, then read the existing
overlay, approvals, and `<StateBase>/TODO.md` when present. Report a PASS/FAIL/INFO table with one
remediation line per FAIL; modify nothing. The plugin ships a working zero-config default (the whole
shipped catalog, no remediations approved), so an absent overlay or absent approvals file is **INFO**
(default in effect), never FAIL.

1. **State root** — INFO: the resolved `<StateBase>` path and whether it exists yet, plus any split
   root found. FAIL, and stop before the remaining probes, when the token did not expand: an
   unresolved root makes every verdict below unfounded.
2. **Catalog overlay** (`<StateBase>/catalog/checks.local.jsonc`) — INFO when absent (the shipped
   catalog applies unchanged). When present: validate each entry against the overlay schema
   (`${CLAUDE_PLUGIN_ROOT}/skills/audit/references/shared/catalog-overlay.md`) and confirm every
   entry targets a real check — a shipped check id, or a custom check whose `script` path resolves
   under `<StateBase>`. FAIL a malformed entry, an entry targeting an unknown check id, or a custom
   entry whose `script` file is missing; report which checks the overlay patches (disabled,
   deprecated, demoted) and any custom checks it registers.
3. **Remediation approvals** (`<StateBase>/state/approvals.json`) — INFO when absent (no remediation
   is approved — the safe default; a bare audit mutates nothing). When present: validate against
   `references/shared/approvals.md` and confirm each approval names a real remediation
   (`restart-stopped-service`, `clear-temp-files`). FAIL a malformed file or an approval for an
   unknown remediation; otherwise report which remediations are approved.
4. **Pending proposals** (`<StateBase>/TODO.md`) — INFO: count proposals (deprecation, cadence
   demotion, new check) awaiting a decision from a prior audit; the remediation line is to run
   `apply` to walk them.
5. **Report directory** — INFO: the effective location — the `report_dir` plugin option when set,
   else `$env:USERPROFILE\Documents\MachineHealth`.

## `apply` (idempotent)

Run `check` first. Then, if the invocation carries write arguments, apply each non-interactively;
otherwise run the interview. After any write, re-read the target file and confirm the entry landed —
never report success on the write alone. Only write entries that differ from the shipped catalog, so
the overlay stays minimal.

**Non-interactive write paths** (named in the argument-hint; each targets a shipped check or
remediation, so no interview is needed):

- `disable=<check-id>` — write `"enabled": false` for that check to the overlay.
- `deprecate=<check-id>` — write `"deprecated": true` plus a `deprecation_reason` (from a
  `reason=<text>` argument when supplied, else a short default) to the overlay.
- `demote=<check-id>` — write `"cadence": "monthly"` for that check to the overlay.
- `approve=<remediation-id>` — write the approval to `<StateBase>/state/approvals.json` per
  `references/shared/approvals.md`. A supplied `approve=` argument IS the explicit user decision;
  never approve a remediation not named in the arguments or the interview.

Reject an argument targeting an unknown check id or remediation with the same message `check` would
give, rather than writing a dangling entry.

**Interview** (no write arguments AND an interactive session), one decision at a time:

1. **Read current state first** and present the `check` summary: checks shipped, checks patched by
   the overlay, approvals granted, proposals awaiting a decision.
2. **Walk pending proposals.** For each `<StateBase>/TODO.md` proposal, present it with a
   recommendation, apply the user's decision to the overlay, and mark the proposal resolved in
   `TODO.md`.
3. **Interview catalog changes** against the merged view: disable (`"enabled": false`), retire
   (`"deprecated": true` + `deprecation_reason`), or demote to monthly (`"cadence": "monthly"`).
4. **Register custom checks** when the user wants one (always interactive — it authors a script):
   write the script to `<StateBase>/scripts/windows/checks/Test-<Thing>.ps1` (single JSON object per
   `references/shared/output-schema.md`, `-Human` mode included), then add a full schema-valid
   overlay entry with `script` set to `scripts/windows/checks/Test-<Thing>.ps1`. Merge and resolution
   semantics: `${CLAUDE_PLUGIN_ROOT}/skills/audit/references/shared/catalog-overlay.md`.
5. **Offer remediation approvals.** The two shipped remediations (`restart-stopped-service`,
   `clear-temp-files`) default to not approved. Present each with its risk posture from
   `references/windows/remediation-policy.md`; on an explicit yes, write the approval per
   `references/shared/approvals.md`. Never enable a remediation the user did not explicitly approve.
6. **Confirm the report directory.** Show where reports land (the `report_dir` plugin option when
   set, else `$env:USERPROFILE\Documents\MachineHealth`); to change it, direct the user to
   `/plugin configure machine-health` (interactive, any time) — the option is stored in plugin
   config, not the overlay. Headless: `--config` only applies on a fresh install (ignored once
   installed), so reconfigure via `claude plugin uninstall machine-health` then
   `claude plugin install machine-health@<marketplace> --config report_dir=<path>`; this skill never
   writes user settings or `pluginConfigs`.

Re-running `apply` after everything is already set changes nothing and reports "already configured".

## Output

An updated `<StateBase>/catalog/checks.local.jsonc` (and `approvals.json` when approvals changed),
plus a one-paragraph summary of what changed and how to re-run this setup to reconfigure. `check`
alone reports the effective configuration and changes nothing.

## What this skill does NOT do

- Run the audit — that is `/machine-health:audit`.
- Edit the shipped catalog or anything inside the plugin install directory — a plugin update
  replaces it; machine-local changes live only under `<StateBase>`.
- Approve remediations silently — every approval is an explicit user decision (an `approve=`
  argument or an interview yes).
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
