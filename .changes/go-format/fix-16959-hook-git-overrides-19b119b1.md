---
bump: patch
---

### Changed

- The shared `resolve-tool.sh` adds `rt_git`, the git that format and lint adapters run: `hook::git_untrusted` inside a Claude Code hook, plain git otherwise. This plugin's adapter runs no git.
