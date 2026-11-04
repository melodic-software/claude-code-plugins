---
bump: major
---

### Removed

- The `resolve-conflicts` skill and its ten eval cases ([#13197](https://github.com/melodic-software/claude-code-plugins/issues/13197)). Use `/source-control:pull-request` instead: `ready` merges the base and resolves a conflicted merge under the same rules (both sides' intent first, no `--ours`/`--theirs`, a semantic-conflict sweep, the version-bump script), and `conflicts --ci` is the pr-unblock lane's unattended mode. The pr-unblock activity keeps its `resolve-conflicts` name.
