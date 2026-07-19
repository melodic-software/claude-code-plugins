# Changelog

All notable changes to the `playwright` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/playwright:setup check` reads
  the main skill and its `reference/` files as the single source of truth and probes the
  `playwright-cli` binary and browser resolvability (surfacing the `install-browser` step and
  sandbox-egress caveat from the plugin's own docs). `apply` is guidance-and-verify with
  exactly one write path — the explicitly invoked `apply install-cli`, which runs the global
  `npm install -g @playwright/cli` (stated before running) and re-probes the binary
  afterward. It points at `/playwright:playwright update` for the vendored-baseline flow
  rather than wrapping it.

## [0.2.1]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/playwright/` for earlier changes.
