---
bump: minor
---

### Changed

- enable-auto-merge leaves an unarmed lanes App pull request on its lane refusal (a risk-score hold
  or a pr-unblock stop) with no read when nothing it reads has changed since the last reader run:
  head, `updatedAt`, labels, check and status rollup, reviews, comments, review threads, rung and
  main's code and config. It reuses `merge.skip-unchanged` (max-minutes, max-skips), never skips
  past the refusal's escalation to a failing status, never skips an armed one, and logs
  `enable-auto-merge: skip-unchanged skipped=N recorded=M keyed=K of L`. The records ride in the
  `pr-merge-verify-answers` artifact.
- enable-auto-merge's discussion read lists the changed files, so a head with no rename reads no
  REST files page.
- A `pull_request_target` run of pr-merge handles only the pull request its event names; the
  15-minute schedule keeps the full sweep. A pending event run no longer supersedes another one.
- The merge job lists its candidates with one `gh pr list` and a jq author filter in place of one
  `gh pr list --author` call per author.
