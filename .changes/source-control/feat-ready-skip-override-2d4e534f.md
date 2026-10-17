---
bump: minor
---

### Added

- `/source-control:pull-request ready --skip <step>[,<step>...] --reason "<text>"` lets a person who is present skip pre-flip steps for one run. It is refused under `--unattended`, never re-enables a step `pre_ready` disabled, and leaves the hold checks, the push and the flip in place. Each skipped step is reported as `skipped by <login> for this run: <reason>` and the same lines go into one PR conversation comment, marked with the head it flipped; `ready` never edits the PR body.
