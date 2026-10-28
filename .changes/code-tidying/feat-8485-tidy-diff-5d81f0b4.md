---
bump: minor
---

### Added

- `/code-tidying:tidy-diff` tidies one change's own lines before its commit, scoped by a file-and-line list in the `<start><TAB><count><TAB><path>` shape `added-lines.sh` prints, so it needs no branch or base ref and runs on a detached head. On code it runs a behavior-preserving simplify pass and class-A comment deletions, each behind a COMMENT-ONLY verdict from its `change-shape.sh`; on markdown it applies `/docs-hygiene:write-for-agents` or `/docs-hygiene:write-for-humans` and `/ai-slop:audit fix` to the listed lines. `--turns <n>` bounds it: at the budget it skips the passes left and reports them, never failing its caller. It stages and commits nothing.
