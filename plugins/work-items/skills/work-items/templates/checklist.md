# /work-items Checklist

Copy into `.work/<slug>/work-items-checklist.md`. Per-action checklists below — copy only the section matching the action you're running.

## Action: work (most common — full workflow per item)

- [ ] Session-start reclaim — `tools/work-item-tracker/work-item-tracker.sh reclaim "<id>"` over assigned items (idempotent)
- [ ] Claim — `tools/work-item-tracker/work-item-tracker.sh claim "<id>"` (exit 7 = lost race, pick next)
- [ ] Branch — `git checkout -b <type>/<N>-<short-slug>` from origin/main
- [ ] Run `/workflow` chain — copy the checklist `/workflow` emits into this slice's PLAN.md
- [ ] Close — `/work-items done <N>` after PR merges (or via PR body `Closes #N` auto-close)

## Action: add

- [ ] Pre-flight: search-before-create (adapter: "Search items", `--state all`) — pivot if open/closed match exists
- [ ] Compose title (`<type>: <description>`); body; labels
- [ ] `tools/work-item-tracker/work-item-tracker.sh create-item --title '...' --body '...' --labels '...'`
- [ ] Capture item ID/number for cross-reference

## Action: start

- [ ] Pick item — `/work-items list --label '<label>'` OR `/work-items due`
- [ ] Pre-check + reclaim — `tools/work-item-tracker/work-item-tracker.sh reclaim "<id>"` (idempotent; recovers a crashed session's stale lease so `claim` doesn't back off on the stale assignee)
- [ ] Claim via `tools/work-item-tracker/work-item-tracker.sh claim "<id>"`
- [ ] Chain to `work` action

## Action: done

- [ ] Verify PR merged
- [ ] `/work-items done <N>` (or rely on PR `Closes #N` auto-close)
- [ ] Comment with merge SHA + retro pointer if applicable

## Action: stats / list / search / scan / audit

- [ ] Single-action read-only — no checkbox chain (run once, report)

## Action: recheck

- [ ] Search items with `recheck:` body lines older than threshold
- [ ] For each, evaluate trigger; close-with-comment OR re-open per outcome
- [ ] Update item body with re-check timestamp

## Skip criteria

- `add` pre-flight SKIPPED only in tightly-scoped automation where duplicate-risk explicitly assessed; ad-hoc invocations always pre-flight

## How to use

Same shape as the `/workflow` checklist template ("How to use"). Copy only the per-action section relevant to your invocation.
