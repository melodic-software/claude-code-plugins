# Changelog

All notable changes to the `bug-report` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0]

### Changed

- **Setup adopts the uniform contract's check-only carve-out** (fleet
  conformance wave, dim 8). The plugin's entire configuration is the native
  `output_dir` userConfig, so `check` is the sole action: it verifies and
  reports, states the machine-private-vs-repository tradeoff instead of
  asking, and routes reconfiguration through Claude Code's native flow with
  the fresh-install-only `--config` semantics stated. Rechecks after
  reconfiguration defer to a fresh session (the rendered value is injected at
  load).

## [0.4.0]

### Changed

- Renamed the `bug-report` skill → `write`. Update any `/bug-report:bug-report` invocations to
  `/bug-report:write`; the plugin ID (`bug-report`) is unchanged, only the skill's leaf name moved.
