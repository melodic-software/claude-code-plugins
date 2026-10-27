---
bump: patch
---

### Fixed

- fix-docs's patch now pushes only markdown outside `skills/` ([#8956](https://github.com/melodic-software/claude-code-plugins/issues/8956)). `pr-refine.yml`'s `apply-docs-patch` job passes `patch-prepare: docs`, so apply-patch holds the patch to `patch-rules.json`'s `docs` row in place of the `default` row: a path not ending in `.md`, a path under a `skills/` directory or any `SKILL.md` refuses the whole patch as `patch-protected-path`, and the run posts its `pr-refine / apply-patch` check neutral. Before, the `default` row let a fix-docs patch push any path outside the universal refusals, a plugin hook or script included.
