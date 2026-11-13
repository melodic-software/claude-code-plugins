---
description: "Verify go-format's prerequisites and configuration here, and register its git pre-commit entry. Use when: 'set up go-format', 'configure go-format', 'is go-format working', Go import/formatting fixes silently aren't happening, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | apply | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply [install-git-hooks [scope=local|shared]]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(command -v node*)"
  - "Bash(command -v goimports*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Pre-computed context

`check`'s tool probes ran at load time. Read these rows instead of re-issuing them; each shows the
tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`
- `node`: !`command -v node 2>/dev/null || echo absent`
- `goimports`: !`command -v goimports 2>/dev/null || echo absent`

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
entry copies, which `apply install-git-hooks` writes. It has no consumer-config opt-in gate
(unlike sibling formatter plugins Ruff/typos), so the tunables are the native `userConfig`
options: `go_format_enabled`, `go_format_lint_gitignored` and `go_format_end_of_turn`. Like
`spelling`, `goimports` has no per-repo dependency-manager install path in the way Ruff's
`.venv` does. It is conventionally `go install`ed to the machine-global `$GOPATH/bin`, never as
a project dependency. `apply` is therefore guidance-only for tools: it never installs anything,
matching the hook's own PATH-only resolution and the plugin philosophy's never-download-silently
rule.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
prints remediation guidance for each FAIL. Both are non-interactive. Never prompt when the
action is given. `apply install-git-hooks` asks only where its section says to.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/go-format.sh`) is the single source of truth for
what it requires and how it resolves things.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed tool rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO
table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except `node` downgrades from
FAIL to INFO. The hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report those probes informationally and note that re-enabling
restores the FAIL semantics. A missing `node` stays FAIL in either state: Claude Code launches
`node` before the launcher can read the toggle, so both hook rows fail to start. A tool the git
pre-commit entry needs keeps the grade it gets with the toggle on while that entry is installed
(step 9 reports it as a `tool` line beside an `ok`, `stale` or `modified` entry): the entry runs at
commit outside Claude Code and reads no toggle.

1. **Bash version.** Check against the hooks' floor, Bash 3.2 or newer (`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`).
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: the batch hook then does nothing,
   since it reads the file paths with `jq`.
3. **`node`.** The pre-computed `node` row. FAIL if absent: every hook row launches through
   `node hooks/exec-bash.mjs`, so without node the hooks do not start and nothing is enforced.
   The row reflects Bash's PATH, while Claude Code resolves the hook's `node` from its own
   environment (`docs/formatter-path-probes.md`), so a PASS here does not establish that hooks
   launch. If hooks fail to start despite a PASS, report hook availability as unestablished.
4. **`goimports` binary.** The pre-computed `goimports` row (the hook resolves PATH only, no
   `.venv`-style per-repo convention). Report the resolved path and `goimports -h`'s first line
   when found (goimports has no `--version` flag; the help header is the closest signal). FAIL
   when absent. The hook then skips the files, and the `SessionStart` probe reports the absence
   in every repository where the plugin is enabled, with or without `.go` files.
5. **Hook toggle.** Report the effective `go_format_enabled` value:
   `${user_config.go_format_enabled}` (unexpanded or empty means default `true`).
6. **Gitignored files.** Report the effective `go_format_lint_gitignored` value:
   `${user_config.go_format_lint_gitignored}` (unexpanded or empty means default `false`). At
   `false` the hook skips files the repository gitignores; a tracked file matching an ignore
   pattern stays in scope.
7. **End-of-turn check.** Report the effective `go_format_end_of_turn` value:
   `${user_config.go_format_end_of_turn}` (unexpanded or empty means the shipped default `false`),
   as INFO: on, the Stop row parses the uncommitted Go files once per turn; off, only the batch
   rewrite and the git pre-commit entry run.
8. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
9. **Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale`, `modified` or `superseded` is a
   FAIL whose remediation is `apply install-git-hooks`; a `superseded` detail lists what an install under an earlier plugin name left, which that action removes on the user's yes. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool with its install method from the
   `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), so a lane or cloud setup script can provision it before an
   auto-mode session commits. Outside a git repository, report INFO and skip the step.

There is no consumer-config probe (unlike `spelling`'s config-walk check). This hook has
no consumer-config gate by design; report that plainly as INFO, not as a gap.

## `apply install-git-hooks [scope=local|shared]`

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager. The installer script only detects, renders and writes files the plugin owns; every step
that needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/go-format/`,
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
6. **Verify.** Run `verify` and report its lines as `check` step 9 does.

The entry rewrites: at commit it runs goimports over the staged Go files and stages the result,
so tell the user that a commit can change the files it contains, and that a partly staged Go file
is refused untouched. It fails a commit only for a file goimports cannot parse.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry goimports-format`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains to the user each scope and why a formatter's cleanup PR comes first.

## `apply` (idempotent)

Run `check`, then for each FAIL print remediation guidance. Never install anything. There is
no `apply install-goimports` write path. This skill follows the refusal template in
[docs/plugin-philosophy.md](../../../../docs/plugin-philosophy.md) `### Install subactions and refusal`
and prints the consumer-run command instead. Reason 1 applies: the hook resolves `goimports` on `PATH` only, so the install it can use,
`go install golang.org/x/tools/cmd/goimports@latest`, writes to the machine-global `$GOPATH/bin`;
a `go.mod` tool line is not one the hook finds.

After the consumer installs `goimports` themselves, re-run `check` with live Bash probes (the
pre-computed rows predate the install) and report its actual result. Never claim resolved without
re-verifying. For everything else `apply` only points:

- missing `goimports`: `go install golang.org/x/tools/cmd/goimports@latest` (requires a Go
  toolchain: https://go.dev/dl/).
- missing `node` / `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: set `go_format_enabled` to `false` (and `go_format_lint_gitignored` the same way)
  through Claude Code's native flow, interactively with `/plugin configure go-format@<marketplace>`
  or by a headless route, as the marketplace's plugin-reconfiguration convention gives them in
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

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter. Editing any `.go` file exercises the hook end-to-end; `git commit`
  exercises the installed pre-commit entry.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `goimports`. Installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download tools, or run any during `check` or `apply` beyond the read-only `goimports -h` probe
  and the `install.mjs` commands named above.
