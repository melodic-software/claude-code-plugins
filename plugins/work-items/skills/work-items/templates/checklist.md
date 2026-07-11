# Work-items Checklist

Copy the section matching the action you're running into your session task list (or the consuming project's working-notes convention). Per-action checklists below.

## Action: work (most common — full workflow per item)

- [ ] Claim — hold→verify→claim protocol, ending in `gh issue edit <N> --add-assignee @me`
- [ ] Branch — `git checkout -b <type>/<N>-<short-slug>` from the default branch
- [ ] Execute the project's development workflow (or explore → plan → implement → test → review → PR)
- [ ] Close — `gh issue close <N> --comment '<closing rationale>'` after PR merges (or via PR body `Closes #N` auto-close)

## Action: add

- [ ] Pre-flight: `gh issue list --state all --search '<key-term> in:title'` — pivot if open/closed match exists
- [ ] Compose title (`<type>: <description>`); body; labels
- [ ] `gh issue create --title '...' --body '...' --label '...'`
- [ ] Capture issue number for cross-reference

## Action: start

- [ ] Pick item — `list --label '<label>'` OR `due`
- [ ] Claim via hold→verify→claim, ending in `gh issue edit <N> --add-assignee @me`
- [ ] Chain to `work` action

## Action: done

- [ ] Confirm the work is complete (PR merged, or no PR applies) — for recurring items use `recheck` instead
- [ ] `gh issue close <N> --comment '<summary>'` (or rely on PR `Closes #N` auto-close); `--reason "not planned"` when closing as superseded/rejected
- [ ] Remove `status:claimed`; comment with merge SHA + learnings pointer if applicable

## Action: stats / list / search / scan / audit

- [ ] Single-action read-only — no checkbox chain (run once, report)

## Action: recheck

- [ ] Find the schedule item; complete the periodic check itself
- [ ] Update `last_checked` (always) and `next_due` (only if past due)
- [ ] Close the associated open issue with a recheck comment

## Skip criteria

- `add` pre-flight SKIPPED only in tightly-scoped automation where duplicate-risk explicitly assessed; ad-hoc invocations always pre-flight
