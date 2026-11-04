---
bump: patch
---

### Changed

- **teach:** the workspace-root ladder reads the `${CLAUDE_PLUGIN_DATA}/workspace-root` pointer file with the Read tool in a call of its own, never chained with `list-workspaces.sh` in one Bash call. The eval sandbox denied that chained call in 4 of 9 with-arm runs of `te-root-declared-substitution` ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
