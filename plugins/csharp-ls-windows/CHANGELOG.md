# Changelog

All notable changes to the `csharp-ls-windows` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-28

### Added

- Windows spawn adapter for the `csharp-ls` dotnet global tool ([#3536](https://github.com/melodic-software/claude-code-plugins/issues/3536)). `.lsp.json` starts `node` on `bin/csharp-ls-windows-spawn.mjs`. The adapter resolves `csharp-ls.exe` from `PATH`, sets `DOTNET_ROOT` from the `dotnet` host when that variable is unset, and refuses a `.cmd` shim. `/csharp-ls-windows:probe` reports the same plan.
