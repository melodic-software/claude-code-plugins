# Changelog

All notable changes to the `context7` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Changed

- **Setup adopts the uniform `check` / `apply` contract.** The single interactive
  flow is split into a read-only `check` (default) that reports the `ctx7` CLI,
  `CONTEXT7_API_KEY` presence, and MCP-server state as PASS/FAIL/INFO, and an
  `apply` that resolves what `check` found. The global CLI install is gated behind
  an explicit `apply install-cli` subaction. Auth is reported by presence only and
  its value is never printed; an env-var change defers verification to a fresh
  session. README setup bullet updated to the action shape.

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
