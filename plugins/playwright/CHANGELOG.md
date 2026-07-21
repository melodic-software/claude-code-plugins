# Changelog

All notable changes to the `playwright` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Added

- Synced vendored upstream baseline from `@playwright/cli@0.1.13` to `0.1.17`
  and folded the genuine new commands/flags into the distilled reference
  files: `find` (context-search a snapshot without capturing it all),
  `--hires` screenshots, `--mobile`/`--device=` emulation, and Windows
  `&`-in-URL shell-escaping guidance, all in `reference/commands.md`;
  `video-show-actions`/`video-hide-actions` auto-annotated video overlays in
  `reference/tracing-and-video.md`; and a pointer to the (now-merged)
  spec-driven plan/generate/heal workflow in `reference/test-generation.md`.

## [0.3.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. The vendored Apache-2.0 upstream license reference (shipped
  in-plugin) is unchanged. No behavior change.

## [0.3.1]

### Changed

- Artifact-naming example in the tracing/video reference drops the tracker-shaped
  `issue-123` filename token and the hardcoded `docs/evidence/` directory for
  agnostic `<artifact-dir>/<descriptive-name>` placeholders, so the destination
  comes from the consumer's own project conventions rather than presuming
  GitHub-integer issue numbering and a mandated evidence-directory layout.

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
