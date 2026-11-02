---
bump: minor
---

### Changed

- `/harness-config:audit` now detects a declared unattended-push lane from
  `docs/conventions/source-control.yaml`: a `babysit_loop_merge` above `human-only` there, or any
  `babysit_loop_*` key without it (the `c2-mechanical` baseline). The YAML wins over the
  `.claude/source-control.md` H2, which is still read for one release when the YAML sets no rung.
