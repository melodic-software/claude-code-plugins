---
bump: minor
---

### Added

- Intake refines a thin issue: one whose triage flags `intent` or whose body has no `- [ ] ` task list. A read-only model run in `intake-triage.yml` (`refine-issue`, contents read only, no project settings, `dontAsk`) explores the default branch, checks the open and closed issues and merged pull requests a title search found for duplicates and finished work, and reads the docs hosts resolve-issue reads. The `apply-refinement` activity posts its output as the lanes App in a separate comment opening with `<!-- intake-triage refinement -->`, once per issue.
- An exact refinement lists its acceptance criteria as a task list, lifts the lanes App's `status: needs-decision`, and triages the issue once more; one that is not exact asks numbered questions with `RECOMMENDED:` answers and leaves the issue at `status: needs-decision`. It never adds `agent-ready` or `needs-human`.
- Admission's criterion 7 also counts the task list in that comment when the lanes App's account posted it.
