# Action: `audit`

Detect stale claims, orphaned recurring entries, and label hygiene issues.

## Usage

```
/work-items:track audit
```

## Checks

Before any tracker read, resolve `recurring-maintenance` from `.work-item-tracker.json`
`config.role_labels`, using `recurring` only when the file or entry is absent — and warn loudly when
it defaults for that reason (surface it, never silent). Stop on a malformed, empty, or non-string
configured value. Keep the resolved string for every recurring-item query and
comparison in this audit.

### 1. Stale claims

A claim is a lease; the `reclaim` verb is the SSOT for staleness (activity-check + outcome semantics: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Lease protocol"). Enumerate currently-assigned items (adapter: "List items", assigned filter — rows carry `number`), resolve each `number` to a fully-qualified id (adapter: "Resolve item ID"; `reclaim` rejects a bare number), and run `reclaim` on each id — idempotent, safe to run repeatedly:

```bash
TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
[[ -f "$TRACKER" ]] || TRACKER="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh"
"$TRACKER" reclaim "<id>"
```

Present each item the verb reports `reclaimed: true` (released — the `reason` field says why); `reclaimed: false` means still-held or lease-renewed, left in place. Legacy label-based holds from before the seam are migrated by the label-reconciliation pass, not here.

Exit `6` (capability-unsupported, CONTRACT.md "Exit codes") means the bound provider declares `reclaim: false` (e.g. `local-markdown`) — not an error; report zero stale claims for this pass instead of failing the audit.

A **harness denial of the `reclaim` call itself** takes the same posture. Under auto mode the permission classifier can refuse the Bash tool call before the script runs, so neither an exit code nor the JSON the presentation step above consumes is produced (CONTRACT.md "Exit codes"; observed on `#1381`). Report the denial once and skip the stale-claim pass — reporting it as skipped, not as zero stale claims, since nothing was checked — then continue the audit's remaining passes. Never retry the denied call, and never self-widen permissions to work around it (`${CLAUDE_PLUGIN_ROOT}/reference/permission-preflight.md` "Why a preflight, not a fixer").

### 2. Orphaned recurring entries

Entries in `.github/recurring-schedule.json` with no corresponding open or recently-closed item (skip when the repo has no recurring schedule). Only **due** entries can be orphaned — the automation creates an item only once `next_due <= today`, so a healthy future entry legitimately has no open item and is NOT orphaned:

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq -r --arg today "$(date +%Y-%m-%d)" \
    '.items[] | select(.next_due != null and .next_due <= $today) | .title' "$SCHEDULE"
fi
```

List open recurring items (adapter: "List items", `--label <resolved recurring-maintenance label>`,
`--state all`, bare read) and cross-reference: schedule items without a matching item are orphaned.
The recurring workflow titles items `[Maintenance] {title}`, so strip the prefix when comparing.

### 3. Unlabeled items + label conflicts

Items missing their **type** classification (org repos: no native Issue Type set; personal / non-org repos: no `type:*` label), missing an expected `category:*` label, or carrying conflicting labels (e.g. two `priority:*`) surface via the hygiene projections in the bound adapter's operations reference (GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md` "Aggregate / count (dashboard + hygiene)" — bare reads). On org repos the type axis is a native Issue Type, so absence of a `type:*` label is **not** a defect — read the native type field for the presence check.

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

### Unclassified Items
| # | Item | Missing |
|---|------|---------|
| 1 | #55 Something | No issue type set |

### Label Conflicts
(none found)

**Summary:** X stale claims reclaimed, Y orphaned entries, Z unlabeled items
```

## Notes

- The `reclaim` verb never releases a live lease — a session actively working an item is safe.
- Run periodically (weekly) or before `/work-items:work` (which also reclaims at session start) to keep the tracker clean.
