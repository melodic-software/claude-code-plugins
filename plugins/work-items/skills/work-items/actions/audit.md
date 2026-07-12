# Action: `audit`

Detect stale claims, orphaned recurring entries, and label hygiene issues.

## Usage

```
/work-items audit
```

## Checks

### 1. Stale claims

A claim is a lease; the `reclaim` verb is the SSOT for staleness (activity-check + outcome semantics: `tools/work-item-tracker/CONTRACT.md` "Lease protocol"). Enumerate currently-assigned items (adapter: "List items", assigned filter — rows carry `number`), resolve each `number` to a fully-qualified id (adapter: "Resolve item ID"; `reclaim` rejects a bare number), and run `reclaim` on each id — idempotent, safe to run repeatedly:

```bash
tools/work-item-tracker/work-item-tracker.sh reclaim "<id>"
```

Present each item the verb reports `reclaimed: true` (released — the `reason` field says why); `reclaimed: false` means still-held or lease-renewed, left in place. Legacy label-based holds from before the seam are migrated by the label-reconciliation pass, not here.

### 2. Orphaned recurring entries

Entries in `.github/recurring-schedule.json` with no corresponding open or recently-closed item:

```bash
cat .github/recurring-schedule.json | jq -r '.items[].title'
```

List open recurring items (adapter: "List items", `--label recurring`, `--state all`, bare read) and cross-reference: schedule items without a matching item are orphaned. The recurring workflow titles items `[Maintenance] {title}`, so strip the prefix when comparing.

### 3. Unlabeled items + label conflicts

Items missing expected labels (no `type:*`, no `category:*`) and items with conflicting labels (e.g. two `priority:*`) surface via the hygiene projections in the bound adapter's operations reference (GitHub: `tools/work-item-tracker/adapters/github/README.md` "Aggregate / count (dashboard + hygiene)" — bare reads).

## Output

```markdown
## Work Items Audit

### Stale Claims (reclaimed)
| # | Item | Assigned | Last Update | Result |
|---|------|----------|-------------|--------|
| 1 | #42 Fix analyzer | @agent1 | 36h ago | released (no activity) |

### Orphaned Recurring Entries
| # | Schedule Item | Status |
|---|--------------|--------|
| 1 | Review biome.json | No matching item |

### Unlabeled Items
| # | Item | Missing |
|---|------|---------|
| 1 | #55 Something | No type:* label |

### Label Conflicts
(none found)

**Summary:** X stale claims reclaimed, Y orphaned entries, Z unlabeled items
```

## Notes

- The `reclaim` verb never releases a live lease — a session actively working an item is safe.
- Run periodically (weekly) or before `/work-items work` (which also reclaims at session start) to keep the tracker clean.
