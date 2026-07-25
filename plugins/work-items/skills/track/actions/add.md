# Action: `add`

Create a new work item with labels from the taxonomy.

**Defaults applied by this action:**

- **Priority** — when the `--priority` flag is absent, apply the live `priority:` set's lowest-urgency member, resolved from the bound adapter at action entry (e.g. `priority: low`, if present; [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Universal axes") — an untriaged-signal floor, not a priority assessment. Omit the label when the repo's live set has no such member.
- **Body template** — when `--body` is not provided, fall back to the default skeleton: a `## Context` paragraph (what observation surfaced this item, what's the cost of leaving it), a `## Proposed work` bullet list (concrete next actions), `## Acceptance criteria` (one verifiable assertion per bullet), and `## References` (cross-references to rules, files, prior PRs, or external docs). The concrete body the workflow builds is detailed in step "Build body" below.
- **Label taxonomy** — labels are validated against the 8-group structure documented in [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md).
- **Title shape** — the item title follows the convention in [`${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md`](${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md).

## Usage

```
/work-items:track add [--category <name>] [--type <type>] [--area <area>] [--ecosystem <eco>] [--priority <p>] [--recurring --cadence <cadence>] [--context "summary"] "Item description"
```

## Flags

- `--category <name>` -- Category label. Valid values are the consuming repo's `category:` labels (see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md)); default `general` only when the repo actually defines a `category:general` label, otherwise omit the category label
- `--type <type>` -- The issue's type (default: `task`). Accepts the commit-style inputs `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `perf` and maps them to the coarse issue type: `fix` → **Bug**, `feat` → **Feature**, everything else → **Task**. On **org repos** the type is a **native GitHub Issue Type** set through the seam (not a `type:` label); on **personal / non-org repos** (no native Issue Types) it becomes a coarse `type: bug`/`type: feature`/`type: task` label instead
- `--area <area>` -- Area label — the consuming repo's `area:` labels (see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md))
- `--ecosystem <eco>` -- Ecosystem label — the consuming repo's `ecosystem:` labels (see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md))
- `--priority <p>` -- Priority label; value must be one of the repo's live `priority:` members (see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Universal axes" — resolved live, never snapshotted here), e.g. `critical`, `high`, `medium`, `low` where the repo follows that convention
- `--recurring` -- Mark as recurring. Requires `--cadence`
- `--cadence <c>` -- One of: `weekly`, `biweekly`, `monthly`, `quarterly`, `semi-annual`, `annual`
- `--context "summary"` -- Add research context to the item body
- `--agent-ready` -- Apply the autonomous-eligible role label (default `agent-ready`; resolve per [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md) "Canonical roles") and use agent-brief body template (see [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md)). Brief format: behavioral (not procedural), no file paths, complete acceptance criteria, explicit scope boundaries. Use for items intended for AFK agent execution
- `--force` -- Skip duplicate check

## Workflow

> **Authorization gate (BEFORE any step below).** Never file a work item on inferred intent. A topic the user raised, "they'd want it tracked", or approval of a related *direction* is NOT authorization to create an outward-facing artifact — those need explicit authorization. An explicit user `/work-items:track add ...` invocation IS the authorization; model-initiated filing is not. If you only *infer* an item should exist: draft the title + body, ASK first, OR write a local note in the topic's memory slice (`<memory_dir>/<slug>/`, default `.work/`) instead.

1. Parse the item text and flags from arguments.

1. **Duplicate check** (skip if `--force`) — the search-before-create pre-flight (adapter: "Search items", `--state all`, bare read). If a potential duplicate is found (similar title), present it: "Similar item found: **#N {title}** ({state}). Add anyway, merge, or skip?"

1. **Rejected-concept check.** When the consuming repo keeps a rejected-concept ledger (`docs/out-of-scope/`, one file per concept), scan its concept files for a match with the incoming request — match by **concept similarity, not keyword** ("night theme" matches `dark-mode.md`). On a match, answer from the ledger instead of re-litigating: present the recorded rationale ("Rejected before — `docs/out-of-scope/<concept>.md`: <reason>. Still stand?"). If the user confirms the rejection stands, append the request to that file's "Prior requests" log (re-read the file from disk first; append a line, never rewrite the file) and stop without filing. If the user reconsiders, or the directory is absent, continue normally — no ledger, no check.

1. **Resolve the issue type** `{type}` from `--type` (default `task`), mapping the input to the coarse type: `fix` → `Bug`, `feat` → `Feature`, everything else → `Task`. **Org repos** (native Issue Types available): the type is applied through the seam as a native Issue Type, **not** a label — it is not part of `{labels}`. **Personal / non-org repos** (native-type mechanism unavailable): the type rides as a coarse long-form label instead — append `type: bug` / `type: feature` / `type: task` (colon-space, matching the reconciled naming) to `{labels}`. Determine which path applies from the bound adapter's capabilities (for the GitHub adapter, native Issue Types are an org-only feature).

1. **Build labels list** `{labels}` (comma-separated for the seam) from the remaining flags. Start from the group defaults — the live `priority:` set's lowest-urgency member (resolved per the "Priority" default above) and `category:general` — and replace each group's default with any supplied `--priority`/`--category` value (one label per group); append `--area`/`--ecosystem` labels when provided. When `--agent-ready` is set, also append the autonomous-eligible role label (default `agent-ready`) so the item is eligible for autonomous pickup. A default that the consuming repo doesn't define is omitted rather than passed.

1. **Build body.** If `--agent-ready`, use the agent-brief template from [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md) (Category, Summary, Current behavior, Desired behavior, Key interfaces, Acceptance criteria, Out of scope). Otherwise use the default template:

```markdown
## Context

{what observation surfaced this item; the cost of leaving it — from the description and --context}

## Proposed work

- {concrete next action derived from the description}

## Acceptance criteria

- [ ] {one verifiable assertion per bullet}

## References

- {cross-references to rules, files, prior PRs, or external docs — or "none"}

## Metadata

| Field | Value |
|-------|-------|
| Category | {category} |
| Area | {area or "unspecified"} |
| Ecosystem | {ecosystem or "unspecified"} |

{if --recurring: ## Recurring\n\nCadence: {cadence}\nTriggers: {triggers or "none configured"}}
```

1. **Create the item** via the seam (`create-item` routes the write through the adapter's identity policy). On org repos pass the resolved native Issue Type via the seam's `--type` passthrough (the adapter maps `Bug`/`Feature`/`Task` to the native GitHub Issue Type); on personal / non-org repos the type instead rode into `{labels}` in the resolve step, so omit `--type`. **When `--recurring` targets a repo with no `.github/recurring-schedule.json` yet, resolve the schedule bootstrap FIRST** (the ask-first path in the next step) — if the user declines the new schedule or it cannot be written, create the item **non-recurring** (drop the `[Maintenance]` prefix and the `recurring`/`cadence:` labels) or abort; never create a `[Maintenance]` item that `due`/`recheck` can never reconcile because no schedule row backs it. If `--recurring` and the schedule is in place, prefix the title with `[Maintenance]` to match the convention used by the recurring-issues automation (enables dedup and `recheck` matching). Write the composed body to a temp file with the Write tool and pass it argv-safe — **never** inline the generated body, which can contain quotes, backticks, or `$()` the shell would interpret before the seam sees it:

```bash
BODY_FILE=$(mktemp)
# Write the composed body to "$BODY_FILE" with the Write tool NOW — before create-item —
# not via shell interpolation. "$(cat "$BODY_FILE")" then passes the file content as one
# literal argument the shell never re-parses.
TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
[[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
"$TRACKER" create-item \
  --title "[Maintenance] {title}" \
  --body "$(cat "$BODY_FILE")" \
  --type "{type}" \
  --labels "{labels}"   # --type: org repos only (native Issue Type); on personal/non-org repos drop it — the type is already a type: label in {labels}
rm -f "$BODY_FILE"
```

For non-recurring items, omit the `[Maintenance]` prefix. The emitted item object carries the new `id` (fully-qualified) and `number`.

1. **If `--recurring`:** Also add the item to the consuming repo's `.github/recurring-schedule.json`. When the file does not exist yet, create it with an `{"items": []}` skeleton before appending (ask first if the repo has no recurring setup at all — without the schedule, `due`/`recheck` will never see the item):

```json
{
  "id": "kebab-case-id",
  "title": "Title text",
  "cadence": "quarterly",
  "area": ["<your-area>"],
  "category": "<your-category>",
  "triggers": [],
  "last_checked": "2026-04-08",
  "next_due": "2026-07-07",
  "notes": "Description text.",
  "close_previous": true
}
```

Re-read the current file from disk immediately before the write — the schedule is shared and another session may have appended since it was last in context — then append the new item to the `items` array and write it back, preserving every existing row. Compute `next_due` from today + cadence duration. Also add the recurring-maintenance role label (default `recurring`) and the `cadence:{cadence}` label to the item.

1. Confirm: "Created **#{number}**: {title} (type: {type}, labels: {labels})"

## Cadence Duration Table

| Cadence | Days |
|---------|------|
| `weekly` | 7 |
| `biweekly` | 14 |
| `monthly` | 30 |
| `quarterly` | 90 |
| `semi-annual` | 180 |
| `annual` | 365 |
