# work-items skill checklist

Copy into `<memory_dir>/<slug>/work-items-checklist.md` (default `.work/`). Per-action checklists below — copy only the section matching the action you're running. The `work` section belongs to the `/work-items:work` skill; the rest belong to `/work-items:track`.

## Action: work (most common — full workflow per item)

- [ ] Session-start reclaim — `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh reclaim "<id>"` over assigned items (idempotent)
- [ ] Claim — `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh claim "<id>"` (exit 7 = lost race, pick next)
- [ ] Branch — `git checkout -b <type>/<N>-<short-slug>` from origin/main
- [ ] Run `/workflow` chain — its checklist lands as its own memory-tier ledger (`<memory_dir>/<slug>/workflow-checklist.md`, per `/workflow`'s topic-docs binding); plan progress is marked in the topic's contract-tier `PLAN.md` (`<contract_dir>/<slug>/PLAN.md` on the task branch)
- [ ] Close — `/work-items:track done <N>` after PR merges (or via PR body `Closes #N` auto-close)

## Action: add

- [ ] Pre-flight: search-before-create (adapter: "Search items", `--state all`) — pivot if open/closed match exists (skip if `--force`)
- [ ] Resolve issue type from `--type` (default `task`) — native GitHub Issue Type on org repos (passed via `--type`, not a label); coarse `type: bug`/`type: feature`/`type: task` label on personal/non-org repos
- [ ] Build labels list; build body (default template, or agent-brief template if `--agent-ready`); write the body to a temp file with the Write tool (argv-safe — never inline generated text)
- [ ] `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh create-item --title '{title}' --body "$(cat "$BODY_FILE")" --type '{type}' --labels '...'` (`--type` on org repos only; `[Maintenance]` title prefix when `--recurring`)
- [ ] Capture item ID/number for cross-reference

## Action: start

- [ ] Pick item — `/work-items:track list --label '<label>'` OR `/work-items:track due`
- [ ] Pre-check + reclaim — `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh reclaim "<id>"` (idempotent; recovers a crashed session's stale lease so `claim` doesn't back off on the stale assignee)
- [ ] Claim via `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh claim "<id>"`
- [ ] Chain to the `/work-items:work` skill

## Action: done

- [ ] Verify PR merged
- [ ] `/work-items:track done <N>` (or rely on PR `Closes #N` auto-close)
- [ ] Comment with merge SHA + retro pointer if applicable

## Action: stats / list / search / scan-todos / audit

- [ ] Single-action read-only — no checkbox chain (run once, report)

## Action: recheck

- [ ] Find the schedule item in `.github/recurring-schedule.json` (by ID or title); complete the periodic check itself
- [ ] Update `last_checked` to today (always); advance `next_due` when it is due today or past due (`next_due <= today`)
- [ ] Close the associated open `[Maintenance]` item with a recheck comment (next due date)

## Skip criteria

- `add` pre-flight SKIPPED only in tightly-scoped automation where duplicate-risk explicitly assessed; ad-hoc invocations always pre-flight

## How to use

Same shape as the `/workflow` checklist template ("How to use"). Copy only the per-action section relevant to your invocation.
