---
bump: patch
---

### Fixed

- `/harness-ops:changelog` and its status script read the Claude Code changelog from `CHANGELOG.md` in `anthropics/claude-code` first, falling back to the docs page only when that read fails, through one new `scripts/fetch-changelog.sh`; the shared parser accepts the repository file's `## X.Y.Z` releases, and the status output names the source on a `changelog:` line. A release no longer waits for the docs page to catch up ([#7407](https://github.com/melodic-software/claude-code-plugins/issues/7407)).
