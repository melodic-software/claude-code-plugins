---
bump: minor
---

### Added

- Intake refinement now files the split admission recommends. When admission holds an issue at the lanes App's `status: needs-decision` because some, not all, of its done-when items ask for what an unattended lane run cannot perform, and the triage raised no flag, the `refine-issue` run judges the split. When the model returns exactly the held item numbers, `apply-refinement` files one child issue as the lanes App, labeled `needs-human` and born triaged, that holds those items as written and links back. It then replaces them in the issue body with one line linking the child, lifts `status: needs-decision`, and triages the issue once more so admission reads the rest. The refinement marker keeps it to once per issue, and a retry reuses the child it filed. A proposal that names any other items, drafts criteria or asks questions alongside a split is refused before anything is written.
