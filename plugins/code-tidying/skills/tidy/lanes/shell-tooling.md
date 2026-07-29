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

Retarget these to the consuming project's actual tooling directories with a project lane at `.claude/tidy-lanes/shell-tooling.md`. A project `Scope` block **replaces** the globs above (see [Merge semantics](#merge-semantics)); it does not have to restate the sections it keeps.

## Merge semantics

This lane is layered per the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md) ("Merge semantics"). A project lane at `.claude/tidy-lanes/shell-tooling.md` is **not** meant to replace this file wholesale — it merges with the bundled lane **per section**, so bundled improvements to sections the project does not touch keep reaching the repo. This is the declaration a project lane adopts (by reference or by restating it); it is the recommended shape for this lane:

- **`Scope`** — **per-section override.** A project `Scope` block replaces the bundled globs entirely; retargeting tooling layout is the whole reason a project writes a lane, and two glob sets do not meaningfully concatenate. A project lane that omits `Scope` keeps the bundled globs.
- **`Watch-for patterns`** — **additive (concatenate), per language subsection.** A project's `### Bash` entries are **appended** to the bundled `### Bash` list and its `### PowerShell` entries to the bundled `### PowerShell` list; entries under no subsection append to both, and a project subsection with no bundled counterpart (say `### Python`) is added as its own subsection. The generic patterns are never frozen out, and new bundled patterns flow to the project on upgrade.
- **`Lane-specific extra exclusions`** — **additive (concatenate).** A project's extra exclusions are appended to the bundled ones rather than replacing them; dropping the bundled hook-directory HARD exclusions is not something this lane's semantics offer, because they are the safety mechanism it exists around. Those specific directories are also on the plugin's global HARD list (`reference/exclusions.md`), which no lane layer resolves at all — so they hold even for a project lane that declares nothing.
- **`Preferred research sources`** — **per-section override at `###` granularity.** A project's `### Bash` sources replace the bundled `### Bash` sources; a subsection the project omits keeps the bundled authorities, so supplying only one language's sources never wipes the other's.
- **`Verification commands`** — **per-section override at language granularity.** A project's command block replaces the bundled commands for the languages it covers; the bundled command for a language the project block does not mention is kept, so retargeting the shell checks never silently drops the PowerShell one (or the reverse).
- **Every other section**, named here or not (`Conventional Commits type`, and anything a later version adds) — **per-section override**, same as `Scope`: a section the project supplies replaces the bundled one; a section it omits keeps the bundled value. The prose above the first `##` heading is bundled-only.

When a project lane at `.claude/tidy-lanes/shell-tooling.md` includes a `## Merge semantics` section, `/code-tidying:tidy` reads **both** that project lane and this bundled lane and merges them per **the project lane's** declaration — which is why adopting the shape above (`Merge semantics: per the bundled lane's declaration`) is what puts these rules in force. A project lane without that section resolves project-only, and none of the above applies to it.

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
