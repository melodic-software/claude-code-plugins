---
bump: patch
---

### Fixed

- `lib/check-retirements.sh` finds and cleans a `.git/` leftover, such as a retired git hook,
  when run from a linked worktree: such a path resolves under `git rev-parse --git-common-dir`.
  `/guardrails:setup` step 8 now reports the retired hooks from a linked worktree too.
- The `commit-msg-convention` git hook checks a `git commit -m "#123 fix"` subject: with no
  editor, git keeps lines that start with the comment character, so the hook does too
  (`commit.cleanup` is honored).
