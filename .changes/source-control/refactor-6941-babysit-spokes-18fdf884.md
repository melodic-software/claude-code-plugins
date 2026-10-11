---
bump: patch
---

### Changed

- The `babysit-prs` spokes (`loop.md`, `safety.md`, `orchestration.md`, `freshness.md`, `stuck-checks.md`) and the `babysit-loop` `cycle-shape.md` spoke name forge operations instead of `gh` commands; the GitHub commands, procedures and CLI facts moved to new files under `reference/providers/github/babysit-prs/` and `reference/providers/github/babysit-loop/`, linked from each call site. Behavior is unchanged: every command is still reachable from its spoke, and the worker prompt, the pinned approve mechanic and the pre-computed context keep their `gh` lines.
