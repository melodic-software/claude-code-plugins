# Changelog

All notable changes to the `gopls-lsp` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-28

### Added

- A `gopls` language server entry whose command is the native executable, with no shell and no `.cmd` wrapper, plus `scripts/probe-gopls.mjs`, which refuses a script and completes an LSP initialize over stdio ([#3539](https://github.com/melodic-software/claude-code-plugins/issues/3539)).
