# Label taxonomy

The label prefix structure consumed by every action that creates, queries, or filters work items. This document describes the **grammar** (which axes exist and what each encodes); it does **not** enumerate the members of each axis. Members are owned elsewhere and discovered live, so this file can never drift from the deployed set:

- **Org repos** — the universal axes are declared and deployed by the label-as-code SSOT (`melodic-software/github-iac`), the sole writer. Discover the live members with the bound adapter's label listing (for the GitHub adapter, `gh label list`).
- **Type axis is not a label on org repos** — it is a **native GitHub Issue Type** (`Bug` / `Feature` / `Task`, single-select, org-managed). Actions set it through the seam, never as a `type:` label. Personal / non-org repos (no native Issue Types) keep `type:` labels as the fallback.

UNIVERSAL axes work in any repo; PROJECT-SPECIFIC axes carry the consuming repo's concrete values. When no taxonomy enforcement is desired, actions accept any label without a prefix check; by default, actions validate labels against the axes below.

## Universal axes

These axes work in any repo and don't change per team. Do not snapshot their members here — read them from the SSOT / live set.

| Axis | Mechanism | What it encodes |
|------|-----------|-----------------|
| Type | native Issue Type (org) · `type:` label (personal/non-org) | The kind of issue: `Bug` (broken vs. intent), `Feature` (new capability), `Task` (any other tracked work — maintenance, refactor, tests, docs, audits, chores). Commit-type granularity (`fix`/`feat`/`chore`/`docs`/`refactor`/`test`/`build`/`perf`) stays at the commit layer, not the issue axis. |
| Priority | `priority:` | Urgency. Members from the live set / github-iac. |
| Status | `status:` | Exception and gate flags only (e.g. `needs-info`, `needs-decision`, `ready`, `needs-triage`). Members from the live set. **Claim is not a status label** — it is assignee + lease (see the seam claim protocol). **Blocked is not a status label** — it is a native `blocked-by` dependency edge. |
| Meta | (none) | Tool-owned flat markers the automation sets: `automated`, `recurring`, `agent-ready`, `needs-human`, `good-first-issue`, `migrated`, `stale`. |
| Cadence | `cadence:` | Recurrence period for maintenance items. Members from the live set. |

## Project-specific axes

The consuming repo defines the members of these axes to match its own architecture surface, domain categorization, and language/toolchain mix. Discover the live set from the bound adapter's label listing (for the GitHub adapter, `tools/work-item-tracker/adapters/github/README.md` — e.g. `gh label list`).

| Axis | Prefix | What it encodes |
|------|--------|-----------------|
| Area | `area:` | The repo's architecture surface (modules, apps, infrastructure lanes, cross-cutting concerns) |
| Category | `category:` | Domain categorization of the work (e.g. testing, general) |
| Ecosystem | `ecosystem:` | Language/toolchain (e.g. dotnet, python, typescript, bash) |

When a project-specific axis has no labels in the consuming repo, actions simply omit that axis — no validation error.

**New labels are never created ad hoc.** The SSOT (github-iac) is the sole writer of org-repo labels; a needed label is added via a github-iac PR, not `gh label create`. Actions only read and validate against the live set (they create labels only for a `ManagedLabels: false` opt-out repo that has no IaC-managed set).
