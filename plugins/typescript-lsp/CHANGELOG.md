# Changelog

All notable changes to the `typescript-lsp` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-28

### Added

- A Windows-safe launcher for `typescript-language-server`. `.lsp.json` starts `node` with the bundled launcher and `--stdio`. The launcher finds `lib/cli.mjs` and re-spawns it with `node`, and on Windows falls back to `cmd.exe /d /s /c` only when the JavaScript entry cannot be resolved ([#3537](https://github.com/melodic-software/claude-code-plugins/issues/3537)).
