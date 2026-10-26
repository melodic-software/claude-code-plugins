---
bump: patch
---

### Fixed

- The babysit wrapper's effective rung reads `babysit_loop_merge` from `docs/conventions/source-control.yaml` as well as `.claude/source-control.md` and takes the lower value, so a demotion written only to the YAML holds unattended merges ([#9726](https://github.com/melodic-software/claude-code-plugins/issues/9726)). A YAML the wrapper cannot read, or whose value is rejected, empty, non-scalar or unknown, means `off`.
