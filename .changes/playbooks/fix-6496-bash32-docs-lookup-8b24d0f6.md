---
bump: patch
---

### Fixed

- **The shared docs lookup scripts run on Bash 3.2
  ([#6496](https://github.com/melodic-software/claude-code-plugins/issues/6496)).** `scripts/fetch-docs.sh`
  and `scripts/docs-cache.sh` no longer use `${x,,}`, `${x^^}`, `declare -A` or `printf '%(...)T'`,
  which stock macOS Bash 3.2 rejects, so a docs lookup there no longer exits with `bad substitution`.
