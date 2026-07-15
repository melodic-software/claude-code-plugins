# Changelog

All notable changes to the `source-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- **Exec-bit check in `/source-control:commit`.** Immediately after staging, newly-added files whose
  first line is a shebang (`#!`) are checked against the index and fixed with
  `git update-index --chmod=+x` when staged non-executable. Closes the gap where a new `.sh`/`.py`
  script lands as mode `100644` and is only caught by a CI exec-bit lint lane after the push
  round-trip.
- **Format-before-push check in `/source-control:commit`.** Before drafting the commit message, the
  skill now checks the consuming repo for an already-configured formatter/linter (`package.json`
  scripts, `biome.json`, a `Makefile` target, `.editorconfig` + `editorconfig-checker`, or an
  equivalent repo-native tool) and runs it against the staged files, re-staging any fixes. Runs only
  tooling that already exists in the consuming repo; skips silently when none is discoverable.
