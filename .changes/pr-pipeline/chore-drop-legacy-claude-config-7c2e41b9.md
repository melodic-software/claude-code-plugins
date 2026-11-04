---
bump: patch
---

### Changed

- The local babysit lane's effective rung takes `babysit_loop_merge` from
  `docs/conventions/source-control.yaml` alone; the source-control plugin no longer reads
  `.claude/source-control.md`, so the two-file rule is gone
  ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737)).
