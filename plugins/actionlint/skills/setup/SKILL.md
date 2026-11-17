---
description: "Verify actionlint's prerequisites and whether its hooks lint workflows here, and register its git pre-commit entry. Use when: 'set up actionlint', 'configure actionlint', 'is actionlint working', workflow lint silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | check inspect (read-only) | apply [install-git-hooks [scope=local|shared]]. Re-runnable and safe."
argument-hint: "[check|apply] [inspect|install-git-hooks [scope=local|shared]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v node*)"
  - "Bash(command -v actionlint*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" inspect:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs inspect:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
  - "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh\" --resolve)"
  - "Bash(sh \"${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh\" --resolve:*)"
  - "Bash(sh ${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh --resolve)"
  - "Bash(sh ${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh --resolve:*)"
shell: bash
---

## Pre-computed context

`check`'s tool probes ran at load time. Read these rows instead of re-issuing them; each shows the
tool's path when present, or `absent` when missing:

- `node`: !`command -v node 2>/dev/null || echo absent`
- `actionlint`: !`command -v actionlint 2>/dev/null || echo absent`

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
reports, `apply` resolves. The plugin only lints. Its hooks run only the shipped actionlint adapter,
over the repository's workflow files, applying the repository's own actionlint config when there is
one; they never run a
command from the repository's github-actions record (`.claude/ecosystems/github-actions.yaml`),
which `/toolchain:lint` and `/toolchain:check` run on request. The only consumer-project files this
plugin writes are its git-hook entry copies (`apply install-git-hooks`); it never writes the
actionlint config or the record (`/toolchain:setup apply github-actions` writes the record). The
tunables are the native `userConfig` options (`actionlint_enabled` and `actionlint_end_of_turn`). Every prerequisite is a `PATH` binary the
plugin never bundles, and the plugin never installs system packages, so `apply` is
guidance-and-verify with that one write path. It never modifies user settings or the plugin
cache.

Action routing: no argument or `check` runs the check; `check inspect` runs only the
`check inspect` section; `apply` runs the check first, then
offers remediation guidance; `apply install-git-hooks` registers the git-hook entry. All are
non-interactive. Never prompt when the action is given. `apply install-git-hooks` asks only where
its section says to.

## `check` (read-only)

The lint entry (`${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh`), its adapter
(`${CLAUDE_PLUGIN_ROOT}/git-hooks/adapters.sh`) and the resolver they share are the single source of
truth for what the plugin requires and how it resolves things; step 4 asks the resolver itself.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed tool rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The Claude Code hooks exit through their enabled-gate before probing anything, so a
deliberately disabled plugin is not broken. Report those probes informationally and note that
re-enabling restores the FAIL semantics. A missing `node` stays FAIL: the launcher runs before the
enabled-gate. A tool the git pre-commit entry needs keeps the grade it gets with the toggle on while
that entry is installed (step 7 reports it as a `tool` line beside an `ok`, `stale` or `modified`
entry): the entry runs at commit outside Claude Code and reads no toggle.

1. **Bash version.** Check against the floor, Bash 3.2 or newer (README Requirements).
2. **`node`.** The pre-computed `node` row. FAIL if absent, even when the toggle is off: every
   hook row launches through `node hooks/exec-bash.mjs`, so the hooks do not launch and the
   session-start probe does not run. The hooks cannot report this themselves. Probed here
   through Bash, which works without the launcher.
3. **`actionlint`.** The pre-computed `actionlint` row. Where step 4 resolves the adapter, FAIL if
   absent: the pre-commit entry then fails the commit of an agent with the install command and
   gives a person a notice, and the end-of-turn check does nothing. Where step 4 resolves nothing,
   INFO: no hook would run it here.
4. **What lint resolves to.** From the repository root run
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh" --resolve`. It prints one row: plugin, concern,
   source, tool, found, detail, tab-separated. It reads the adapter's config and runs nothing.
   Which files the adapter governs and which config it applies are its rules in `adapters.sh`: read
   them to explain the row. Report from the row, never from this text:
   - `adapter:actionlint` with found `yes`: PASS, naming the config the detail reports (or that
     actionlint runs on its defaults); an absent config is not a fault.
   - found `no`: FAIL, as step 3.
   - `none`: INFO "unresolved": the repository has no workflow files, so the hooks have nothing
     to lint. This is not a fault. This skill never writes a workflow or an actionlint config.
   A detail saying a github-actions record exists is INFO beside the row: the hooks never run it,
   and `/toolchain:lint` or `/toolchain:check` runs it on request. When the person wants a linter
   the plugin ships no adapter for, say the hooks will not run it, and hand it to
   `/toolchain:setup apply github-actions`, the one writer of the record's `lint-cmd`.
5. **Hook toggles.** Report the effective `actionlint_enabled` value:
   `${user_config.actionlint_enabled}` (unexpanded or empty means default `true`; any value
   other than `true` disables the Claude Code hooks). Also report `actionlint_end_of_turn`:
   `${user_config.actionlint_end_of_turn}` (unexpanded or empty means the shipped default
   `false`), as INFO: on, the Stop row runs the lint entry over the uncommitted workflow changes
   once per turn; off, only the git pre-commit entry lints.
6. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
7. **Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. It lists `lint`. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale`, `modified` or `superseded` is a
   FAIL whose remediation is `apply install-git-hooks`; a `superseded` detail lists what an install under an earlier plugin or entry name left (the `actionlint-check` entry `lint` replaced), which that action removes on the user's yes. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool with its install method from the
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

**Run this section only when the user typed `/actionlint:setup apply install-git-hooks` as a
command; that typed command is the only go-ahead this flow takes, `plan` included.** The user's
answers to this section's own questions continue a run it started. On any other request,
including a plain-language "run the apply step" or "register the hook" and a hook notice, never
run `install.mjs` `plan`, `copy`, `decline` or `config-hook`, and reply that the user should type
`/actionlint:setup apply install-git-hooks` themselves.

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager. The installer script only detects, renders and writes files the plugin owns; every step
that needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/actionlint/`,
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
6. **Verify.** Run `verify` and report its lines as `check` step 7 does.

The entry only reports: at commit it lints the staged workflow files and blocks the commit on a
finding actionlint reports on a line the commit adds. It rewrites nothing.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry lint`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains each install scope to the user.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. This skill installs nothing:

- missing `actionlint`: the install method in `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read
  that path); the plugin neither bundles nor installs it.
- missing `node` / Bash: platform install instructions from the README Requirements section.
- toggle off: set `actionlint_enabled` to `true` through Claude Code's native flow,
  interactively with `/plugin configure actionlint@<marketplace>` or by a headless route, as the
  marketplace's plugin-reconfiguration convention gives them in
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

## Gotchas

- **A userConfig knob is reachable natively only if the manifest declares it.** An undeclared key
  silently cannot be set through native plugin configuration (a raw settings `env` block still
  works). Pointer: the `--config` row in
  [`plugin install`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).
- **What each headless route does to stored options is the convention's to state.** Read it in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes),
  which also holds the verified-version record: which CLI release each behavior was observed on,
  and under which conditions.
- **`-shellcheck=` / `-pyflakes=` are deliberate, and the deadlock claim is a local
  observation.** The entry disables actionlint's external run-block linters because each spawns a
  subprocess per `run:` block; the additional "ShellCheck deadlocks on large blocks under the
  Windows subprocess IPC path in actionlint 1.7.x" rationale is the author's own reproduction.
  No matching upstream rhysd/actionlint issue as of 2026-07-23; recheck when a rhysd/actionlint
  issue or release note reports ShellCheck hanging or deadlocking under the Windows subprocess
  path, which would replace the local reproduction with an upstream-confirmed cause and a fixed
  version to pin against. Deep run-block linting belongs in CI.

## What this skill does not do

- Run the linter. `git commit` exercises the installed pre-commit entry.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Write an actionlint config or a `.claude/ecosystems/` record.
- Install actionlint, node or Bash.
- Download or execute tools during `check` beyond the read-only `command -v` presence probes, the
  lint entry's `--resolve` row and the installer's read-only `verify`.
