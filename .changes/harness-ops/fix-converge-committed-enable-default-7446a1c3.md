---
bump: patch
---

### Fixed

- `/harness-ops:plugins converge` no longer defaults to uninstalling a project pin whose id is enabled in the tracked `.claude/settings.json`: it defaults to `update -s project` and offers uninstall only as a warned non-default. Each preview row states why its default was chosen. The check reads that one `enabledPlugins` key with the Read tool, the plugin's only sanctioned settings read, and is removed once `sync` takes over project pin updates (#7458).
