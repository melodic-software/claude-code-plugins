---
bump: patch
---

### Fixed

- run setup's status checks as single Bash calls

  `firecrawl --version`, `firecrawl --status` and each env-var presence test
  run alone, one call per variable with its name spelled out, so no command
  chains probes or loops with shell-specific indirect expansion.
