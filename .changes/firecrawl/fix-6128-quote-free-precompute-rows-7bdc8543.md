---
bump: patch
---

### Fixed

- **`firecrawl` and `setup` load under `claude -p` again.** Both pre-computed rows held a brace
  group, which Claude Code's shell permission check refuses even when quote-free (`A group in braces
  or double parentheses in this command can't be checked before it runs`); outside auto mode that
  aborts the skill with no output. `setup`'s probe is now `command -v firecrawl 2>/dev/null || echo
  absent`, pre-approved in its `allowed-tools`. The status row drops the 0.5.7 brace group and
  repeats the guard before the fallback instead:
  `command -v firecrawl >/dev/null 2>&1 && firecrawl --status 2>/dev/null | head -10 || command -v firecrawl >/dev/null 2>&1 || echo "NOT INSTALLED ..."`.
  It renders the same as the 0.5.7 row with and without `pipefail`, for an absent CLI, output under
  the cap and output over it (checked with a fake `firecrawl` on `PATH`), and the existing
  `Bash(command -v firecrawl*)` grant covers both guards.
