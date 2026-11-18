---
description: "Verify bash-format's prerequisites and which formatter and linter its hooks run here, and register its git pre-commit entries. Use when: 'set up bash-format', 'configure bash-format', 'is bash-format working', 'which linter does bash-format run', shell lint or formatting silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only verification, default) | check inspect (read-only) | apply | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply] [inspect|install-git-hooks [scope=local|shared]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(command -v node*)"
  - "Bash(command -v shellcheck*)"
  - "Bash(command -v shfmt*)"
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

## Pre-computed context

`check`'s tool probes ran at load time. Read these rows instead of re-issuing them; each shows the
tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`
- `node`: !`command -v node 2>/dev/null || echo absent`
- `shellcheck`: !`command -v shellcheck 2>/dev/null || echo absent`
- `shfmt`: !`command -v shfmt 2>/dev/null || echo absent`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

- **Pointer**: for the placeholder a skipped load-time command leaves, fetch
  [skills § Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  live.
- **As of**: 2026-11-11
- **Recheck trigger**: the placeholder text changes.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. Shell formatting and linting are two concerns. The hooks run only the
plugin's shipped adapter for each, where that tool's own config governs the file, and otherwise
nothing; they never run a command from the repository's bash record (`.claude/ecosystems/bash.yaml`),
which `/toolchain:lint` and `/toolchain:check` run on request. The only consumer-project files this
plugin writes are its git-hook entry copies (`apply install-git-hooks`); the record is written by
`/toolchain:setup apply bash`, never here. The tunables are the native `userConfig` options (the
on/off toggle, the gitignored-file switch and the end-of-turn check).
Every prerequisite is a `PATH` binary the plugin never bundles, and the plugin never installs
system packages, so the rest of `apply` is guidance-only. It never modifies user settings or the
plugin cache.

Action routing: no argument or `check` runs the check; `check inspect` runs only the
`check inspect` section; `apply` runs the check first, then
offers remediation guidance. Both are non-interactive. Never prompt when the action is given.
`apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The batch hook (`${CLAUDE_PLUGIN_ROOT}/hooks/bash-format.sh`), the entries and the resolver they
share are the single source of truth for what the plugin requires and how it resolves things;
step 4 asks the resolver itself.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed tool rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL in either state: every hook row launches
`node`, and the gate runs inside `hooks/exec-bash.mjs`. A tool the git pre-commit entries need keeps
the grade it gets with the toggle on while those entries are installed (step 10 reports it as a
`tool` line beside an `ok`, `stale` or `modified` entry): the entries run at commit outside Claude
Code and read no toggle.

1. **Bash version.** Check against the hooks' floor, Bash 3.2 or newer (`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`).
2. **`node`.** The pre-computed `node` row. FAIL if absent: every hook row launches through
   `node hooks/exec-bash.mjs`, so without `node` the hook does not launch and no shell edit is
   formatted in the session (`${CLAUDE_PLUGIN_ROOT}/README.md` Requirements).
3. **`jq`.** The pre-computed `jq` row. FAIL if absent: the batch row does nothing, since it
   reads the file paths with `jq`, and the `format` entry cannot run its subscript guard.
4. **What each concern resolves to.** From the repository root run
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh" --resolve` and
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh" --resolve`. Each prints one row: plugin, concern,
   source, tool, found, detail, tab-separated. It reads the adapters' configs and runs nothing.
   Append repository paths (`--resolve scripts/a.sh lib/b.bash`) for one row per file, since each
   adapter's config walk can answer differently per file; the detail column then names the config
   that governs that file and the binary that would run, or why nothing resolved. Each adapter's
   own rules (which config opts a file in, where its binary comes from) are in
   `${CLAUDE_PLUGIN_ROOT}/git-hooks/adapters.sh`, and the format opt-in test is in
   `${CLAUDE_PLUGIN_ROOT}/git-hooks/shfmt-rewrite.sh`: read them to explain why a row names that
   config. Report one line per concern from the rows, never from this text:
   - `adapter:<name>` with found `yes`: PASS, naming the adapter's tool and that its config opted in.
   - found `no`: FAIL; the remediation is the adapter tool's
     `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` install hints (Read that path).
   - `none`: INFO "unresolved": no shipped adapter's config governs the repository for that
     concern, so the hooks run nothing for it. Only format can resolve to `none`: the lint adapter
     needs no config, and its detail says `none (ShellCheck defaults)` when no rc file exists. This is the opt-out by design, so a missing tool for
     an unresolved concern is INFO, not a defect. For format, shell files are then left as written
     rather than rewritten to shfmt's built-in defaults; a bare `[*]` section or a path-only one
     such as `[scripts/**]` does not opt in (`apply` below lists the sections that do).
   A detail saying a bash record exists is INFO beside the row: the hooks never run it, and
   `/toolchain:lint` or `/toolchain:check` runs it on request.
5. **Draft, never write, the record.** When a concern is unresolved, or the person names a tool the
   plugin ships no adapter for, say that the hooks will not run that tool: they run only the shipped
   adapters. Find the repository's own formatter and linter by the steps in
   [reference/ecosystem-resolution.md](../../reference/ecosystem-resolution.md), and draft the
   `fix-cmd` and `lint-cmd` values: each holds `<files>`, `fix-cmd` only formats and `lint-cmd` only
   reports, with findings as `<path>:<line>` lines. Hand the draft to `/toolchain:setup apply bash`,
   the one writer of those keys, so `/toolchain:lint` and `/toolchain:check` can run them on request.
6. **Hook options.** Report the effective values. `${user_config.bash_format_enabled}`
   (unexpanded or empty means the manifest default `true`; any value other than `true`
   disables the hook). `${user_config.bash_format_lint_gitignored}` (unexpanded or empty means
   the manifest default `false`): unless it is `true`, the batch row silently skips an edit to a
   file the repository gitignores, so a user asking why `.work/scratch.sh` was not formatted
   gets this answer. `${user_config.bash_format_end_of_turn}` (unexpanded or empty means the
   shipped default `false`), as INFO: on, the Stop row runs the `lint` entry over the uncommitted
   changes once per turn; off, only the batch format and the git pre-commit entries run.
7. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
8. **Project scope.** INFO: when `CLAUDE_PROJECT_DIR` is set, the batch row acts only
   on shell files inside it (symlink-resolved membership guard in the shared hook
   library, aware of Windows 8.3 short-name spellings of in-project paths, a
   per-volume property; only volumes with 8.3 generation enabled produce them);
   a `.sh`/`.bash` file written *outside* the project (temp/scratchpad
   dirs) is silently skipped. No lint, no format, no notice. The OS temp tree
   counts as outside even when it sits under `CLAUDE_PROJECT_DIR`, unless the
   project root itself lives under temp. When
   `CLAUDE_PROJECT_DIR` is **unset** (e.g. some headless `-p` sessions) the guard
   is skipped and any existing edited file is processed. Report this so a green
   `check` is not read as "every shell edit anywhere is covered".
9. **Gitignored files.** INFO: unless `bash_format_lint_gitignored` is `true`, a file the
   repository gitignores (`git check-ignore`) is silently skipped: no lint, no format, no
   notice. A tracked file that matches an ignore pattern stays in scope, and when git cannot
   decide (git absent, no repository, an error) the hook acts as before
   (`hook::gitignored_out_of_scope` in `${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`). Report the item 6
   value beside this.
10. **Git pre-commit entries.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
    from the repository. It lists `format`, `lint` and `lint-full`. Each line is `<state>\t<entry>[\t<detail>]`:
    `ok` is PASS, `declined` is INFO (this clone said no; silent at session start), and `missing`,
    `stale`, `modified` or `superseded` is a FAIL whose remediation is `apply install-git-hooks`; a
    `superseded` detail lists what an install under an earlier plugin or entry name left (the single
    entry these two replaced), which that action removes on the user's yes. A
    `tool\t<tool>\tmissing` line means the installed entry cannot run here: list every such tool (the
    entry's resolved tool) with its install method from the
    `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), so a lane or cloud setup script can
    provision it before an auto-mode session commits. Outside a git repository, report INFO and skip
    the step.

When every probe passes, report the result **with the scope caveats** (items 8 and 9).
Never an unqualified "fully operational", which would imply out-of-project shell
edits are covered when they are deliberately skipped.

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
   (this clone only, nothing committed) or `shared` (committed under `.githooks/bash-format/`,
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
   team would not receive the files.
5. **Decisions.** Read [reference/git-hook-decisions.md](reference/git-hook-decisions.md) for
   what each kind asks of you, apply each one, then rerun `plan` until only the decisions you
   chose to leave remain.
6. **Verify.** Run `verify` and report its lines as `check` step 10 does.

The `format` entry rewrites: at commit it formats the staged shell scripts the shfmt adapter
governs and stages the result, so tell the user that a commit can change the files it contains,
and that a partly staged governed script is refused untouched. The `lint` entry only reports
findings on the lines the commit adds, and `lint-full` only on the lines a push adds to a script over
2,000 lines. A decline of the earlier single entry carries to both.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry format` (or `lint`); the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains to the user each scope and why a formatter's cleanup PR comes first.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Apart from the git-hook entries above, this
skill installs nothing:

- a resolved adapter's tool missing: the install hints for that tool in
  `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path); this skill never installs system
  packages.
- missing `node` / `jq` / Bash: platform install instructions from the README Requirements section.
- a concern unresolved and wanted: say what opts the shipped adapter in
  (`${CLAUDE_PLUGIN_ROOT}/git-hooks/adapters.sh`), with the install hints for its tool from
  `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` when the tool is missing too. For format, an
  `.editorconfig` section naming shell files (`[*.sh]`, `[*.bash]`, or `[*.{sh,bash}]`, including
  path-prefixed forms like `[**/*.sh]`) opts the repo in; a bare `[*]` or a path-only section such as
  `[scripts/**]` does not. Lint has no opt-in: ShellCheck runs on every shell file, with the
  repository's `.shellcheckrc` when one exists and its own defaults otherwise. This skill writes
  neither file: both are the consumer's, and `.editorconfig` governs every editor and tool in the
  repo, so the choice and the edit belong to the consumer. For a tool the plugin ships no adapter for, `check` step 5's draft, for
  `/toolchain:setup apply bash`.
- toggle off, gitignored files wanted, or the end-of-turn check wanted: set
  `bash_format_enabled`, `bash_format_lint_gitignored` or `bash_format_end_of_turn` to `true`
  through Claude Code's native flow, interactively with
  `/plugin configure bash-format@<marketplace>` or by a headless route, as the marketplace's
  plugin-reconfiguration convention gives them in
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

After pointing at a remediation, re-run the relevant `check` probe live via Bash (a pre-computed row
predates the remediation, so never re-read it) and report its actual result. Never claim resolved on
the reader's report that they installed something.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Next

/toolchain:setup apply bash, with the drafted `fix-cmd` and `lint-cmd`, when the repository wants a
tool the plugin ships no adapter for; /toolchain:lint then runs it on request.

## What this skill does not do

- Run the linter or formatter. Editing any `.sh` or `.bash` file exercises the batch row end to
  end; `git commit` exercises the installed pre-commit entries.
- Write the bash record: `/toolchain:setup apply bash` does.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the repository,
  beyond the git-hook entry copies, including `.editorconfig` / `.shellcheckrc`. Every
  prerequisite is a `PATH` binary or the native toggle, so remediation is guidance only.
- Download or execute tools during `check` beyond the read-only `command -v` presence probes.

## Gotchas

- **`ENAMETOOLONG` when grepping the plugin cache.** Installed plugins run from a
  deeply nested, cache-isolated path. Piping a `grep`/`rg` over the long absolute
  path to `hooks/hook-utils.sh` (or another bundled file) can spawn-fail with
  `ENAMETOOLONG` on some hosts. Read the file directly rather than passing the full
  cache path on the command line.
- **`check` PASS ≠ every shell edit is covered.** When `CLAUDE_PROJECT_DIR` is set
  the hook is project-scoped (probe 8): shell files written outside it are silently
  skipped, so a fully green `check` still does not cover out-of-project edits. (When
  `CLAUDE_PROJECT_DIR` is unset the scoping does not apply. See probe 8.)
- **A missing tool is FAIL only for a resolved concern.** A missing `shfmt` or
  `shellcheck` is a FAIL only when step 4 resolves that concern to its adapter; for an
  unresolved concern it is INFO, not a defect. Read the `--resolve` rows before calling a
  missing tool a failure.
