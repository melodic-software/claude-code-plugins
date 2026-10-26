---
bump: patch
---

### Fixed

- The babysit wrapper's effective rung reads `babysit_loop_merge` from `docs/conventions/source-control.yaml` as well as `.claude/source-control.md` and takes the lower value, so a demotion written only to the YAML holds unattended merges ([#9726](https://github.com/melodic-software/claude-code-plugins/issues/9726)). While `.claude/source-control.md` exists it must set the key too, or the rung is `off`, so a raise needs both files; with no legacy file the YAML alone decides. Either file the wrapper cannot read or trust (a rejected YAML or legacy file, an empty, non-scalar or unknown YAML value, an empty or repeated legacy H2) means `off`, never the other file's value alone.
