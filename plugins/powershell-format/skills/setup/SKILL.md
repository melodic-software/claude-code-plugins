---
description: "Verify powershell-format's prerequisites and configuration here, and register its git pre-commit entry. Use when: 'set up powershell-format', 'configure powershell-format', 'is powershell-format working', PowerShell formatting or linting silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | apply | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply [install-git-hooks [scope=local|shared]]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. The only consumer-project files this plugin owns are its git-hook
entry copies, which `apply install-git-hooks` writes. Formatting and linting rules come from
the repository's own `PSScriptAnalyzerSettings.psd1`, and the tunables are the native
`userConfig` options (the on/off toggle and the end-of-turn check). The `pwsh` runtime and the
PSScriptAnalyzer module are resolved from the environment (never bundled, never downloaded),
and the plugin installs nothing, so `apply` is otherwise guidance-only. It never modifies
user settings or the plugin cache.

Note the deliberate asymmetry vs the sibling formatter plugins: only `node` absence is a
prerequisite defect here. A machine without PowerShell, or without the PSScriptAnalyzer
module, or a repo without a settings file, is INFO in `check`, never FAIL: the hooks stay
quiet by design. A machine without PowerShell still gets the `SessionStart` probe's notice once per
session while the plugin is enabled.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive. Never prompt when the action is given.
`apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The pre-commit check (`${CLAUDE_PLUGIN_ROOT}/git-hooks/powershell-check.sh`) and its
`powershell-check.ps1` are the single source of truth for what the plugin requires and how it
resolves things.

**Read them first.** Probe what they actually do, don't recite this file. Then run the
probes via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO. The hooks exit through their enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version.** Check against the documented floor (README Requirements).
2. **`node`.** Probe via Bash: `command -v node`, then `node --version` when it resolves. FAIL if
   absent: every handler in `hooks/hooks.json` launches through `node hooks/exec-bash.mjs`, so
   without `node` the hook never starts and says nothing (README Requirements). The hook process
   resolves bare `node` from the persisted Machine/User PATH, not from this shell. On Windows a
   version manager can return a per-call path whose directory name contains a process id (fnm's
   `fnm_multishells\<pid>_<timestamp>\node`); that path is ephemeral, so FAIL when it is the only <!-- portability-ok: Windows path, not a shell regex -->
   hit, say so, and report the persisted resolution separately from
   `[Environment]::GetEnvironmentVariable('Path','Machine')` and `'User'`. A non-ephemeral in-shell
   hit is INFO beside that result, not a PASS by itself. `node` is the only FAIL-class
   prerequisite.
3. **`pwsh` (PowerShell 7+).** Probe read-only:
   `pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'`. INFO,
   not FAIL: the plugin probes `pwsh` only (never legacy `powershell.exe`) and the hooks stay
   quiet when it is absent, while the `SessionStart` probe reports it once per session on every
   host where the plugin is enabled. Report the version when present.
4. **PSScriptAnalyzer module.** Probe **only when `pwsh` resolved** (chain behind step 3 so
   the probe never errors on a pwsh-less box):
   `pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { "present" } else { "absent" }'`.
   INFO, not FAIL: absent → an agent commit fails with the install command and a person's commit gets a notice, as the check-placement contract says; the Stop check stays silent. This probe is read-only. `Get-Module -ListAvailable` inspects, it does
   not format, lint, or mutate.
5. **`PSScriptAnalyzerSettings.psd1` opt-in.** INFO: the check runs **only on a file a
   `PSScriptAnalyzerSettings.psd1` governs** (walking up from the file to the repo root,
   stopping at the closest one). Absence
   is the opt-out and is **by design, not a defect**. The plugin is inert until a repo adopts
   a settings file. Report whether one exists and its location. When one exists, surface the
   README **Trust model**: the settings file is executed-adjacent configuration. A
   `CustomRulePath` it declares would load and run repository-supplied rule modules during
   analysis, so the check skips such a settings state until the user approves its exact content (a marker
   under the repository's git common directory in `powershell-format/trust-approvals`, one
   store for every session and commit; any settings or rule-module change revokes it). It carries the same trust as build/CI configuration.
6. **Hook toggle.** Report the effective `powershell_format_enabled` value:
   `${user_config.powershell_format_enabled}` (unexpanded or empty means default `true`; any
   value other than `true` disables the hooks). Also report `powershell_format_end_of_turn`:
   `${user_config.powershell_format_end_of_turn}` (unexpanded or empty means the shipped default
   `false`), as INFO: on, the Stop row checks the uncommitted changes once per turn; off, only the
   git pre-commit entry runs.
7. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
8. **Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale` or `modified` is a
   FAIL whose remediation is `apply install-git-hooks`. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool with its install method from the
   plugin's `prerequisites.json`, so a lane or cloud setup script can provision it before an
   auto-mode session commits. Outside a git repository, report INFO and skip the step.

## `apply install-git-hooks [scope=local|shared]`

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager. The installer script only detects, renders and writes files the plugin owns; every step
that needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/powershell-format/`,
   so every teammate and agent gets it). When nobody can answer, use `local`.
2. **Plan.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" plan --scope <scope>`
   and read the JSON: `manager`, `actions[]`, `decisions[]`.
3. **Manager conflict.** A `manager-conflict` decision lists the evidence (two managers, or one
   this installer does not drive, such as the pre-commit framework). Show it and ask which manager
   should carry the entry; rerun `plan` with `--manager lefthook|husky|plain`. Without an answer,
   stop here and report.
4. **Actions.** When `actions[]` holds `copy` items, run
   `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" copy --scope <scope>` (plus the same
   `--manager` when you passed one). It prints `installed`, `refreshed`, `unchanged`, `refused` or
   `blocked` per entry; `refused` means a locally edited copy, which the `modified` decision
   covers, and `blocked` means another tool owns the local hooks directory, which the
   `hooks-path-owned` decision covers. The entry's `powershell-check.ps1` is copied beside its
   script.
5. **Decisions.** Read [reference/git-hook-decisions.md](reference/git-hook-decisions.md) for
   what each kind asks of you, apply each one, then rerun `plan` until only the decisions you
   chose to leave remain.
6. **Verify.** Run `verify` and report its lines as `check` step 8 does.

The entry rewrites: at commit it formats the staged PowerShell files and stages the result, so
tell the user that a commit can change the files it contains, and that a partly staged
PowerShell file is refused untouched. It runs Invoke-Formatter, which costs about a second per
commit that stages PowerShell. When a `PSScriptAnalyzerSettings.psd1` declares `CustomRulePath`,
the entry skips that state until the user approves it; tell the user the approval command only
in the user's own channel, never in text an agent commit would print.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry powershell-check`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/check-placement/adopting-git-hooks.md) explains to the user each scope and why a formatter's cleanup PR comes first.

## `apply` (idempotent)

Run `check`, then for each finding point at the resolution. This skill installs nothing:

- missing `node` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- `pwsh` absent (and PowerShell support is wanted): point at installing
  [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell);
  this skill never installs it. If PowerShell is genuinely not applicable on this machine,
  leaving it absent is a valid end state. The hooks stay quiet; the once-per-session probe
  notice is the only signal, and `powershell_format_enabled` false or disabling the plugin stops it.
- PSScriptAnalyzer module absent: `Install-Module PSScriptAnalyzer` is **user-scope guidance
  only**. State the command for the reader to run; this skill never runs it.
- no `PSScriptAnalyzerSettings.psd1` (and linting/formatting is wanted): explain that adding a
  settings file at or below the project root opts the repo in, but this skill does not write
  it. The settings file is the executed-adjacent trust boundary above; the choice and the edit
  belong to the consumer.
- toggle off: reconfigure through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive `/plugin configure powershell-format@<marketplace>`
  any time, or headless
  `claude plugin install powershell-format@<marketplace> -s <scope> --config powershell_format_enabled=true`
  (repeatable per key). Against an already-installed plugin it prints `already installed` and
  still writes the value. Do **not** uninstall to reconfigure: that drops the plugin's entire
  stored `pluginConfigs` entry, resetting every option in the README's Options reference to its
  manifest default. `-s` defaults to `user`; pass the scope `claude plugin list` reports, and run
  from that project's directory for a `project`/`local` scope, or the rerun adds a second
  install record at the scope passed and enables the plugin there; the value itself always
  lands in user settings. A rejected value prints a warning yet exits 0, so read the output.
  This skill never writes user settings or `pluginConfigs`. Afterwards rerun
  `check` in a **fresh session**. The rendered `${user_config.*}` and the hook's
  `CLAUDE_PLUGIN_OPTION_*` are fixed at session start, so a same-session `check` still reports
  the OLD value; report the observed effective value, never an unobserved change.

After pointing at a remediation, re-run the relevant `check` probe live via Bash (a pre-computed row
predates the remediation, so never re-read it) and report its actual result. Never claim resolved on
the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter or linter. `git commit` of a `.ps1`, `.psm1`, or `.psd1` file exercises the
  installed pre-commit entry end-to-end. The `check` pwsh probes are read-only capability checks; they never format,
  lint, or mutate any file.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the repository,
  including `PSScriptAnalyzerSettings.psd1`. The `pwsh` runtime and the PSScriptAnalyzer module
  are resolved from the environment, never installed, so remediation is guidance only.
- Download tools during `check` beyond the read-only presence and version probes.
