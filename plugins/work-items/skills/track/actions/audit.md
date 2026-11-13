# Action: `audit`

Detect stale claims, orphaned recurring entries, and label hygiene issues, and close decomposed parents whose children are done.

## Usage

```
/work-items:track audit
```

## Checks

Before any tracker read, resolve `recurring-maintenance` from `config.role_labels` of the binding
the seam resolves (the `tracker` mapping of `<home>/work-items.yaml`, else the legacy repo-root
JSON binding), using `recurring` when the file or entry is absent (the documented default,
no warning). Stop on a malformed, empty, or non-string configured value. Keep the resolved string
for every recurring-item query and comparison in this audit.

### 1. Stale claims

A claim is a lease; the `reclaim` verb is the SSOT for staleness (activity-check + outcome semantics: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/CONTRACT.md` "Lease protocol"). Enumerate currently-assigned items (adapter: "List items", assigned filter, whose rows carry `number`), resolve each `number` to a fully-qualified id (adapter: "Resolve item ID"; `reclaim` rejects a bare number), and run `reclaim` on each id. The verb is idempotent and safe to run repeatedly:

```bash
TRACKER="${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh"
[[ -f "$TRACKER" ]] || TRACKER="<project root>/tools/work-item-tracker/work-item-tracker.sh"
"$TRACKER" reclaim "<id>"
```

`<project root>` is the literal path [`tracker-seam.md`](../../../reference/tracker-seam.md) "Project root" resolves, in its own Bash call before this snippet and each later one in this file.

Present each item the verb reports `reclaimed: true` (released, with the `reason` field saying why); `reclaimed: false` means still-held or lease-renewed, left in place.

Exit `6` (capability-unsupported, CONTRACT.md "Exit codes") means the bound provider declares `reclaim: false` (e.g. `local-markdown`). That is not an error; report zero stale claims for this pass instead of failing the audit.

A **harness denial of the `reclaim` call itself** takes the same posture. The script never runs, so the presentation step above gets no JSON (CONTRACT.md "Exit codes"; [How auto mode evaluates actions](https://code.claude.com/docs/en/permission-modes#how-auto-mode-evaluates-actions)). Report the denial once and skip the stale-claim pass, reporting it as skipped, not as zero stale claims, since nothing was checked. Then continue the audit's remaining passes. Never retry the denied call, and never self-widen permissions to work around it (`${CLAUDE_PLUGIN_ROOT}/reference/permission-preflight.md` "Why a preflight, not a fixer", whose "The dated record for both claims" carries the dated basis for this refusal).

### 2. Orphaned recurring entries

Entries in `.github/recurring-schedule.json` with no corresponding open or recently-closed item (skip when the repo has no recurring schedule). Only **due** entries can be orphaned. The automation creates an item only once `next_due <= today`, so a healthy future entry legitimately has no open item and is NOT orphaned:

```bash
SCHEDULE="<project root>/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq -r --arg today "$(date +%Y-%m-%d)" \
    '.items[] | select(.next_due != null and .next_due <= $today) | .id' "$SCHEDULE"
fi
```

List recurring items (adapter: "List items", `--label <resolved recurring-maintenance label>`,
`--state all`, with bodies, bare read) and cross-reference by each body's
`<!-- recurring-schedule id=<id> -->` line, never by title
([`reference/issue-conventions.md`](../../../reference/issue-conventions.md)
"Recurring marker"): schedule ids no item's marker names are orphaned. Report a labeled item with
no marker as unlinked.

### 3. Unlabeled items + label conflicts

Items missing their **type** classification (org repos: no native Issue Type set; personal / non-org repos: no `type:*` label), missing an expected `category:*` label, or carrying conflicting labels (e.g. two `priority:*`) surface via the hygiene projections in the bound adapter's operations reference (GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md` "Aggregate / count (dashboard + hygiene)", bare reads). On org repos the type axis is a native Issue Type, so absence of a `type:*` label is **not** a defect. Read the native type field for the presence check.

### 4. Decomposed parents

List open and closed items with their bodies (adapter: "List items", `body` added to the fields, `--state all`), keep those whose body carries the `<!-- work-items:born-triaged -->` marker and a `## Parent` section opening `Refs #<parent>`, and collect each open parent they name. Run "Decomposed parent close" in [`reference/issue-conventions.md`](../../../reference/issue-conventions.md) for each one; it owns the close or the comment. A child a merged PR closed reaches its parent only through this pass. Present each parent it closed or left open, with the reason.

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

### Decomposed Parents
| # | Parent | Children | Result |
|---|--------|----------|--------|
| 1 | #60 Export refunds | 3 closed | closed (Finish line merged) |
| 2 | #70 Ward rota | 2 closed | left open (Finish line in use, checked by the ward lead) |

**Summary:** X stale claims reclaimed, Y orphaned entries, Z unlabeled items, P parents closed, Q left open
```

## Notes

- The `reclaim` verb never releases a live lease, so a session actively working an item is safe.
- Run periodically (weekly) or before `/work-items:work` (which also reclaims at session start) to keep the tracker clean.
