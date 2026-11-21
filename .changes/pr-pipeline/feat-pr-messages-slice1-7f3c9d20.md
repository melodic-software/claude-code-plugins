---
bump: patch
---

### Changed

- **One lane run report per activity on a pull request.** The report jobs of `pr-run-activity-read.yml` and `pr-run-activity-write.yml` now keep one comment per activity, marked `<!-- lane-run-report activity=<lane>/<activity> -->`, with one section per report job of the newest run, instead of one comment per run, model rung and runner leg. A comment a person edited is skipped and the next report posts a fresh one. The report goes through the new PR-message module (`.github/scripts/lib/pr-messages/`), which owns the kind's marker grammar, trusted author, match and void rules. Old per-run comments stay on open pull requests and stop growing.
