# Changelog

All notable changes to the `repo-hygiene` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Destructive-guard kill switch migrated to native `userConfig`** (the fleet-wide
  kill-switch doctrine ruling): the `clean_destructive_guard_enabled` boolean (default
  `true`) now gates the session-scoped destructive guard, read through the native
  `CLAUDE_PLUGIN_OPTION_CLEAN_DESTRUCTIVE_GUARD_ENABLED` hook-process mirror. Configure
  with `/plugin configure repo-hygiene` or `claude plugin install --config`.
- **BREAKING:** the `HOOK_CLEAN_DESTRUCTIVE_GUARD_ENABLED` environment variable is retired
  and no longer read. Zero-config behavior is unchanged (guard active while the clean skill
  is active).
