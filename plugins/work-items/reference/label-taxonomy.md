# Label taxonomy

The label prefix structure consumed by every action that creates, queries, or filters work items. This document describes the **grammar** (which axes exist and what each encodes); it does **not** enumerate the members of each axis. Members are owned elsewhere and discovered live, so this file can never drift from the deployed set:

- **Repositories with label-as-code**: the consuming repository declares its source of truth and
  write policy. Discover live members through the bound adapter (for GitHub, `gh label list`) and
  route requested taxonomy changes to that declared owner.
- **Type axis is not a label on org repos.** It is a **native GitHub Issue Type** (`Bug` / `Feature` / `Task`, single-select, org-managed). Actions set it through the seam, never as a `type:` label. Personal / non-org repos (no native Issue Types) keep `type:` labels as the fallback.

UNIVERSAL axes work in any repo; PROJECT-SPECIFIC axes carry the consuming repo's concrete values. When no taxonomy enforcement is desired, actions accept any label without a prefix check; by default, actions validate labels against the axes below.

## Universal axes

These axes work in any repo and don't change per team. Do not snapshot their members here. Read them from the SSOT / live set.

| Axis | Mechanism | What it encodes |
|------|-----------|-----------------|
| Type | native Issue Type (org) · `type:` label (personal/non-org) | The kind of issue: `Bug` (broken vs. intent), `Feature` (new capability), `Task` (any other tracked work: maintenance, refactor, tests, docs, audits, chores). Commit-type granularity (`fix`/`feat`/`chore`/`docs`/`refactor`/`test`/`build`/`perf`) stays at the commit layer, not the issue axis. |
| Priority | `Priority` issue field (org) · `priority:` label (no such field) | Urgency. Members from the live set: the field's options, else the labels. Set per [`tracker-seam.md`](tracker-seam.md) "Setting an item's priority". |
| Status | `status:` | Exception and gate flags only (e.g. `confirmed`, `ready`). Members from the live set. **Claim is not a status label.** It is assignee + lease (see the seam claim protocol). **Blocked is not a status label.** It is a native `blocked-by` dependency edge. The triage floor is not a status value. Where the tracker also keeps a `Work status` field, read an item's status per [`tracker-seam.md`](tracker-seam.md) "Reading an item's status". |
| Meta | (none) | Tool-owned flat markers the automation sets: `automated`, `good-first-issue`, `migrated`, `stale`, the triage floor `needs-triage` (bare; not a `priority:` or `status:` value), the idea-issue park `needs-spec` (bare; set by triage), the hold labels `needs-owner-decision` and `needs-reporter-info` (bare), plus the three canonical-role labels (defaults `agent-ready`, `needs-human`, and `recurring`, listed under "Canonical roles" below). |
| Cadence | `cadence:` | Recurrence period for maintenance items. Members from the live set. |
| Work class | `work-class:` | Semantic risk class (C1–C4), kept on older items as a record; nothing applies or reads it. C5 is marked on the provenance axis. Members: [`work-class-labels.md`](work-class-labels.md). Classification criteria: the `autonomy` plugin's [`work-classes.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/autonomy/reference/guardrails/work-classes.md). |
| Provenance | `provenance:` | Where an item came from. `provenance: untrusted` (C5) floors the item for a person and holds its merge; `provenance: signal` marks an item filed from a signal and floors it too. Members from the live set. |
| Capability tier | `capability-tier:` | Execution capability tier for the work-loop frontier quota guard. Canonical members and migration: [`capability-tier-labels.md`](capability-tier-labels.md). Absent label = general tier (fail-closed); body prose is never authority. |

## Canonical roles

Four labels are **canonical roles**: skill and action prose speaks the role name, and
the repo-actual label string resolves from the tracker binding (the `tracker` mapping of
`<home>/work-items.yaml`), key `config.role_labels`. When the key (or an individual role entry) is absent, the defaults below
apply, so existing repos need zero migration.

| Role | Default label | What it marks |
|------|---------------|---------------|
| `autonomous-eligible` | `agent-ready` | Fully specified and briefed; eligible for autonomous (AFK) pickup from the frontier |
| `human-gated` | `needs-human` | Needs human judgment (design decision, UX review, manual QA); excluded by `list-frontier --autonomous` |
| `recurring-maintenance` | `recurring` | A scheduled maintenance item reconciled against `.github/recurring-schedule.json` |
| `owner-decision` | `needs-owner-decision` | Parked on an owner's decision; the decision label `/work-items:morning-brief` lists and `/plugin-quality:audit` files an unresearched change under, and a hold label by default |

Binding shape (every entry optional; unlisted roles keep their defaults):

```json
{
  "config": {
    "role_labels": {
      "autonomous-eligible": "agent-ready",
      "human-gated": "needs-human",
      "recurring-maintenance": "recurring",
      "owner-decision": "needs-owner-decision"
    }
  }
}
```

Resolve the mapping at the start of every action invocation that uses a role and use the resolved
strings in every provider query and core-side label comparison for that invocation. Do not cache a
mapping across invocations: the tracked binding may change between them. An absent file or absent
entry falls back to the documented default **silently**, because `/work-items:setup` deliberately omits
entries that keep their default, so a conforming binding must not produce a standing warning every
lane pass. A present malformed, empty, or non-string entry is a configuration error, not permission to
fall back silently. Two constraints on remapping:

- **`human-gated` is shared with the seam.** `list-frontier --autonomous` excludes items by that
  label. The shipped seam resolves it from `config.role_labels`; a consumer-local adapter must
  resolve the same key, or the frontier filter and the skill will disagree.
- **The remapped label must exist** in the consuming repo (or route through its label-as-code
  owner), the same never-create-ad-hoc rule as every other label.

`/work-items:setup` offers the remap interview and writes the binding key.

### Container label

The seam's container marker (CONTRACT.md "Containers and state"), the label that makes an
ordinary item a navigable graph root (wayfind maps, decompose breakdowns/spec containers)
and keeps it off every frontier, resolves from the binding key `config.container_label`,
a **sibling** of `config.role_labels` (it marks a graph root, not a worker role), default
`work-map` when absent or empty. The same remap constraints as canonical roles apply: the
remapped label must exist (or route through the repo's label-as-code owner), and a repo
that already holds containers must relabel them when remapping, because the frontier exclusion is
an exact match against the resolved string.

### Hold lists and the wayfind prefix

The labels and Work status states that keep an item off the autonomous frontier, and the
wayfind label prefix, resolve from these `config` keys, siblings of `config.role_labels`.
An absent or empty key keeps its default; a present value of the wrong shape is a
configuration error.

| Key | Default | What it holds |
|-----|---------|---------------|
| `hold_labels` | the `owner-decision` role label, `needs-reporter-info`, `needs-spec` | Labels that wait on a person |
| `hold_states` | `needs-human`, `needs-owner-decision`, `needs-reporter-info`, `needs-spec` | Work status states that wait on a person |
| `hold_state_labels` | `needs-human`, the `owner-decision` role label, `needs-reporter-info`, `needs-spec` | The hold states' labels: an item carrying one has its hold decided by its labels |
| `wayfind_label_prefix` | `wayfind:` | The prefix of `/planning:wayfind`'s routing labels |

A remap of the `owner-decision` role reaches the two defaults that name it. A key set
explicitly replaces its whole default list.

### Recorded postures: fixed strings without a remap seam

Two strings adjacent to the `recurring-maintenance` role are **fixed by design today**. No
binding key remaps them (recorded posture per the consumer-configurability doctrine; #2942
F3.7):

- **`<!-- recurring-schedule id=<id> -->` body marker**: the exact-match key the recurring flows
  use to reconcile a schedule row with its open tracker item
  ([`issue-conventions.md`](issue-conventions.md) "Recurring marker"). Making it configurable is
  deferred until a consumer asks for a different marker; when that request lands it joins the
  binding as a sibling of `config.role_labels` (a `config` key, not a parallel mechanism), and
  every reader that convention names resolves it the same way role labels resolve.
- **`.github/recurring-schedule.json` path**: the schedule file's location. Deferred on the
  same first-request trigger; a future remap is a binding `config` key resolved once per
  invocation, never a second discovery climb.

Both strings participate in exact-match lookups against provider data, so a repo changing
either today would orphan existing recurring items and schedules, which is why the
remap, when it comes, arrives with a reconciliation step, not as a bare string swap.

## Project-specific axes

The consuming repo defines the members of these axes to match its own architecture surface, domain categorization, and language/toolchain mix. Discover the live set from the bound adapter's label listing (for the GitHub adapter, `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md`, e.g. `gh label list`).

| Axis | Prefix | What it encodes |
|------|--------|-----------------|
| Area | `area:` | The repo's architecture surface (modules, apps, infrastructure lanes, cross-cutting concerns) |
| Category | `category:` | Domain categorization of the work (e.g. testing, general) |
| Ecosystem | `ecosystem:` | Language/toolchain (e.g. dotnet, python, typescript, bash) |

When a project-specific axis has no labels in the consuming repo, actions simply omit that axis, with no validation error.

**New labels are never created ad hoc.** When the repository declares a label-management source of
truth, route changes to that owner and keep actions read-only. Otherwise, creating a label requires
the user's explicit authorization and the repository's documented contribution process; discovery
and validation alone never imply write permission.

## Skill-private routing markers

Not every label a work-items action encounters is general classification. Some are another
skill's own routing state on its own items, and this plugin is **read-only** on them. The current
example is the `wayfind: *` axis: declared by the consuming repo's label-as-code source of truth,
but applied and removed only by `/planning:wayfind`, on its own map sub-issues, at sub-issue
creation ("Never create labels ad hoc from this skill", per `/planning:wayfind` `SKILL.md` "Create or
extend the map issue"). No work-items skill applies, strips, or requires a `wayfind:` value on the
items it manages, and `list-frontier` leaves out every item carrying a `wayfind:` label, whatever
role label it carries, so `/work-items:work` never picks one. Members and semantics belong to the declaring
repo and `/planning:wayfind`, per the resolved decision `melodic-software/github-iac#179`, so they are
referenced here, not restated.
