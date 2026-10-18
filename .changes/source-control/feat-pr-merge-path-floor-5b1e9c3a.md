---
bump: minor
---

### Added

- The pr-merge lane reads `merge.diff-check.floor-paths`, globs joined to the risk scorer's HIGH path floor while the floor applies. A diff touching one scores HIGH and waits for a human, where a denied path makes the pull request ineligible. `babysit_risk.RiskInput` gains `floor_paths`.
- With the floor, a SKILL.md, agents/*.md or commands/*.md patch that adds, changes or removes `hooks`, `allowed-tools`, `permissionMode` or `mcpServers` frontmatter, or adds a line holding a `!` backtick command, scores HIGH as `high-capability`, read from the patch text the files listing already returns (`ChangedFile.patch`). A changed indented line whose hunk shows no key above it, or such a file with no patch text, also scores HIGH.
