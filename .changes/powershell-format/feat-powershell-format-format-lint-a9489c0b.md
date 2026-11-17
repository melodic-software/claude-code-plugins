---
bump: major
---

### Changed

- Formatting and linting are separate concerns, each with its own git-hook entry and its own row in `setup check`. Both run only the PSScriptAnalyzer adapter, where a `PSScriptAnalyzerSettings.psd1` governs the file, and otherwise nothing. They never run a command from the repository's powershell record (`.claude/ecosystems/powershell.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists. File names reach `pwsh` as arguments, never as shell text. The `CustomRulePath` trust gate applies to both entries, and an approval already given still holds.
- `setup check` reports, per concern, the adapter, its tool and whether it is found, read from the entries' `--resolve` rows. A missing `pwsh` or PSScriptAnalyzer module is now FAIL where a settings file opts the adapter in, and stays INFO where none does. `setup apply` drafts `fix-cmd` and `lint-cmd` for `/toolchain:setup apply powershell` when the repository wants a tool the plugin ships no adapter for, and never writes the record.
- The opt-in end-of-turn check runs the `lint` entry and drops only missing-tool lines from what it hands back, so a finding printed beside one still reaches Claude.

### Removed

- The single `powershell-check` git-hook entry is retired for `format` (Invoke-Formatter; rewrites and re-stages; reports no finding) and `lint` (Invoke-ScriptAnalyzer; reports findings on added lines, never rewrites, and fails closed when the run exits non-zero without a `<path>:<line>` finding). Installed copies, lefthook jobs and the `checks.powershell-format.powershell-check.declined` key change; `setup check` reports an installed `powershell-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `powershell-check` carries to both new entries.
