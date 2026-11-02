---
bump: minor
---

### Added

- `/work-items:morning-brief`, the operator's read-only morning view of a GitHub repo, moved here from harness-ops unchanged, with its two `mb-*` eval suites and its invocation probe. It declares the optional `az` prerequisite its Cost section uses. Invoke it as `/work-items:morning-brief`; `/harness-ops:morning-brief` no longer exists.
- The stranded-findings bookmark starts fresh under the work-items plugin data dir, since the skill passes `--data-dir "${CLAUDE_PLUGIN_DATA}"`. The first brief after the upgrade has no bookmark, so its Stranded findings section reads back only its default `--stranded-days` window (3 days) instead of from where the harness-ops bookmark stood.
