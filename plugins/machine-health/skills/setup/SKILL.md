---
name: setup
description: "Configure the machine-health plugin for this machine: review the check catalog, write the machine-local overlay (disable/deprecate/demote checks, register custom ones), and optionally seed remediation approvals. Use when: 'set up machine-health', 'configure machine health', 'disable a health check', 'approve a remediation', 'add a custom health check', or the audit skill proposes catalog changes needing approval. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Write (or update) the machine-local configuration that customizes `/machine-health:audit`
on this host: the catalog overlay at `<StateBase>/catalog/checks.local.jsonc` and the remediation
approvals at `<StateBase>/state/approvals.json`. Idempotent: re-running reads the existing files and
offers updates rather than overwriting blind.

## Resolving the state root

`<StateBase>` is `${CLAUDE_PLUGIN_DATA}` — the per-plugin data directory that survives plugin
updates. If that token is unexpanded (running outside plugin context), default to
`$HOME/.claude/plugins/data/machine-health`. Create it if missing. Configuration here is
machine-local by design — a workstation's check tuning does not belong in any repository.

## Task

1. **Read current state first.** Load the shipped catalog
   (`${CLAUDE_PLUGIN_ROOT}/skills/audit/catalog/checks.jsonc`), the existing overlay and
   approvals files when present, and `<StateBase>/TODO.md` (pending proposals from prior runs).
   Present a short summary: checks shipped, checks patched by the overlay, approvals granted,
   proposals awaiting a decision.
2. **Walk pending proposals.** For each `<StateBase>/TODO.md` proposal (deprecation, cadence
   demotion, new check), present it with a recommendation and apply the user's decision to the
   overlay; mark the proposal resolved in `TODO.md`.
3. **Interview catalog changes, one decision at a time.** Offer per-check tuning against the merged
   view: disable (`"enabled": false`), retire (`"deprecated": true` + `deprecation_reason`), or
   demote to monthly (`"cadence": "monthly"`). Only write entries that differ from the shipped
   catalog — the overlay stays minimal.
4. **Register custom checks** when the user wants one: write the script to
   `<StateBase>/scripts/windows/checks/Test-<Thing>.ps1` (single JSON object per
   `references/shared/output-schema.md`, `-Human` mode included), then add a full schema-valid
   entry to the overlay with `script` set to `scripts/windows/checks/Test-<Thing>.ps1`. Merge and
   resolution semantics: `${CLAUDE_PLUGIN_ROOT}/skills/audit/references/shared/catalog-overlay.md`.
5. **Offer remediation approvals.** The two shipped remediations (`restart-stopped-service`,
   `clear-temp-files`) default to not approved. Present each with its risk posture from
   `references/windows/remediation-policy.md`; on an explicit yes, write the approval to
   `<StateBase>/state/approvals.json` per `references/shared/approvals.md`. Never enable a
   remediation the user did not explicitly approve in this conversation.
6. **Confirm the report directory.** Show where reports currently land (the `report_dir` plugin
   option when set, else `$env:USERPROFILE\Documents\MachineHealth`); to change it, point the user
   at `/plugin configure machine-health` (the option is stored in plugin config, not in the overlay).

## Output

An updated `<StateBase>/catalog/checks.local.jsonc` (and `approvals.json` when approvals changed),
plus a one-paragraph summary of what changed and how to re-run this setup to reconfigure.

## What this skill does NOT do

- Run the audit — that is `/machine-health:audit`.
- Edit the shipped catalog or anything inside the plugin install directory — a plugin update
  replaces it; machine-local changes live only under `<StateBase>`.
- Approve remediations silently — every approval is an explicit user decision.
