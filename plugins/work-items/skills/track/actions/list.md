# Action: `list`

List work items with optional filtering.

## Usage

```
/work-items:track list [--category <name>] [--label <name>] [--state <open|closed|all>] [--assignee <login>] [--limit <n>] [--search <query>]
```

## Flags

- `--category <name>` -- Filter by category label (adds `category:<name>`; the consuming repo's `category:` values — see [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md))
- `--label <name>` -- Filter by any label (repeatable, AND logic)
- `--state <s>` -- `open` (default), `closed`, `all`
- `--assignee <login>` -- Filter by assignee (`@me` for self)
- `--limit <n>` -- Max results (default: 30, max per request: 100)
- `--search <query>` -- Free search using the bound provider's search syntax

## Workflow

1. List items filtered by the parsed flags (adapter: "List items" — bare read; category/label/state/assignee/limit map to the adapter's filter args; `--search` uses the adapter's "Search items" path). The adapter returns normalized item objects.

1. Parse the result and present as a condensed table:

```markdown
| # | Item | Type | Labels | Assignee | Updated |
|---|------|------|--------|----------|---------|
| 1 | #42 Fix <thing> | Bug | area: <your-area>, priority:p1-high | @user | 2d ago |
| 2 | #38 Review <config> | Task | area: <your-area> | -- | 5d ago |
```

The `#` column is a sequential index for this listing. When the user references an item by `#`, match it to the item in the most recent listing.

## Search syntax

Provider search qualifiers (label/exclude/assignee/sort/date) and the pass-through behavior of `--search` are documented in the bound adapter's operations reference — GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md` "Search items".
