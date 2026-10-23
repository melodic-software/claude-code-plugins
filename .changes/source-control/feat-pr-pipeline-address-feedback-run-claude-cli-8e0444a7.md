---
bump: minor
---

### Changed

- `pull-request comments --ci` commits nothing: it leaves each fix uncommitted in the working tree, and a later job with no model pushes it as one commit. A disposition's `fix_sha` stays empty, and the reply job names the pushed commit. The review-thread tool's path comes from the run's preamble ([`comments-ci.md`](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/skills/pull-request/reference/comments-ci.md)).
- The review-thread tool, `feedback-thread.sh`, makes no GitHub call. It records `VALID` only with an empty `fix_sha`, and only while every path the working tree changes against the gated head is in a kept thread's scope and outside `.github/`. That covers both sides of a rename and every untracked file git does not ignore.
