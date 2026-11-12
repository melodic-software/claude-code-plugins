---
description: "Verify biome-format's prerequisites and configuration here, and register its git pre-commit entry. Use when: 'set up biome-format', 'configure biome-format', 'is biome-format working', formatting silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | apply [install-biome] | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply [install-biome|install-git-hooks [scope=local|shared]]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Pre-computed context

`check`'s `jq` probe ran at load time. Read this row instead of re-issuing it; it shows
the tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`

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
reports, `apply` resolves. The only consumer-project files this plugin owns are its git-hook
entry copies, which `apply install-git-hooks` writes. Rules come from the repository's own
Biome config, and the tunables are the native `userConfig` options (the on/off toggle, the
gitignored-file switch and the end-of-turn check). `apply` is otherwise guidance-and-verify,
with one more write path: the explicitly invoked `apply install-biome` dependency install
described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation; `apply install-biome` additionally authorizes the consumer-repo dependency
install described below. All are non-interactive. Never prompt when the action is given.
`apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/biome-format.sh`) is the single source of
truth for what it requires and how it resolves things.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed `jq` row, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except Node.js (probe 7)
downgrades from FAIL to INFO. The hook exits through its enabled-gate before probing
anything, so a deliberately disabled plugin is not broken. Report those probes
informationally and note that re-enabling restores the FAIL semantics. Node.js stays FAIL
when disabled: the runner must start `node` before `exec-bash.mjs` can evaluate the gate. A tool
the git pre-commit entry needs keeps the grade it gets with the toggle on while that entry is
installed (step 8 reports it as a `tool` line beside an `ok`, `stale` or `modified` entry): the
entry runs at commit outside Claude Code and reads no toggle.

1. **Bash version.** Check against the hooks' floor, Bash 3.2 or newer (`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`).
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: the batch hook then does nothing,
   since it reads the file paths with `jq`.
3. **Biome binary.** Resolve it exactly the way the hook's resolution code does: its
   repo-local install walk (the `node_modules/.bin` path it tests, walking up from the
   edited file toward the repo root) and then `PATH`. Test only what the hook tests. A
   binary the hook would not accept must not PASS here. FAIL when nothing the hook would
   resolve is present while a Biome config governs the repo; the hook then skips the file.
   The `SessionStart` probe resolves biome separately: read
   `local_bin` in `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` and `findLocalBin` in
   `${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs` for its walk limit and file tests
   and compare them with the hook's, instead of assuming they match. The probe does not check
   for a Biome config, so it reports a missing biome in repositories with no `biome.json` too;
   it is the probe that reports the gap. A PASS here means the hook resolves it.
4. **Consumer Biome config.** Mirror the hook's opt-in walk: it records the topmost
   governing config found walking from the edited file's directory up to the repo root, and
   deliberately accepts only the config names the hook treats as the opt-in. Read the hook:
   the hidden dotted variants are intentionally excluded. Report the governing config the
   walk discovers, or INFO that none exists. Absence is the opt-out by design, so the
   plugin is inert (INFO, not FAIL), matching the README's "ships no rules of its own"
   stance. Do not offer to create a config; say the user can add a `biome.json` or
   `biome.jsonc` to opt in.
5. **Hook toggle and options.** Report the effective `biome_format_enabled` value:
   `${user_config.biome_format_enabled}` (unexpanded or empty means default `true`), and the
   effective `biome_format_lint_gitignored` value:
   `${user_config.biome_format_lint_gitignored}` (unexpanded or empty means default `false`).
   Also report `biome_format_end_of_turn`: `${user_config.biome_format_end_of_turn}` (unexpanded
   or empty means the shipped default `false`), as INFO: on, the Stop row checks the uncommitted
   changes once per turn; off, only the batch rewrite and the git pre-commit entry run.
6. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
7. **Node.js.** Run `command -v node` via Bash. FAIL when absent: every hook launch goes
   through `node hooks/exec-bash.mjs`, so a missing `node` is a hook launch error, not a skip
   notice. Bash's `PATH` can differ from the one Claude Code resolves hook commands with (a
   shell initializer such as nvm may add Node only to Bash; see
   `docs/formatter-path-probes.md`), so a PASS means Node is on Bash's `PATH` only. Say
   so, and report INFO that hook availability is not established when the hooks still fail
   to start.
8. **Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale`, `modified` or `superseded` is a
   FAIL whose remediation is `apply install-git-hooks`; for `superseded` (a copy installed under an earlier plugin name), first remove what its detail names. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool with its install method from the
   `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), so a lane or cloud setup script can provision it before an
   auto-mode session commits. Outside a git repository, report INFO and skip the step.

## `apply install-git-hooks [scope=local|shared]`

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager. The installer script only detects, renders and writes files the plugin owns; every step
that needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/biome-format/`,
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
6. **Verify.** Run `verify` and report its lines as `check` step 8 does.

The entry rewrites: at commit it formats the staged JavaScript, TypeScript and JSON files and
stages the result, so tell the user that a commit can change the files it contains, and that a
partly staged one is refused untouched.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry biome-check`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains to the user each scope and why a formatter's cleanup PR comes first.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution. Never install anything without the
consumer's explicit go-ahead in the invocation. `apply install-biome` adds
`@biomejs/biome` as a dev dependency in the consumer repository **using the repository's
own package manager**, resolved in order: lockfile (`pnpm-lock.yaml` → `pnpm add -D`,
`yarn.lock` → `yarn add -D`, `bun.lock`/`bun.lockb` → `bun add -d`, `package-lock.json` →
`npm install --save-dev`), then the `package.json` `"packageManager"` field when no
lockfile exists, then npm only when neither signal is present. With no `package.json`, an
ambiguous multi-lockfile state, or a lockfile that contradicts `packageManager`, stop with
manager-specific guidance instead of guessing. Never introduce a competing lockfile. The
change is stated before running. For a Yarn repository, don't infer the linker. Ask the
repo's own Yarn: run `yarn config get nodeLinker` in the repo. `pnp` → skip the install and
give guidance, because Plug'n'Play generates a loader file, not the `node_modules/.bin` shim
the hook resolves; install `@biomejs/biome` on `PATH` or switch the linker.
`node-modules`/`pnpm`, or Yarn Classic → install. Pointer for the linker values and their
default: [`nodeLinker`](https://yarnpkg.com/configuration/yarnrc#nodeLinker). As of: 2026-11-10.
Recheck trigger: that setting gains a value that also yields no `node_modules/.bin` shim. The
verify-after-remediation rule below is
the backstop when an install still yields no usable shim. After ANY remediation, re-run the
relevant `check` probe live via Bash (a pre-computed row predates the remediation) and report
its actual result. Never claim resolved on the install
command's exit code alone. For everything else `apply` only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: set `biome_format_enabled` to `true` through Claude Code's native flow,
  interactively with `/plugin configure biome-format@<marketplace>` or by a headless route, as the
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
- no Biome config: offer to create a minimal `biome.json` in the repository root only when
  explicitly asked. The plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter. Editing any supported file exercises the hook end-to-end; `git commit`
  exercises the installed pre-commit entry.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Download or execute tools during `check`; network use happens only in an explicitly
  requested `apply install-biome` inside the consumer repository.
