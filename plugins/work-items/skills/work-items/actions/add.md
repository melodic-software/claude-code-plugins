# Action: `add`

Create a new work item with labels from the taxonomy.

**Defaults applied by this action:**

- **Priority** — when the `--priority` flag is absent, apply `priority:p3-low` (include it in the labels array built below).
- **Body template** — when `--body` is not provided, fall back to the default skeleton: a `## Context` paragraph (what observation surfaced this issue, what's the cost of leaving it), a `## Proposed work` bullet list (concrete next actions), `## Acceptance criteria` (one verifiable assertion per bullet), and `## References` (cross-references to rules, files, prior PRs, or external docs). The concrete body the workflow builds is detailed in step "Build body" below.
- **Label taxonomy** — labels are validated against the group structure documented in [`../reference/label-taxonomy.md`](../reference/label-taxonomy.md).

## Usage

```
add [--category <name>] [--type <type>] [--area <area>] [--ecosystem <eco>] [--priority <p>] [--recurring --cadence <cadence>] [--context "summary"] "Item description"
```

## Flags

- `--category <name>` -- Category label. Valid values are the consuming repo's `category:` labels ([`../reference/label-taxonomy.md`](../reference/label-taxonomy.md)). Default: `general` ONLY when the repo actually has a `category:general` label (check `gh label list`); otherwise omit the category label entirely
- `--type <type>` -- Type label (default: `chore`). Valid: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `perf`
- `--area <area>` -- Area label (the consuming repo's `area:` labels)
- `--ecosystem <eco>` -- Ecosystem label (the consuming repo's `ecosystem:` labels)
- `--priority <p>` -- Priority label (e.g., `p0-critical`, `p1-high`, `p2-medium`, `p3-low`)
- `--recurring` -- Mark as recurring. Requires `--cadence`
- `--cadence <c>` -- One of: `weekly`, `biweekly`, `monthly`, `quarterly`, `semi-annual`, `annual`
- `--context "summary"` -- Add research context to the issue body
- `--agent-ready` -- Apply `agent-ready` meta label and use the agent-brief body template ([`../reference/agent-brief.md`](../reference/agent-brief.md)). Brief format: behavioral (not procedural), no file paths, complete acceptance criteria, explicit scope boundaries. Use for issues intended for AFK agent execution
- `--force` -- Skip duplicate check

## Workflow

> **Authorization gate (BEFORE any step below).** Never file an issue on inferred intent. A topic the user raised, "they'd want it tracked", or approval of a related *direction* is NOT authorization to create an outward-facing artifact. An explicit user `add ...` invocation IS the authorization; model-initiated filing is not. If you only *infer* an issue should exist: draft the title + body and ASK first, or keep a local working note instead.

1. Parse the item text and flags from arguments.

1. **Duplicate check** (skip if `--force`) — search before creating (read — bare `gh`):

```bash
gh issue list --search "<title keywords>" --state all --json number,title,state --limit 10 | tr -d '\r'
```

If a potential duplicate is found (similar title), present it: "Similar issue found: **#N {title}** ({state}). Add anyway, merge, or skip?"

1. **Build labels array.** A group default applies ONLY when no flag supplied a label for that group — `--type fix` replaces `type:chore`, `--priority p1-high` replaces `priority:p3-low`, `--category x` replaces `category:general` (one label per group). Every label must also exist in the repo — `gh issue create` fails on unknown labels — so filter the resolved set against the live label list. When a default label doesn't exist, either offer to create the universal set once (`gh label create`) or omit that label:

```bash
EXISTING=$(gh label list --limit 200 --json name --jq '.[].name' | tr -d '\r')
# Resolve one label per group first (flag value wins over the group default),
# then keep only labels that exist in the repo.
LABELS=""
for l in "type:${TYPE:-chore}" "priority:${PRIORITY:-p3-low}" "category:${CATEGORY:-general}" <other flag-specified...>; do
  grep -qxF "$l" <<<"$EXISTING" && LABELS="$LABELS --label $l"
done
```

1. **Build body.** If `--agent-ready`, use the agent-brief template from [`../reference/agent-brief.md`](../reference/agent-brief.md) (Type, Summary, Current behavior, Desired behavior, Key interfaces, Acceptance criteria, Out of scope). Otherwise use the default template:

```markdown
## Context

{what observation surfaced this issue; the cost of leaving it — from the description and --context}

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

1. **Create the issue** (write). If `--recurring`, prefix the title with `[Maintenance]` — the convention that enables dedup and `recheck` matching against the recurring schedule:

Pass the generated body via `--body-file` (never inline `--body` — generated text can contain quotes, backticks, or `$()` that the shell would interpret):

```bash
BODY_FILE=$(mktemp)
# Write the composed body to $BODY_FILE with the Write tool (not shell interpolation)
gh issue create \
  --title "[Maintenance] {title}" \
  --body-file "$BODY_FILE" \
  $LABELS \
  | tr -d '\r'
rm -f "$BODY_FILE"
```

For non-recurring issues, omit the `[Maintenance]` prefix.

1. **If `--recurring`:** Also add the item to the consuming repo's `.github/recurring-schedule.json` (create the file with an `{"items": []}` skeleton if the repo has opted into recurring scheduling but the file doesn't exist yet — ask first if the repo has no recurring setup at all):

```json
{
  "id": "kebab-case-id",
  "title": "Title text",
  "cadence": "quarterly",
  "area": ["<area>"],
  "category": "<category>",
  "triggers": [],
  "last_checked": "2026-04-08",
  "next_due": "2026-07-07",
  "notes": "Description text.",
  "close_previous": true
}
```

Read the current file, append the new item to the `items` array, write it back. Compute `next_due` from today + cadence duration.

Also add the `recurring` and `cadence:{cadence}` labels to the issue — route them through the same existence filter as step "Build labels array" (create the missing label once via `gh label create`, or omit it; never pass a label the repo lacks).

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
