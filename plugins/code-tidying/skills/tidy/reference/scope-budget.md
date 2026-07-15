# Scope budget reference

How big is "well-sized" for a tidy PR? This file is the canonical answer. Three sections: the cap and target numbers (with research lineage), the overflow protocol when a hunt finds more than the cap allows, and the deferred-items message template.

---

## 1. PR scope target / hard cap

| Metric | Target | Hard cap |
|--------|--------|----------|
| Lines of code (additions + deletions) | ≤200 LOC | ≤400 LOC |
| Files changed | ≤8 files | ≤15 files |

The **target** is the ideal shape of a tidy PR — small enough to review in under an hour, atomic enough to revert cleanly. The **hard cap** is the absolute upper bound; runs producing more must defer the overflow.

### Research lineage

- **SmartBear "Best Kept Secrets of Peer Code Review" (Cohen et al.)** — the foundational study showing review effectiveness drops sharply above 200 LOC and reviews above 400 LOC are largely ineffective at finding defects. The 200/400 thresholds match this lineage directly
- **Cisco's code-review study (Bosu, McIntosh, Wagner)** — confirmed SmartBear's findings on a different codebase; ≤60 minutes of review time correlates with ≤200 LOC
- **CodeScene 2026 agentic refactoring research (Tornhill)** — autonomous AI agents introduce defects ~30% more often in unhealthy code; small, structure-only PRs minimize that defect rate

If a lane consistently overflows the cap, that's a signal the lane scope is too coarse — split the lane, don't raise the cap.

### What counts toward LOC

- Net additions + net deletions (a change that adds 50 lines and removes 50 lines = 100 LOC for the cap)
- Generated / formatted diffs (whitespace-only changes from formatters) DO count toward the cap — they're still code the reviewer must scan past
- Lockfile changes (`uv.lock`, `package-lock.json`, and similar machine-generated files) DO NOT count — they're inspection-only
- Markdown line additions DO count for prose lanes (those lanes are prose-only, so line counts ARE the budget)

### What counts toward files changed

- Every file with at least one non-whitespace edit
- File renames count as 1 file (not 2)
- Generated files not in the index don't show up here

---

## 2. Overflow protocol

When the hunt phase produces more candidates than fit in the budget:

1. **Sort candidates by priority.** Default priority order, highest first:
   - Tidyings that resolve a build warning, lint warning, or analyzer hit
   - Tidyings that fix a stale cross-reference (P-2) or dead link (P-1) — high reader-experience impact
   - Tidyings that improve reading order (Beck #5, P-4) in files reviewers visit often
   - Tidyings that delete dead code (Beck #2) or redundant comments (Beck #15)
   - Other Beck/Fowler/prose tidyings, all roughly equal priority

2. **Take the top-priority subset that fits.** Greedy selection: take the highest-priority candidate; if adding it would exceed the cap, skip and try the next; stop when the cap is reached or no remaining candidate fits.

3. **Defer the rest.** For each unselected candidate above a "would-be-worth-doing" threshold (i.e., not trivial micro-tidyings — those just go away), file a work item using the deferred-items template below: via `/work-items:track add` when that plugin is installed, else `gh issue create`, else present the list to the user.

4. **Record the deferred issue numbers in the PR body** under a `## Deferred items` section. This makes the PR's review obvious-by-default: "here's what I did, here's what I parked for next time, here are the issue numbers to hold me accountable."

### Greedy vs. optimal selection

Bin-packing-optimal selection isn't worth the complexity. Greedy by priority gets ≥90% of the value; reviewers don't notice whether the PR contained the mathematically-optimal subset.

---

## 3. Deferred-items message template

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

Deferred from tidy run on `<branch-name>` (anchor: `<anchor-sha>`). The hunt found this candidate but the PR scope budget (≤200 LOC / ≤8 files target; ≤400 / ≤15 cap) was reached before it could be included.

## Tidying type

<one of the named tidyings from reference/tidyings.md, e.g., "Beck #5 — Reading Order">

## Files

- `<path/to/file1.ext>` (<estimated LOC delta>)
- `<path/to/file2.ext>` (<estimated LOC delta>)

## Estimated scope

<estimate>: ~<N> LOC across <M> files. Should fit within the standard 200/8 target as a future tidy run.

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

No upper bound on deferred issues per run. If a single run defers >10 items, that's worth noting to the user — the lane may be scope-creep'd or the watch-for list may be too aggressive.

---

## How to apply these numbers during a run

1. **Phase D (Hunt + prioritize + scope-budget enforce)** — after building the prioritized findings table, sum the LOC deltas. Apply the greedy selection.
2. **Phase E (Implement)** — periodically check actual LOC delta against the running estimate (`git diff --stat origin/<default-branch>...HEAD`). This measures the full branch diff — all commits since the branch point, not just uncommitted changes relative to HEAD. If actual exceeds estimated by >25%, stop the current tidying mid-flight and re-budget.
3. **Phase H (Ship)** — the PR body's `## Deferred items` section comes directly from this protocol's filed-issue list.

If the cap numbers themselves need to change, that's a research-driven update — not a tidy. See the SELF-UPDATE EXTRA HARD list in `reference/exclusions.md`.
