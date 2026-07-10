# powershell-format

A Claude Code plugin that formats and lints PowerShell the moment you edit it. On
every `Write` or `Edit` of a `.ps1`, `.psm1`, or `.psd1` file it runs
[PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview)'s
`Invoke-Formatter` (formatting in place) and `Invoke-ScriptAnalyzer` (linting),
then surfaces any residual findings back to Claude as advisory context.

It uses **your repository's own analyzer settings**. It ships no rules of its own
and runs only when your repo has opted into a `PSScriptAnalyzerSettings.psd1`.

## Behavior

- **Opt-in on a settings file.** PSScriptAnalyzer runs **only when a
  `PSScriptAnalyzerSettings.psd1` governs the edited file**, found by walking up
  from the file to the repository root and stopping at the closest one. Unlike
  some formatters, PSScriptAnalyzer does not auto-discover its settings —
  `Invoke-Formatter` and `Invoke-ScriptAnalyzer` take an explicit settings path —
  so the hook both gates on that file and passes it through. A repo without a
  settings file is left untouched rather than formatted and linted with
  PSScriptAnalyzer's built-in defaults, so the plugin never imposes a style you
  did not choose.
- **Format on edit.** `Invoke-Formatter` applies your settings' formatting rules
  (indentation, alias expansion, brace placement, and so on) in place.
- **Findings are advisory.** Semantic diagnostics your settings enable (for
  example `PSAvoidGlobalVars`) are *reported* but never auto-applied.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Graceful degrade.** If PowerShell (`pwsh`) is not installed, or the
  PSScriptAnalyzer module is not available, the hook is a clean silent no-op —
  no error spam. `pwsh` is resolved from `PATH` and is never downloaded.

## Trust model

The opt-in `PSScriptAnalyzerSettings.psd1` is **executed-adjacent configuration**,
not inert data. A settings file may declare a
[`CustomRulePath`](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/using-scriptanalyzer#custom-rules)
pointing at PowerShell rule modules, and PSScriptAnalyzer **loads and runs** those
modules' exported functions during analysis. Treat the settings file — and any
module it references — with the same trust you give your build and CI
configuration: it runs on your machine on every edit. The hook only reads a
settings file at or below your project root (bounded by `CLAUDE_PROJECT_DIR` when
set), so it never picks up one from an ancestor directory outside the project.
Do not enable this plugin against an untrusted working tree.

## Requirements

- **PowerShell** (`pwsh`) on `PATH` — PowerShell 7+ (cross-platform) or Windows
  PowerShell. If absent, the hook is a silent no-op.
- The **PSScriptAnalyzer** module installed
  (`Install-Module PSScriptAnalyzer`). If absent, the hook is a silent no-op.
- A **`PSScriptAnalyzerSettings.psd1`** in your repo — the opt-in.

The hook itself runs on Bash 3.2+. Telemetry timing uses `EPOCHREALTIME`
(Bash 5.0+); on older bash the telemetry envelope is skipped while formatting and
linting still run.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install powershell-format@melodic-software
```

## Configuration

This plugin has no `userConfig` — its only "configuration" is the
`PSScriptAnalyzerSettings.psd1` already in your repository, which it reads
automatically. To change the rules, edit that file.

### Disable without uninstalling

Set the kill switch in your settings `env` block:

```json
{ "env": { "HOOK_POWERSHELL_FORMAT_ENABLED": "false" } }
```

## License

[MIT](../../LICENSE).
