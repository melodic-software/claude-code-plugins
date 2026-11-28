---
bump: minor
---

### Changed

- Unattended filing now needs `node` on PATH: without it, `/improvement:find --unattended` still writes its report but files nothing, and says so in a `gap:` line. Before this change, filing needed no runtime.
- `/improvement:find`'s unattended filing now takes its open cap, title-repeat check and missing-label stop from `scripts/filing-plan.mjs`, one command any other filer can share, instead of applying them by hand.
- That step passes each cap layer as a JSON integer, puts the plan's `warnings`, `cap` and `source` in the run report, and names a missing `node` in its `gap:` line; the README lists `node` on PATH as a filing prerequisite.
- The filing-plan command exits 2 on a cap layer that is not a non-negative integer, so a malformed request files nothing, and it still runs when the plugin sits behind a symlinked path. A command that prints no JSON plan files nothing.
- New eval case `find-unattended-filing-plan-fails-files-nothing` checks that a failed filing-plan command files nothing and writes a `gap:` line naming `node`; `find-unattended-filing-plan-empty-files-nothing` checks the same for a command that exits 0 and prints no plan.
