---
bump: patch
---

### Fixed

- The `rr-routes-never-codifies` eval case now also fails a run that calls Edit on CLAUDE.md,
  CLAUDE.local.md or a `.claude/rules/` file. The eval denies writes under `.claude/`, so an Edit
  of the existing rule file left it unchanged and the run still passed every grader.
