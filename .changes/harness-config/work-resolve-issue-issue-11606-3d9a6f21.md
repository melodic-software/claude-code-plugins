---
bump: patch
---

### Fixed

- `audit-permission-grants` now parses the `allowed-tools` frontmatter of installed plugins when `$PERMISSION_HYGIENE_SCAN_ROOT` points at the plugin cache or at a single-plugin repository. A `skills/<name>/SKILL.md`, `agents/<name>.md` or `commands/<name>.md` file is now audited when the directory above its `skills/`, `agents/` or `commands/` folder holds `.claude-plugin/plugin.json`, as well as under `plugins/<name>/`. A run that excludes every frontmatter candidate as non-loadable now prints `NO FRONTMATTER AUDITED, NOT A CLEAN BILL` instead of `No fragile permission grants found.` ([#11606](https://github.com/melodic-software/claude-code-plugins/issues/11606)).
