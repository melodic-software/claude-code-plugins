---
bump: minor
---

### Added

- **`/harness-ops:morning-brief` lists open items stuck in a queue label** ([#8649](https://github.com/melodic-software/claude-code-plugins/issues/8649)). A new Stuck section, right after Queues, shows the open issues and PRs whose newest labeled event for a queue label is older than `--stuck-days` (default 7), oldest first, with the days in stage. `--stuck-limit` (default 20) caps the lines and the section says `PARTIAL` past it. `--stuck-json` feeds the section from a fixture. The section is read-only, and renders `UNREADABLE` where GraphQL is not served.
