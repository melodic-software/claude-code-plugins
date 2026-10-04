# Scope budget reference

How tidy applies the PR scope budget. The target, the hard cap, and what counts toward them belong to the shared PR scope budget convention, shipped with this plugin as [`<plugin-root>/reference/pr-scope-budget.md`](../../../reference/pr-scope-budget.md); read the numbers there. This file holds what the convention leaves to each adopter: tidy's overflow priority order and its deferred-items template.

If a lane consistently overflows the cap, the lane scope is too coarse. Split the lane, don't raise the cap.

---

## 1. Overflow protocol

When the hunt phase produces more candidates than fit in the budget:

1. **Sort candidates by priority.** Default priority order, highest first:
   - Tidyings that resolve a build warning, lint warning, or analyzer hit
   - Tidyings that fix a stale cross-reference (P-2) or dead link (P-1), with high reader-experience impact
   - Tidyings that improve reading order (Beck #5, P-4) in files reviewers visit often
   - Tidyings that delete dead code (Beck #2) or redundant comments (Beck #15)
   - Other Beck/Fowler/prose tidyings, all roughly equal priority

2. **Take the top-priority subset that fits.** Greedy selection: take the highest-priority candidate; if adding it would exceed the cap, skip and try the next; stop when the cap is reached or no remaining candidate fits.

3. **Defer the rest.** For each unselected candidate above a "would-be-worth-doing" threshold (i.e., not trivial micro-tidyings, which just go away), file a work item using the deferred-items template below: invoke `/work-items:track add` via the Skill tool when that plugin is installed, else `gh issue create`, else present the list to the user.

4. **Record the deferred issue numbers** under a `## Deferred items` section, in Phase H's follow-up PR comment when `source-control` is installed, otherwise directly in the PR body. This makes the PR's review obvious-by-default: "here's what I did, here's what I parked for next time, here are the issue numbers to hold me accountable."

### Greedy vs. optimal selection

Bin-packing-optimal selection is not worth the complexity. Greedy by priority captures nearly all of the value, and reviewers do not notice whether the PR contained the mathematically optimal subset.

---

## 2. Deferred-items message template

When filing a deferral, use this exact title and body shape so the deferred items are searchable, sortable, and pre-filled for the next tidy run.

### Title format

```text
<conv-type>(<area>): <one-line what>
```

Conventional Commits type matches the lane's default (`refactor:`, `docs:`, `chore:`, `test:`). The `<area>` is the lane name or a more specific scope. The one-line what describes the tidying without specifying its full implementation.

Examples:

- `refactor(core): consolidate result-chain helpers`
- `docs(skills): repair stale cross-references in retro/SKILL.md`
- `chore(tools): apply shfmt drift across tools/setup-*.sh`

### Body format (use as-is, fill in the angle-bracket placeholders)

```markdown
## Context

Deferred from tidy run on `<branch-name>` (anchor: `<anchor-sha>`). The hunt found this candidate but the PR scope budget's hard cap was reached before it could be included.

## Tidying type

<one of the named tidyings from reference/tidyings.md, e.g., "Beck #5: Reading Order">

## Files

- `<path/to/file1.ext>` (<estimated LOC delta>)
- `<path/to/file2.ext>` (<estimated LOC delta>)

## Estimated scope

<estimate>: ~<N> LOC across <M> files. Should fit within the scope budget's target as a future tidy run.

## Lane

`<lane-name>`

## Acceptance criteria

- [ ] Tidying applied per `reference/tidyings.md` definition
- [ ] Build + tests + lint pass for the affected ecosystem
- [ ] Squash-merge title follows Conventional Commits

## Notes

<any context the next agent / reviewer needs that wasn't obvious from "what" alone>
```

### Labels (when supported by the issue tracker)

- `type:refactor` / `type:docs` / `type:chore` / `type:test` (matches the Conventional Commits type)
- `area:<lane-name>`
- `tidy-deferred` (umbrella label so all tidy-deferred issues are findable)

### Frequency

No upper bound on deferred issues per run. If a single run defers >10 items, that's worth noting to the user. The lane may be scope-creep'd or the watch-for list may be too aggressive.

---

## How to apply the budget during a run

1. **Phase D (Hunt + prioritize + scope-budget enforce)**: after building the prioritized findings table, sum the LOC deltas. Apply the greedy selection.
2. **Phase E (Implement)**: periodically check actual LOC delta against the running estimate (`git diff --stat origin/<default-branch>...HEAD`; under `in-place`, `git diff --cached --stat`, since the tidyings are staged on a branch that may carry unrelated commits). The default form measures the full branch diff, all commits since the branch point, not just uncommitted changes relative to HEAD. If actual exceeds estimated by >25%, stop the current tidying mid-flight and re-budget.
3. **Phase H (Ship)**: the `## Deferred items` section (follow-up comment, or PR body when `source-control` isn't installed) comes directly from this protocol's filed-issue list.

If the budget numbers themselves need to change, that is a change to the shared convention, not a tidy. See the SELF-UPDATE EXTRA HARD list in `reference/exclusions.md`.
