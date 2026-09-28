# Changelog

All notable changes to the `csharp-lsp` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-28

### Added

- A launcher that starts `csharp-ls` from the dotnet global tools directory when it is not on PATH, and sets `DOTNET_ROOT` (and `DOTNET_ROOT_X64` on Windows x64) from the `dotnet` host when those variables are unset ([#3536](https://github.com/melodic-software/claude-code-plugins/issues/3536)).
