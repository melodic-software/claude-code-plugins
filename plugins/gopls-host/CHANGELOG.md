# Changelog

All notable changes to the `gopls-host` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-28

### Added

- Native `gopls` control ([#3539](https://github.com/melodic-software/claude-code-plugins/issues/3539)). `/gopls-host:probe` reports whether `gopls` or `gopls.exe` on `PATH` is a native executable and whether that directory is `GOBIN` or `GOPATH/bin`. `--lsp` spawns that absolute binary with `serve` and checks hover, definition, and references. No language-server fork and no `.cmd` shim.
