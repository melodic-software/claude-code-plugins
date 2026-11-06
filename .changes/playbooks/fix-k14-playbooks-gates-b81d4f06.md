---
bump: patch
---

### Fixed

- presence-gate the optional plugins repo-sweep and skill-authoring use

  repo-sweep's review step runs /plugin-quality:audit only when that
  plugin is installed, else drafts from the reviewer's evidence; its
  lint step falls back to each ecosystem's own lint command without the
  toolchain plugin; its branch step takes the plain git worktree path
  when source-control is not installed. skill-authoring's rewrite order
  and measurement step say which check did not run when the
  skill-quality or evals plugin is missing.
