# Action: `due`

Show recurring items that are past their `next_due` date.

## Usage

```
/work-items:track due
```

## Workflow

1. **Resolve the recurring-maintenance role label before any tracker read.** Read
   `.work-item-tracker.json` at action entry and resolve
   `config.role_labels["recurring-maintenance"]`; use `recurring` only when the file or entry is
   absent — and warn loudly when it defaults for that reason (surface it, never silent). Stop on a
   malformed, empty, or non-string configured value. Use the resolved string in every adapter filter
   below.

1. **Read the recurring schedule:**

Read `.github/recurring-schedule.json` and filter items where `next_due <= today`. When the file is absent, report "no recurring schedule configured" and stop. Use jq for the initial filter:

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq --arg today "$(date +%Y-%m-%d)" '
    [.items[] | select(.next_due != null and .next_due <= $today)]
    | sort_by(.next_due)
    | map({id, title, cadence, last_checked, next_due})
  ' "$SCHEDULE"
else
  echo "no recurring schedule configured"
fi
```

For days-overdue computation, calculate `(today - next_due)` in days. jq lacks date arithmetic, so compute this when presenting the table (parse the ISO dates and subtract).

1. **Cross-reference with open items.** For each due recurring item, check if one already exists
   (adapter: "List items", `--label <resolved recurring-maintenance label>`, bare read). Match against
   the FULL expected title `[Maintenance] {schedule item title}` — never by the bare `[Maintenance]`
   prefix alone (that would let any recurring item satisfy every due row), and never by a
   prefix/substring of the title (a shorter title would spuriously match a longer item).

1. **Check for orphaned entries.** Only **due** entries can be orphaned — the recurring automation creates a tracker item only once an entry reaches `next_due <= today`, so a healthy future entry (`next_due > today`) legitimately has no open item and is NOT orphaned. Filter to due entries before flagging missing items:

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq -r --arg today "$(date +%Y-%m-%d)" \
    '.items[] | select(.next_due != null and .next_due <= $today) | .id' "$SCHEDULE"
fi
```

1. **Present:**

```markdown
## Recurring Items Due

| # | Item | Cadence | Last Checked | Days Overdue | Open Item |
|---|------|---------|-------------|--------------|-----------|
| 1 | Review Directory.Packages.props | quarterly | 2026-03-23 | 15 | #52 |
| 2 | Review biome.json | quarterly | 2026-03-23 | 15 | -- |

**Orphaned entries** (in schedule but no matching item):
- {id}: {title} -- create item or remove entry
```

If nothing is due: "All recurring items are current. Next due: **{item}** on **{date}**."

## Notes

- Cadence is a minimum interval, not a lock. On-demand rechecks are always allowed via `/work-items:track recheck`.
- The `triggers` field in each schedule item lists external events that warrant early recheck regardless of cadence.
- When the user mentions a trigger event (e.g., ".NET 10.1 shipped"), proactively suggest relevant rechecks even if they aren't technically due yet.

## Documentation freshness (optional)

After presenting due items, when the user asks for a doc audit or maintenance is the focus, hand off to the consuming repo's documentation-audit tooling if it provides one (e.g. a doc-drift subagent or skill scoped to the repo's docs and rules) and surface the summary alongside the due table. Degrade gracefully — skip when no such tooling is present.
