---
description: "Verify powershell-format's prerequisites and which formatter and linter its hooks run here, and register its git pre-commit entries. Use when: 'set up powershell-format', 'configure powershell-format', 'is powershell-format working', 'which formatter does powershell-format run', PowerShell formatting or linting silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | check inspect (read-only) | apply | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply] [inspect|install-git-hooks [scope=local|shared]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" inspect:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs inspect:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
  - "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh\" --resolve)"
  - "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh\" --resolve:*)"
  - "Bash(sh ${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh --resolve)"
  - "Bash(sh ${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh --resolve:*)"
  - "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh\" --resolve)"
  - "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh\" --resolve:*)"
  - "Bash(sh ${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh --resolve)"
  - "Bash(sh ${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh --resolve:*)"
shell: bash
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. PowerShell formatting and linting are two concerns, each with its own
git-hook entry. The hooks run only the plugin's shipped PSScriptAnalyzer adapter, where a
`PSScriptAnalyzerSettings.psd1` governs the file, and otherwise nothing; they never run a command
from the repository's powershell record (`.claude/ecosystems/powershell.yaml`), which
`/toolchain:lint` and `/toolchain:check` run on request. The only consumer-project files this
plugin writes are its git-hook entry copies (`apply install-git-hooks`); the record is written by
`/toolchain:setup apply powershell`, never here. Rules come from the repository's own settings
file, and the tunables are the native `userConfig` options (the on/off toggle and the
end-of-turn check). The `pwsh` runtime and the PSScriptAnalyzer module are resolved from the
environment (never bundled, never downloaded), and the plugin installs nothing, so `apply` is
otherwise guidance-only. It never modifies user settings or the plugin cache.

A machine without PowerShell or the PSScriptAnalyzer module, or a repo without a settings file,
is INFO in `check` while no settings file opts the adapter in: the hooks then run nothing by
design. Where a settings file does opt in, `check` step 3's rows decide.

Action routing: no argument or `check` runs the check; `check inspect` runs only the
`check inspect` section; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive. Never prompt when the action is given.
`apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The entries (`${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh` and `lint.sh`), their adapter
(`adapters.sh` and `psscriptanalyzer.ps1` beside them) and the resolver they share are the single
source of truth for what the plugin requires and how it resolves things; step 3 asks the
resolver itself.

**Read them first.** Probe what they actually do, don't recite this file. Then run the
probes via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hooks exit through their enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL in either state: every hook row launches
`node`, and the gate runs inside `hooks/exec-bash.mjs`.

1. **Bash version.** Check against the floor, Bash 3.2 or newer (`${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/check-lib.sh`).
2. **`node`.** Probe via Bash: `command -v node`, then `node --version` when it resolves. FAIL if
   absent: every handler in `hooks/hooks.json` launches through `node hooks/exec-bash.mjs`, so
   without `node` the hook never starts and says nothing (README Requirements). The hook process
   resolves bare `node` from the persisted Machine/User PATH, not from this shell. On Windows a
   version manager can return a per-call path whose directory name contains a process id (fnm's
   `fnm_multishells\<pid>_<timestamp>\node`); that path is ephemeral, so FAIL when it is the only <!-- portability-ok: Windows path, not a shell regex -->
   hit, say so, and report the persisted resolution separately from
   `[Environment]::GetEnvironmentVariable('Path','Machine')` and `'User'`. A non-ephemeral in-shell
   hit is INFO beside that result, not a PASS by itself.
3. **What each concern resolves to.** From the repository root run
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh" --resolve` and
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh" --resolve`. Each prints one row: plugin, concern,
   source, tool, found, detail, tab-separated. It reads the adapter's config and runs nothing.
   Append repository paths (`--resolve src/a.ps1 build/b.psm1`) for one row per file, since the
   closest settings file governs each file; the detail column then names it, or the row says
   nothing resolved. The adapter's own rules (which settings file opts a file in, where `pwsh`
   comes from) are in `${CLAUDE_PLUGIN_ROOT}/git-hooks/adapters.sh`: read them to explain a row.
   Report one line per concern from the rows, never from this text:
   - `adapter:<name>` with found `yes`: PASS, naming the adapter's tool and the settings file that
     opted in. Report the `pwsh` version too:
     `pwsh -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()'`.
   - found `no`: FAIL; the remediation is the adapter tool's
     `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` install hints (Read that path).
   - `none`: INFO "unresolved": no settings file governs the repository, so the hooks run
     nothing. This is the opt-out by design.
   A detail saying a powershell record exists is INFO beside the row: the hooks never run it, and
   `/toolchain:lint` or `/toolchain:check` runs it on request.
4. **PSScriptAnalyzer module.** Probe **only when a row found `pwsh`** (so the probe never errors
   on a pwsh-less box):
   `pwsh -NoProfile -NonInteractive -Command 'if (Get-Module -ListAvailable -Name PSScriptAnalyzer) { "present" } else { "absent" }'`.
   Absent is FAIL while a row resolved to the adapter: an agent commit then fails with the
   install command and a person's commit gets a notice, as the check-placement contract says,
   and the Stop check stays silent. The probe is read-only: `Get-Module -ListAvailable`
   inspects, it does not format, lint, or mutate.
5. **Trust model.** When a row resolved to the adapter, surface the README **Trust model**: the
   settings file is executed-adjacent configuration. A `CustomRulePath` it declares would load
   and run repository-supplied rule modules, so both entries skip such a settings state until
   the user approves its exact content (a marker under the repository's git common directory in
   `powershell-format/trust-approvals`, one store for every session and commit; any settings or
   rule-module change revokes it). It carries the same trust as build/CI configuration.
6. **Draft, never write, the record.** When a concern is unresolved, or the person names a tool
   the plugin ships no adapter for, say that the hooks will not run that tool: they run only the
   shipped adapter. Find the repository's own formatter and linter by the steps in
   [reference/ecosystem-resolution.md](../../reference/ecosystem-resolution.md), and draft the
   `fix-cmd` and `lint-cmd` values: each holds `<files>`, `fix-cmd` only formats and `lint-cmd`
   only reports, with findings as `<path>:<line>` lines. Hand the draft to
   `/toolchain:setup apply powershell`, the one writer of those keys, so `/toolchain:lint` and
   `/toolchain:check` can run them on request.
7. **Hook toggle.** Report the effective `powershell_format_enabled` value:
   `${user_config.powershell_format_enabled}` (unexpanded or empty means default `true`; any
   value other than `true` disables the hooks). Also report `powershell_format_end_of_turn`:
   `${user_config.powershell_format_end_of_turn}` (unexpanded or empty means the shipped default
   `false`), as INFO: on, the Stop row lints the uncommitted changes once per turn; off, only the
   git pre-commit entries run.
8. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
9. **Git pre-commit entries.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. It lists `format` and `lint`. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale`, `modified` or `superseded` is a
   FAIL whose remediation is `apply install-git-hooks`; a `superseded` detail lists what an install under an earlier plugin or entry name left (the single entry these two replaced), which that action removes on the user's yes. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool (the entry's resolved tool) with its install method from the
   `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), so a lane or cloud setup script can provision it before an
   auto-mode session commits. Outside a git repository, report INFO and skip the step.

## `check inspect` (read-only)

Lists what runs at each git hook stage in this repository, under whichever hook manager it uses,
and times this plugin's own entries. Run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" inspect` from the repository (add
`--runs <n>` to time each entry more often) and render its JSON as one table per stage: each item's
kind, name and source, then its `measured` median and range with the input it ran on and its exit
codes, or `not measured` with the `notMeasured` reason. A stage whose `installed` is false has no
hook file git runs: say the manager's install step has not run in this clone. The script runs only
this plugin's installed entries that change no files and still match what the plugin ships; it never runs a repository's own hook,
another plugin's entry, a lefthook job or a Husky.Net task. To place a new check, compare the
numbers with the duration budgets in the check-placement contract
(`docs/contracts/check-placement/README.md#duration-budgets` in the marketplace repository).
Modify nothing. Outside a git repository, report INFO and stop.

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
   `--manager` when you passed one). It prints `installed`, `refreshed`, `unchanged`, `refused`,
   `blocked`, `unsafe-path` or `stage-failed` per entry; `refused` means a locally edited copy or
   dispatcher, which the `modified` decision covers, `blocked` that another tool owns the local
   hooks directory, which the `hooks-path-owned` decision covers, `unsafe-path` the decision of
   that name, and `stage-failed` that `git add` failed on a shared install: report it, since the
   team would not receive the files. Each entry's adapter files are copied beside its script.
5. **Decisions.** Read [reference/git-hook-decisions.md](reference/git-hook-decisions.md) for
   what each kind asks of you, apply each one, then rerun `plan` until only the decisions you
   chose to leave remain.
6. **Verify.** Run `verify` and report its lines as `check` step 9 does.

The `format` entry rewrites: at commit it formats the staged PowerShell files and stages the
result, so tell the user that a commit can change the files it contains, and that a partly
staged PowerShell file is refused untouched. The `lint` entry only reports findings on the lines
the commit adds. Each starts `pwsh`, which costs about a second per commit that stages
PowerShell. A decline of the earlier single entry carries to both. When a
`PSScriptAnalyzerSettings.psd1` declares `CustomRulePath`, both entries skip that state until
the user approves it; tell the user the approval command only in the user's own channel, never
in text an agent commit would print.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry format` (or `lint`); the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains to the user each scope and why a formatter's cleanup PR comes first.

## `apply` (idempotent)

Run `check`, then for each finding point at the resolution. This skill installs nothing:

- missing `node` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- `pwsh` absent (and PowerShell support is wanted): point at the install hints in
  `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), matching the entries'
  missing-tool text; this skill never installs it. If PowerShell is genuinely not applicable on this machine,
  leaving it absent is a valid end state. The hooks stay quiet; the once-per-session probe
  notice is the only signal, and `powershell_format_enabled` false or disabling the plugin stops it.
- PSScriptAnalyzer module absent: `Install-Module PSScriptAnalyzer` is **user-scope guidance
  only**. State the command for the reader to run; this skill never runs it.
- no `PSScriptAnalyzerSettings.psd1` (and linting/formatting is wanted): explain that adding a
  settings file at or below the project root opts the repo in, but this skill does not write
  it. The settings file is the executed-adjacent trust boundary above; the choice and the edit
  belong to the consumer.
- a concern unresolved, or a tool the plugin ships no adapter for: `check` step 6's draft, for
  `/toolchain:setup apply powershell`.
- toggle off: set `powershell_format_enabled` to `true` through Claude Code's native flow,
  interactively with `/plugin configure powershell-format@<marketplace>` or by a headless route,
  as the marketplace's plugin-reconfiguration convention gives them in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
  (it owns the verified-version record). Apply the scope and failure-signal caveats in its
  [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
  Read both sections and print what they give, the fallback route, its behavior on an
  already-installed plugin and the scope to pass included, rather than only naming them, and
  leave out the verified-version record.
  Never uninstall to reconfigure; that section links what an uninstall deletes. This skill never
  writes user settings or `pluginConfigs`. Afterwards rerun `check` in a **fresh session**, since a
  same-session `check` can still show the old value, and report the observed effective value,
  never an unobserved change.

  - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
    when a saved value applies, fetch
    [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
    live.

After pointing at a remediation, re-run the relevant `check` probe live via Bash and report its
actual result. Never claim resolved on the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Next

/toolchain:setup apply powershell, with the drafted `fix-cmd` and `lint-cmd`, when the repository
wants a tool the plugin ships no adapter for; /toolchain:lint then runs it on request.

## What this skill does not do

- Run the formatter or linter. `git commit` of a `.ps1`, `.psm1`, or `.psd1` file exercises the
  installed pre-commit entries end-to-end. The `check` pwsh probes and `--resolve` rows are read-only; they never format,
  lint, or mutate any file.
- Write the powershell record: `/toolchain:setup apply powershell` does.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the repository,
  including `PSScriptAnalyzerSettings.psd1`. The `pwsh` runtime and the PSScriptAnalyzer module
  are resolved from the environment, never installed, so remediation is guidance only.
- Download tools during `check` beyond the read-only presence and version probes.
