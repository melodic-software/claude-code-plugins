# Lane: shell-tooling

Bash and PowerShell scripts in the project's tooling directories. **The single most important rule of this lane: agent-hook and git-hook script directories are HARD-EXCLUDED for mutation.** Those directories are recursive infrastructure — a tidying that breaks a hook silently degrades every future session.

## Scope

```text
tools/**/*.sh
tools/**/*.ps1
scripts/**/*.sh
scripts/**/*.ps1
```

(`**` matches zero or more directories, so these cover both `tools/x.sh` and `tools/a/b/y.sh`.)

Adjust to the consuming project's actual tooling directories (a project lane at `.claude/tidy-lanes/shell-tooling.md` overrides this file entirely). Hook directories (`.claude/hooks/**`, `.lefthook/**`, `.husky/**`) are HARD-EXCLUDED at the lane level (and also globally) — read-only investigation is fine, mutation is not.

## Watch-for patterns

### Bash (`**.sh`)

- **shellcheck-fix-able patterns** — `shellcheck script.sh` surfaces candidates. Common: unquoted expansions (SC2086), `[ ]` instead of `[[ ]]` (SC2292), `which` instead of `command -v` (SC2230)
- **shfmt drift** — `shfmt -d script.sh` shows formatting deltas. Tidy in passing
- **Beck #1 — Guard Clauses** — early-exit patterns at the top of a script (`[[ -n "$VAR" ]] || exit 0`) over deeply-nested `if` blocks
- **Beck #2 — Dead Code** — variables set but never read (SC2034), commented-out blocks, abandoned `# TODO:` hints with no tracking
- **Beck #15 — Delete Redundant Comments** — `# Loop over files` above an obvious `for f in *; do` is noise
- **`local` discipline** — function variables should be `local`-scoped; missing `local` is a slow-burn bug that ShellCheck doesn't always catch
- **`set -euo pipefail` consistency** — every executable bash script should have it (or a documented reason it doesn't)

### PowerShell (`**.ps1`)

- **Array-literal modernization** — older patterns: `New-Object Collections.ArrayList` → `@()`. Verify the project's PowerShell version floor first
- **`[CmdletBinding()]` consistency** — every advanced function should declare it
- **Verb-Noun naming** — `Get-`, `Set-`, `New-`, etc. via `Get-Verb`. Tidying scope: function names that match approved verbs but read awkwardly
- **Beck #1 — Guard Clauses** — `if (-not $foo) { return }` early-exits over nested `if/else`
- **`-ErrorAction Stop` placement** — should be on the cmdlet that needs it, not the whole script unless intentional

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **Agent-hook directories (`.claude/hooks/**`) — HARD-EXCLUDED for mutation.** Read-only investigation OK (to understand patterns); editing is deferred
- **Git-hook manager config and script dirs (`lefthook.yml`, `.lefthook/**`, `.husky/**`, `.pre-commit-config.yaml`) — HARD-EXCLUDED for mutation.** They control the entire local hook chain. Read-only investigation OK
- **Bootstrap/install scripts** — SOFT-EXCLUDED for behavioral changes. Reading-order / comment cleanup OK; logic changes defer
- **CI-invoked test runners** — SOFT-EXCLUDED. Behavioral changes to a script CI invokes need a CI run to validate. Beck #5 / #15 tidyings OK; argument-parsing changes defer

## Verification commands

```bash
shellcheck <changed .sh files>
shfmt -d <changed .sh files>
pwsh -NoProfile -NonInteractive -Command "Invoke-ScriptAnalyzer -Path <changed .ps1 files>"
```

Plus the project's own shell test suite if one exists (check the consuming project's CLAUDE.md / CI config for the canonical command).

## Conventional Commits type

`chore:`. Tooling improvements aren't features (`feat:`), aren't behavioral fixes to product code (`fix:`), and aren't strictly refactor in the compiled-code sense. Example titles:

- `chore(tools): apply shellcheck/shfmt drift across tools/*.sh`
- `chore(tools): modernize array literals in PowerShell scripts`

## Preferred research sources

### Bash

- **Vidar Holen** — author of ShellCheck; canonical authority on bash linting and pitfalls
- **Greg Wooledge** — `wooledge.org` BashFAQ / BashGuide; canonical authority on bash semantics, `set -e` corner cases, quoting rules
- **Stéphane Chazelas** — POSIX shell, security implications of bash patterns

### PowerShell

- **Jeffrey Snover** — creator of PowerShell, design philosophy, advanced functions
- **Don Jones** — PowerShell community lead, scripting best practices, cmdlet design
