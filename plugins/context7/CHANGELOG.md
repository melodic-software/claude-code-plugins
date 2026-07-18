# Changelog

All notable changes to the `context7` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.1]

### Changed

- **CLI/platform facts re-verified against `ctx7` 0.5.5 and corrected**
  (fleet conformance wave: freshness riders). `--base-url` default is
  `https://context7.com` (not `/api`), version flag is lowercase `-v`,
  `library`'s query argument is optional, the `skills` surface is deprecated
  upstream (this plugin never invokes it), and new top-level
  `remove`/`uninstall` + `upgrade` commands are listed.
- **Claude Code unset-env-var MCP behavior corrected**: the config loads with
  a missing-variable warning and the literal `${VAR}` text is sent as-is
  (silently broken auth) — it is not a parse failure. Both context docs now
  carry verified-date + official-link riders.

## [0.3.0]

### Changed

- Renamed the `context7` skill → `lookup`. Update any `/context7:context7` invocations to
  `/context7:lookup`; the plugin ID (`context7`) is unchanged, only the skill's leaf name moved.
