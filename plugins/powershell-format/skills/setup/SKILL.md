---
name: setup
description: "Verify the powershell-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up powershell-format', 'configure powershell-format', 'is powershell-format working', PowerShell formatting or linting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — formatting and linting rules
come from the repository's own `PSScriptAnalyzerSettings.psd1`, and the only tunable is the
native `userConfig` toggle. The `pwsh` runtime and the PSScriptAnalyzer module are resolved
from the environment (never bundled, never downloaded), and the plugin installs nothing, so
`apply` is guidance-only with **no write path** — it never modifies the repository, user
settings, or the plugin cache.

Note the deliberate asymmetry vs the sibling formatter plugins: only `jq` absence is a
prerequisite defect here. A machine without PowerShell — or without the PSScriptAnalyzer
module, or a repo without a settings file — is treated as **not-applicable, not missing**: the
hook stays quiet by design, so `check` reports these as INFO, never FAIL.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/powershell-format.sh`) is the single source of
truth for what it requires and how it resolves things. **Read it first** — probe what it
actually does, don't recite this file. Then run each probe via Bash and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   a Bash 5.0+ builtin).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of running. This is the only FAIL-class prerequisite.
3. **`pwsh` (PowerShell 7+)** — probe read-only:
   `pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'`. INFO,
   not FAIL: the hook probes `pwsh` only (never legacy `powershell.exe`) and stays quiet when
   it is absent — a machine without PowerShell is not-applicable by design. Report the version
   when present.
4. **PSScriptAnalyzer module** — probe **only when `pwsh` resolved** (chain behind step 3 so
   the probe never errors on a pwsh-less box):
   `pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { "present" } else { "absent" }'`.
   INFO, not FAIL: absent → the hook is a clean quiet no-op (same not-applicable
   classification). This probe is read-only — `Get-Module -ListAvailable` inspects, it does
   not format, lint, or mutate.
5. **`PSScriptAnalyzerSettings.psd1` opt-in** — INFO: the hook runs **only when a
   `PSScriptAnalyzerSettings.psd1` governs the edited file** (walking up from the file to the
   repo root, bounded by `CLAUDE_PROJECT_DIR` when set, stopping at the closest one). Absence
   is the opt-out and is **by design, not a defect** — the plugin is inert until a repo adopts
   a settings file. Report whether one exists and its location. When one exists, surface the
   README **Trust model**: the settings file is executed-adjacent configuration — a
   `CustomRulePath` it declares is loaded and run during analysis on every edit — so it
   carries the same trust as build/CI configuration. Do not enable this plugin against an
   untrusted working tree.
6. **Hook toggle** — report the effective `powershell_format_enabled` value:
   `${user_config.powershell_format_enabled}` (unexpanded or empty means default `true`; any
   value other than `true` disables the hook).
7. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each finding point at the resolution — this skill installs nothing:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- `pwsh` absent (and PowerShell support is wanted): point at installing
  [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell);
  this skill never installs it. If PowerShell is genuinely not applicable on this machine,
  leaving it absent is a valid end state — the hook stays quiet.
- PSScriptAnalyzer module absent: `Install-Module PSScriptAnalyzer` is **user-scope guidance
  only** — state the command for the reader to run; this skill never runs it.
- no `PSScriptAnalyzerSettings.psd1` (and linting/formatting is wanted): explain that adding a
  settings file at or below the project root opts the repo in — but this skill does not write
  it. The settings file is the executed-adjacent trust boundary above; the choice and the edit
  belong to the consumer.
- toggle off: direct to `/plugin configure powershell-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall powershell-format -s <scope>` then
  `claude plugin install powershell-format@<marketplace> -s <scope> --config powershell_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.

After pointing at a remediation, re-run the relevant `check` probe and report its actual
result — never claim resolved on the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter or linter — editing any `.ps1`, `.psm1`, or `.psd1` file exercises the
  hook end-to-end. The `check` pwsh probes are read-only capability checks; they never format,
  lint, or mutate any file.
- Write anything: not the repository (including `PSScriptAnalyzerSettings.psd1`), not Claude
  Code user settings, not `pluginConfigs`, not the plugin cache. The `pwsh` runtime and the
  PSScriptAnalyzer module are resolved from the environment, never installed, so remediation is
  guidance only.
- Download tools during `check` beyond the read-only presence and version probes.
