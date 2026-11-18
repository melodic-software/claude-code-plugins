---
description: "Verify javascript-format's prerequisites and which formatter and linter its hooks run here, and register its git pre-commit entries. Use when: 'set up javascript-format', 'configure javascript-format', 'is javascript-format working', 'which formatter does javascript-format run', formatting silently isn't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | check inspect (read-only) | apply [install-biome] | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply] [inspect|install-biome|install-git-hooks [scope=local|shared]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
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
reports, `apply` resolves. JavaScript, TypeScript and JSON formatting and linting are two concerns.
The hooks run only the plugin's shipped adapter, where that tool's own config governs the file, and
otherwise nothing; they never run a command from the repository's typescript, javascript or json
record (`.claude/ecosystems/<id>.yaml`), which `/toolchain:lint` and `/toolchain:check` run on
request. The only consumer-project files this plugin writes are its git-hook entry copies
(`apply install-git-hooks`); a record is written by `/toolchain:setup apply <id>`, never here. The
tunables are the native `userConfig` options (the on/off toggle, the gitignored-file switch and the
end-of-turn check). `apply install-biome` is the one other write path: the adapter's tool, added
through the repository's own package manager as described below.

Action routing: no argument or `check` runs the check; `check inspect` runs only the
`check inspect` section; `apply` runs the check first, then
remediation; `apply install-biome` additionally authorizes the install its section describes. All
are non-interactive except where a section says to ask. Never prompt when the action is given.
`apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/javascript-format.sh`), the entries and the resolver
they share are the single source of truth for what the plugin requires and how it resolves
things; step 3 asks the resolver itself.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed `jq` row, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.
An installed plugin runs from a deeply nested cache path, and a search passed that path can fail
to start on some hosts because the path is too long, while reading a named file still works.

When the plugin's toggle is disabled, every prerequisite absence except Node.js downgrades
from FAIL to INFO. The hook script exits through its enabled-gate before probing anything, so
a deliberately disabled plugin is not broken. Node.js stays FAIL: `hooks.json` spawns `node`
before the script can read the toggle. Report the probes informationally and note that re-enabling
restores the FAIL semantics. A tool the git pre-commit entries need keeps the grade it gets with
the toggle on while an entry is installed (step 8 reports it as a `tool` line beside an `ok`,
`stale` or `modified` entry): the entries run at commit outside Claude Code and read no toggle.

1. **Bash version.** Check against the hooks' floor, Bash 3.2 or newer (`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`).
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: the batch hook then does nothing,
   since it reads the file paths with `jq`.
3. **What each concern resolves to.** From the repository root run
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/format.sh" --resolve` and
   `sh "${CLAUDE_PLUGIN_ROOT}/git-hooks/lint.sh" --resolve`. Each prints one row: plugin, concern,
   source, tool, found, detail, tab-separated. It reads the adapter's config and runs nothing.
   Append repository paths (`--resolve src/a.ts pkg/b.ts`) for one row per file when the answer can
   differ per file, as an adapter's config walk does; the detail column then names the config that
   governs that file and the binary that would run, or why nothing resolved. An adapter's own rules
   (which config opts a file in, where its binary comes from) are in
   `${CLAUDE_PLUGIN_ROOT}/git-hooks/adapters.sh`: read them to explain why a row names that config.
   Report one line per concern from the rows, never from this text:
   - `adapter:<name>` with found `yes`: PASS, naming the adapter's tool and that its config opted in.
   - found `no`: FAIL; the remediation is the adapter tool's
     `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` install hints (Read that path).
   - `none`: INFO "unresolved": no shipped adapter's config governs the repository, so the hooks run
     nothing. This is the opt-out by design.
   A detail saying a record exists is INFO beside the row: the hooks never run it, and
   `/toolchain:lint` or `/toolchain:check` runs it on request.

   The `SessionStart` probe resolves the adapter's tool separately, and only where its `when`
   config sits at or above the project directory or is tracked anywhere in its repository: read
   `when` and `local_bin` in `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` and `findLocalBin` in
   `${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs`, and compare them with the adapter's walk instead
   of assuming they match. An untracked config in a nested directory opts files in for the hooks,
   but the probe stays silent there.
4. **Draft, never write, the record.** When a concern is unresolved, or the person names a tool the
   plugin ships no adapter for, say that the hooks will not run that tool: they run only the shipped
   adapter. Find the repository's own formatter and linter by the steps in
   [reference/ecosystem-resolution.md](../../reference/ecosystem-resolution.md), and draft the
   `fix-cmd` and `lint-cmd` values: each holds `<files>`, `fix-cmd` only formats (import ordering
   included) and `lint-cmd` only reports, with findings as `<path>:<line>` lines. Hand the draft to
   `/toolchain:setup apply <id>` (the record's ecosystem id), the one writer of those keys, so
   `/toolchain:lint` and `/toolchain:check` can run them on request.
5. **Hook toggle and options.** Report the effective `javascript_format_enabled` value:
   `${user_config.javascript_format_enabled}` (unexpanded or empty means default `true`), and the
   effective `javascript_format_lint_gitignored` value:
   `${user_config.javascript_format_lint_gitignored}` (unexpanded or empty means default `false`).
   Also report `javascript_format_end_of_turn`: `${user_config.javascript_format_end_of_turn}`
   (unexpanded or empty means the shipped default `false`), as INFO: on, the Stop row lints the
   uncommitted changes once per turn; off, only the batch format and the git pre-commit entries run.
6. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
7. **Node.js.** Run `command -v node` via Bash. FAIL when absent: every hook launch goes
   through `node hooks/exec-bash.mjs`, so a missing `node` is a hook launch error, not a skip
   notice. Bash's `PATH` can differ from the one Claude Code resolves hook commands with (a
   shell initializer such as nvm may add Node only to Bash; see
   `docs/formatter-path-probes.md`), so a PASS means Node is on Bash's `PATH` only. Say
   so, and report INFO that hook availability is not established when the hooks still fail
   to start.
8. **Git pre-commit entries.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. It lists `format` and `lint`. Each line is `<state>\t<entry>[\t<detail>]`:
   `ok` is PASS, `declined` is INFO (this clone said no; silent at session start), and `missing`,
   `stale`, `modified` or `superseded` is a FAIL whose remediation is `apply install-git-hooks`; a
   `superseded` detail lists what an install under an earlier plugin or entry name left (the single
   entry these two replaced), which that action removes on the user's yes. A `tool\t<tool>\tmissing`
   line means the installed entry cannot run here: list every such tool (the entry's resolved tool)
   with its install method from the `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), so
   a lane or cloud setup script can provision it before an auto-mode session commits. Outside a git
   repository, report INFO and skip the step.

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
   (this clone only, nothing committed) or `shared` (committed for the team,
   so every teammate and agent gets it). When nobody can answer, use `local`.
2. **Plan.** For `local`, run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" plan
   --scope local`. For `shared`, run `plan --scope remote` first: with lefthook, or no hook manager
   yet, the committed `lefthook.yml` gets one `remotes:` entry naming the marketplace's root
   `lefthook-remote.yml`, which fetches every plugin's hooks from its main branch, so nothing is
   copied and no refresh is ever committed. When it returns `remote-needs-lefthook` (husky or plain
   hooks) or `remote-source-dir`, run `plan --scope shared` instead, which commits copies under
   `.githooks/javascript-format/`. Read the JSON: `manager`, `actions[]`, `decisions[]`.
3. **Manager conflict.** A `manager-conflict` decision lists the evidence (two managers, or one
   this installer does not drive, such as the pre-commit framework). Show it and ask which manager
   should carry the entry; rerun `plan` with `--manager lefthook|husky|plain`. Without an answer,
   stop here and report.
4. **Actions.** A remote plan has none. When `actions[]` holds `copy` items, run
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

The `format` entry rewrites: at commit it formats the staged JavaScript, TypeScript and JSON files
and stages the result, so tell the user that a commit can change the files it contains, and that a
partly staged one is refused untouched. The `lint` entry only reports findings on the lines the
commit adds. A decline of the earlier single entry carries to both.

A remote entry stays in the committed `lefthook.yml`, so stop it in one clone by skipping its job,
`javascript-format-remote-<entry>`, in the clone's untracked `lefthook-local.yml`; a failing remote job prints
that skip, and the [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md#when-a-remote-job-breaks)
says when to use it and how to drop it.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry format` (or `lint`); the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains to the user each scope and why a formatter's cleanup PR comes first.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution. Never install anything without the
consumer's explicit go-ahead in the invocation. `apply install-biome` adds the Biome adapter's
tool as a dev dependency of the consumer repository **through the package manager the repository
already uses**, never globally, mirroring how the adapter resolves the binary.

Principles, in order. They decide every case, whatever the tool:

1. **Identify the repo's package manager from its own markers**: its lockfile, then the
   `package.json` field that names a manager when no lockfile exists, then the platform's default
   manager only when neither signal is present. Recognize the manager from what the repo declares,
   and look up its commands in its own documentation at run time; don't assume from a list.
2. **Record through the manager, never around it.** The tool goes in through that manager's own
   dev-dependency add command, so the manifest and lockfile record it. Never introduce a
   competing lockfile.
3. **Only where the adapter resolves.** The adapter resolves a `node_modules/.bin` the repository
   does not commit, walking up from the file, or `PATH`, nothing else
   (`${CLAUDE_PLUGIN_ROOT}/git-hooks/adapters.sh`). Ask the repo's own manager, by its own config
   command, whether its install mode yields that directory; never infer the mode from the files
   present. When it does not, skip the install and guide instead (put the tool on `PATH`, or change
   the install mode) rather than installing somewhere the adapter never looks.
4. **Ambiguity stops.** No `package.json`, more than one lockfile, or a lockfile that contradicts
   the declared manager: guidance only, anchored on the install hints in
   `${CLAUDE_PLUGIN_ROOT}/prerequisites.json`, matching the entries' missing-tool text. State the
   change and the target before running anything.

After any remediation, re-run the relevant `check` probe live via Bash (a pre-computed row
predates the remediation) and report its actual result.
Never claim resolved on the install command's exit code alone. For everything else `apply`
only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: set `javascript_format_enabled` to `true` through Claude Code's native flow,
  interactively with `/plugin configure javascript-format@<marketplace>` or by a headless route, as the
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
- a concern unresolved: `check` step 4's draft, for `/toolchain:setup apply <id>`. The plugin
  imposes no rules and no tool of its own; it offers to create a minimal config for the Biome
  adapter in the repository root only when the person explicitly asks for one.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Next

/toolchain:setup apply <id>, with the drafted `fix-cmd` and `lint-cmd`, when the repository wants a
tool the plugin ships no adapter for; /toolchain:lint then runs it on request.

## What this skill does not do

- Run the formatter or the linter. Editing any supported file exercises the batch hook;
  `git commit` exercises the installed pre-commit entries.
- Write a typescript, javascript or json record: `/toolchain:setup apply <id>` does.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install Biome globally or outside the package manager the repository already uses.
- Download or execute tools during `check`; network use happens only in an explicitly
  requested `apply install-biome` inside the consumer repository.
