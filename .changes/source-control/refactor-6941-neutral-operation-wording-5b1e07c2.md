---
bump: patch
---

### Changed

- The `pull-request`, `babysit-prs`, `babysit-loop`, `setup`, `worktree`, `commit` and `resolve-conflicts` skill bodies name forge operations instead of `gh` commands; the GitHub commands for each operation are in the new `reference/providers/github/README.md`. Behavior is unchanged: the phase spokes and bundled scripts still run the same commands.

### Fixed

- `pr-body-linkage-gate` and `pr-linkage-mcp-gate` accept a tracker's link line as `/work-items:track link` prints it (`Closes ENG-123`, `Refs ENG-123`, `Refs: SW2-12`, `Refs: local-markdown:local/markdown#7`), alone on its line. They blocked every non-GitHub tracker's link before.
