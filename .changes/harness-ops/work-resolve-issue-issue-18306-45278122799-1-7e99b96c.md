---
bump: patch
---

### Changed

- `changelog` and `audit-plugin-landscape` read pages through the shared docs cache

  `/harness-ops:changelog` research subagents read a changelog entry through
  `scripts/fetch-docs.sh --cache --profile generic` instead of `curl`; a GitHub issue is still
  read with `curl`. `/harness-ops:audit-plugin-landscape` reads a docs page through the same
  script, not WebFetch, when the `discovery` plugin is not enabled.
