---
bump: minor
---

### Added

- `handoff` gains a tracker short form: when a tracker item (a wayfind map item, say) already holds every finding, decision and remaining action and no session state is left, the resume is two lines, `/clear, then run:` and the command with the item's URL, with no handoff file. Findings not yet on the tracker still take the full file (new `skills/handoff/reference/tracker-short-form.md`).

### Changed

- `workflow` is the one home for route choice: `context/steps.md` gains "Pre-implementation order", moved in full from `docs/finding-your-unknowns.md`, and the quick-change and foggy-effort on-ramps carry the reasons that were in the interview's routing file.
