# Changelog

All notable changes to the `firecrawl` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Added

- **Uniform-contract `setup` skill** (fleet conformance wave). `/firecrawl:setup check` reads
  the main skill as the single source of truth and probes the `firecrawl` binary (absence is
  INFO — the plugin is lazy-install by design) and `FIRECRAWL_API_KEY` presence in the OS
  user environment (presence only — the key value is never printed, logged, or persisted).
  `apply` is guidance-and-verify with no write path: it defers to the main skill's documented
  `npm install -g firecrawl-cli` flow and points at the OS-appropriate way to set the key,
  writing nothing.

## [0.2.2]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

## [0.2.1]

First versioned release covered by this changelog; see the git history of
`plugins/firecrawl/` for earlier changes.
