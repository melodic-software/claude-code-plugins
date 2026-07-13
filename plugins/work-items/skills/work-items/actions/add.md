# Action: `add`

Create a new work item with labels from the taxonomy.

**Defaults applied by this action:**

- **Priority** — when the `--priority` flag is absent, apply `priority:p3-low`.
- **Body template** — when `--body` is not provided, fall back to the default skeleton: a `## Context` paragraph (what observation surfaced this item, what's the cost of leaving it), a `## Proposed work` bullet list (concrete next actions), `## Acceptance criteria` (one verifiable assertion per bullet), and `## References` (cross-references to rules, files, prior PRs, or external docs). The concrete body the workflow builds is detailed in step "Build body" below.
- **Label taxonomy** — labels are validated against the 8-group structure documented in [`../reference/label-taxonomy.md`](../reference/label-taxonomy.md).

## Usage

```
/work-items:work-items add [--category <name>] [--type <type>] [--area <area>] [--ecosystem <eco>] [--priority <p>] [--recurring --cadence <cadence>] [--context "summary"] "Item description"
```

## Flags

- `--category <name>` -- Category label. Valid values are the consuming repo's `category:` labels (see [`../reference/label-taxonomy.md`](../reference/label-taxonomy.md)); default `general` only when the repo actually defines a `category:general` label, otherwise omit the category label
- `--type <type>` -- Type label (default: `chore`). Valid: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `perf`
- `--area <area>` -- Area label — the consuming repo's `area:` labels (see [`../reference/label-taxonomy.md`](../reference/label-taxonomy.md))
- `--ecosystem <eco>` -- Ecosystem label — the consuming repo's `ecosystem:` labels (see [`../reference/label-taxonomy.md`](../reference/label-taxonomy.md))
- `--priority <p>` -- Priority label (e.g., `p0-critical`, `p1-high`, `p2-medium`, `p3-low`)
- `--recurring` -- Mark as recurring. Requires `--cadence`
- `--cadence <c>` -- One of: `weekly`, `biweekly`, `monthly`, `quarterly`, `semi-annual`, `annual`
- `--context "summary"` -- Add research context to the item body
- `--agent-ready` -- Apply `agent-ready` meta label and use agent-brief body template (see [`reference/agent-brief.md`](../reference/agent-brief.md)). Brief format: behavioral (not procedural), no file paths, complete acceptance criteria, explicit scope boundaries. Use for items intended for AFK agent execution
- `--force` -- Skip duplicate check

## Workflow

> **Authorization gate (BEFORE any step below).** Never file a work item on inferred intent. A topic the user raised, "they'd want it tracked", or approval of a related *direction* is NOT authorization to create an outward-facing artifact — those need explicit authorization. An explicit user `/work-items:work-items add ...` invocation IS the authorization; model-initiated filing is not. If you only *infer* an item should exist: draft the title + body, ASK first, OR write a local `.work/<slug>/` note instead.

1. Parse the item text and flags from arguments.

1. **Duplicate check** (skip if `--force`) — the search-before-create pre-flight (adapter: "Search items", `--state all`, bare read). If a potential duplicate is found (similar title), present it: "Similar item found: **#N {title}** ({state}). Add anyway, merge, or skip?"

1. **Build labels list** `{labels}` (comma-separated for the seam) from the flags. Start from the group defaults `type:chore,priority:p3-low,category:general` and replace each group's default with any supplied `--type`/`--priority`/`--category` value (one label per group); append `--area`/`--ecosystem` labels when provided. When `--agent-ready` is set, also append the `agent-ready` meta label so the item is eligible for autonomous pickup. A default that the consuming repo doesn't define is omitted rather than passed.

1. **Build body.** If `--agent-ready`, use the agent-brief template from [`reference/agent-brief.md`](../reference/agent-brief.md) (Category, Summary, Current behavior, Desired behavior, Key interfaces, Acceptance criteria, Out of scope). Otherwise use the default template:

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

1. **Create the item** via the seam (`create-item` routes the write through the adapter's identity policy). If `--recurring`, prefix the title with `[Maintenance]` to match the convention used by the recurring-issues automation (enables dedup and `recheck` matching). Write the composed body to a temp file with the Write tool and pass it argv-safe — **never** inline the generated body, which can contain quotes, backticks, or `$()` the shell would interpret before the seam sees it:

```bash
BODY_FILE=$(mktemp)
# Write the composed body to "$BODY_FILE" with the Write tool NOW — before create-item —
# not via shell interpolation. "$(cat "$BODY_FILE")" then passes the file content as one
# literal argument the shell never re-parses.
"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh" create-item \
  --title "[Maintenance] {title}" \
  --body "$(cat "$BODY_FILE")" \
  --labels "{labels}"
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

Read the current file, append the new item to the `items` array, write it back. Compute `next_due` from today + cadence duration. Also add the `recurring` and `cadence:{cadence}` labels to the item.

1. Confirm: "Created **#{number}**: {title} (labels: {labels})"

## Cadence Duration Table

| Cadence | Days |
|---------|------|
| `weekly` | 7 |
| `biweekly` | 14 |
| `monthly` | 30 |
| `quarterly` | 90 |
| `semi-annual` | 180 |
| `annual` | 365 |
