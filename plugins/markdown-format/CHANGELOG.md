# Changelog

All notable changes to the `markdown-format` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1]

### Changed

- Refresh of the bundled shared hook-utils library, which gains the git argv-grammar parser used by
  the guardrails plugin's git guards. No behavioral change to this plugin's hooks.

## [0.2.0]

### Changed

- **Breaking:** renamed the plugin `markdown-formatter` → `markdown-format`, aligning with the
  hook-plugin `<tool>-format` verb family (`biome-format`, `ruff-format`, `powershell-format`).
  This is a hard break with no marketplace `renames` entry: uninstall `markdown-formatter` and
  run `/plugin install markdown-format@<marketplace>`. Skills, hook behavior, telemetry `hook`
  value (`markdown-format`), and the `HOOK_MARKDOWN_FORMAT_ENABLED` kill switch are unchanged.
