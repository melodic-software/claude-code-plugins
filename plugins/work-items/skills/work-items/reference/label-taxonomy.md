# Label taxonomy

The label prefix structure consumed by every action that creates, queries, or filters work items. This document describes the **grammar** (which axes exist and what each encodes); it does **not** enumerate the members of each axis. Members are owned elsewhere and discovered live, so this file can never drift from the deployed set:

- **Repositories with label-as-code** — the consuming repository declares its source of truth and
  write policy. Discover live members through the bound adapter (for GitHub, `gh label list`) and
  route requested taxonomy changes to that declared owner.
- **Type axis is not a label on org repos** — it is a **native GitHub Issue Type** (`Bug` / `Feature` / `Task`, single-select, org-managed). Actions set it through the seam, never as a `type:` label. Personal / non-org repos (no native Issue Types) keep `type:` labels as the fallback.

UNIVERSAL axes work in any repo; PROJECT-SPECIFIC axes carry the consuming repo's concrete values. When no taxonomy enforcement is desired, actions accept any label without a prefix check; by default, actions validate labels against the axes below.

## Universal axes

These axes work in any repo and don't change per team. Do not snapshot their members here — read them from the SSOT / live set.

| Axis | Mechanism | What it encodes |
|------|-----------|-----------------|
| Type | native Issue Type (org) · `type:` label (personal/non-org) | The kind of issue: `Bug` (broken vs. intent), `Feature` (new capability), `Task` (any other tracked work — maintenance, refactor, tests, docs, audits, chores). Commit-type granularity (`fix`/`feat`/`chore`/`docs`/`refactor`/`test`/`build`/`perf`) stays at the commit layer, not the issue axis. |
| Priority | `priority:` | Urgency. Members from the live set. |
| Status | `status:` | Exception and gate flags only (e.g. `needs-info`, `needs-decision`, `ready`, `needs-triage`). Members from the live set. **Claim is not a status label** — it is assignee + lease (see the seam claim protocol). **Blocked is not a status label** — it is a native `blocked-by` dependency edge. |
| Meta | (none) | Tool-owned flat markers the automation sets: `automated`, `good-first-issue`, `migrated`, `stale`, plus the three canonical-role labels (defaults `agent-ready`, `needs-human`, `recurring` — see "Canonical roles" below). |
| Cadence | `cadence:` | Recurrence period for maintenance items. Members from the live set. |

## Canonical roles

Three meta-axis members are **canonical roles**: skill and action prose speaks the role name, and
the repo-actual label string resolves from the tracker binding — `.work-item-tracker.json`, key
`config.role_labels`. When the key (or an individual role entry) is absent, the defaults below
apply, so existing repos need zero migration.

| Role | Default label | What it marks |
|------|---------------|---------------|
| `autonomous-eligible` | `agent-ready` | Fully specified and briefed; eligible for autonomous (AFK) pickup from the frontier |
| `human-gated` | `needs-human` | Needs human judgment (design decision, UX review, manual QA); excluded by `list-frontier --autonomous` |
| `recurring-maintenance` | `recurring` | A scheduled maintenance item reconciled against `.github/recurring-schedule.json` |

Binding shape (every entry optional; unlisted roles keep their defaults):

```json
{
  "config": {
    "role_labels": {
      "autonomous-eligible": "agent-ready",
      "human-gated": "needs-human",
      "recurring-maintenance": "recurring"
    }
  }
}
```

Resolve the mapping once per session and use the resolved strings wherever a role is meant. Two
constraints on remapping:

- **`human-gated` is shared with the seam.** `list-frontier --autonomous` excludes items by that
  label, and the shipped seam reads `needs-human`; remap this role only when the bound seam
  resolves the same `config.role_labels` key, or the frontier filter and the skill will disagree.
- **The remapped label must exist** in the consuming repo (or route through its label-as-code
  owner) — the same never-create-ad-hoc rule as every other label.

`/work-items:setup` offers the remap interview and writes the binding key.

## Project-specific axes

The consuming repo defines the members of these axes to match its own architecture surface, domain categorization, and language/toolchain mix. Discover the live set from the bound adapter's label listing (for the GitHub adapter, `tools/work-item-tracker/adapters/github/README.md` — e.g. `gh label list`).

| Axis | Prefix | What it encodes |
|------|--------|-----------------|
| Area | `area:` | The repo's architecture surface (modules, apps, infrastructure lanes, cross-cutting concerns) |
| Category | `category:` | Domain categorization of the work (e.g. testing, general) |
| Ecosystem | `ecosystem:` | Language/toolchain (e.g. dotnet, python, typescript, bash) |

When a project-specific axis has no labels in the consuming repo, actions simply omit that axis — no validation error.

**New labels are never created ad hoc.** When the repository declares a label-management source of
truth, route changes to that owner and keep actions read-only. Otherwise, creating a label requires
the user's explicit authorization and the repository's documented contribution process; discovery
and validation alone never imply write permission.
