---
bump: patch
---

### Changed

- `/improvement:find`'s unattended filing now takes its open cap, title-repeat check and missing-label stop from `scripts/filing-plan.mjs`, one command any other filer can share, instead of applying them by hand.
- That step passes each cap layer as a JSON integer, puts the plan's `warnings`, `cap` and `source` in the run report, and names a missing `node` in its `gap:` line; the README lists `node` on PATH as a filing prerequisite.
- New eval case `find-unattended-filing-plan-fails-files-nothing` checks that a failed filing-plan command files nothing and writes a `gap:` line naming `node`.
