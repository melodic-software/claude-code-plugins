---
description: "Verify spelling's prerequisites and configuration here, and register its git pre-commit entry. Use when: 'set up spelling', 'configure spelling', 'is spelling working', spelling findings never show up, or a hook reported a missing prerequisite or drifted git hook. Actions: check (read-only, default) | apply | apply install-git-hooks [scope=local|shared]. Re-runnable."
argument-hint: "[check|apply [install-git-hooks [scope=local|shared]]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v typos*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Pre-computed context

`check`'s tool probe ran at load time. Read this row instead of re-issuing it; it shows the
tool's path when present, or `absent` when missing:

- `typos`: !`command -v typos 2>/dev/null || echo absent`

A row reading `[shell command execution disabled by policy]` carries no result: run the
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
entry copies, which `apply install-git-hooks` writes. Rules come
from the repository's own typos config, and the only tunables are the native `userConfig`
options (the on/off toggle and the end-of-turn opt-in). Unlike sibling formatter plugins
(Ruff, markdownlint-cli2), typos has no per-repo dependency-manager install path. It is a
standalone Rust binary installed at the machine level (cargo, Homebrew, Conda, pacman, or
a pre-built binary), never as a project dependency. `apply` is therefore guidance-only: it
never installs anything, matching the check's own PATH-only resolution and the plugin
philosophy's never-download-silently rule.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
prints remediation guidance for each FAIL. Both are non-interactive. Never prompt when the
action is given. `apply install-git-hooks` is the one write path, and it asks only where its
section says to.

Step 1 of `check` only reports a Bash version because the skill cannot load where bash is missing:
with `shell: bash` on Windows without Git Bash the invocation fails before any command runs, so
this skill never gets to diagnose the missing Git Bash. The README Requirements section carries
that answer. Verification record. Claim: `shell: bash` without bash available fails the
invocation before any command runs, showing ``Skill <name> requires bash (`shell: bash` in
frontmatter) but Git Bash was not found``, and a failed injected command aborts the skill before
Claude sees its content. Basis: [How injected commands
run](https://code.claude.com/docs/en/skills#how-injected-commands-run) and [When an injected
command fails](https://code.claude.com/docs/en/skills#when-an-injected-command-fails). As of
2026-09-29. Recheck when a re-read of either section no longer describes that failure.

## `check` (read-only)

Spelling findings arrive at commit time, from the git pre-commit entry
(`${CLAUDE_PLUGIN_ROOT}/git-hooks/typos-check.sh`), and at turn end only when
`spelling_end_of_turn` is on. Nothing reports while Claude edits. Read that script and
`${CLAUDE_PLUGIN_ROOT}/hooks/spelling.sh` first: probe what they actually do, don't recite
this file. Then read the pre-computed tool row, run the remaining probes via Bash, and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

typos stays a FAIL even when `spelling_enabled` is off, because the installed git entry runs
without Claude Code. Node.js (step 5) is a FAIL either way too.

1. **Bash version.** Check against the README Requirements floor (3.2 or newer).
2. **typos binary.** The pre-computed `typos` row (PATH only, with no per-repo convention).
   Report the resolved path and `typos --version` output when found. FAIL when absent: an agent's
   commit then fails with the install command, and a person's commit passes with a notice.
3. **Consumer typos config (informational only).** typos resolves its own governing config from
   each checked path, and the check adds the bundled `${CLAUDE_PLUGIN_ROOT}/config/default-typos.toml` via `typos -c`
   (SHA `extend-ignore-re`); `extend-*` keys merge rather than replace. Report whether a
   `typos.toml`, `_typos.toml`, `.typos.toml`, a `Cargo.toml` with
   `[workspace.metadata.typos]`/`[package.metadata.typos]`, or a `pyproject.toml` with
   `[tool.typos]` governs the repo, as INFO. Do not offer to create a config; say the user can
   add one to tune the rules.
4. **Options.** Report the effective `spelling_enabled` value
   (`${user_config.spelling_enabled}`; unexpanded or empty means `true`) and
   `spelling_end_of_turn` (`${user_config.spelling_end_of_turn}`; unexpanded or empty means
   `false`, so findings wait for the commit). Report both as INFO.
5. **Node.js.** Run `node --version` via Bash. A `command -v node` hit is not enough: a
   version-manager shim or a shell function resolves there yet cannot run the launcher. FAIL when
   the command is absent or exits non-zero: the hook rows run `node hooks/exec-bash.mjs` and the
   installer is a node script. Node is a prerequisite separate from Claude Code. Pointer:
   [Install with npm](https://code.claude.com/docs/en/setup#install-with-npm).
6. **Git pre-commit entry.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined` is
   INFO (this clone said no; silent at session start), and `missing`, `stale`, `modified` or `superseded` is a
   FAIL whose remediation is `apply install-git-hooks`; a `superseded` detail lists what an install under an earlier plugin name left, which that action removes on the user's yes. A `tool\t<tool>\tmissing` line means the
   installed entry cannot run here: list every such tool with its install method from the
   `${CLAUDE_PLUGIN_ROOT}/prerequisites.json` (Read that path), so a lane or cloud setup script can provision it before an
   auto-mode session commits. Outside a git repository, report INFO and skip the step.

## `apply install-git-hooks [scope=local|shared]`

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager. The installer script only detects, renders and writes files the plugin owns; every step
that needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/spelling/`,
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
6. **Verify.** Run `verify` and report its lines as `check` step 6 does.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry typos-check`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses it.
Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains each install scope to the user.

## `apply` (idempotent)

Run `check`, then for each FAIL print remediation guidance. Never install anything. There is
no `apply install-typos` write path. This skill follows the refusal template in
[docs/plugin-philosophy.md](../../../../docs/plugin-philosophy.md) `### Install subactions and refusal`
and prints the consumer-run install method instead. Both reasons apply: (1) every install is
machine-level (cargo, Homebrew, Conda, pacman, or a pre-built binary), not a dependency recorded
through the repo's package manager; (2) typos publishes several official install methods
(`https://github.com/crate-ci/typos#install`), so choosing one is the consumer's call. Surface the
platform-appropriate method.

After the consumer installs `typos` themselves, re-run `check` with live Bash probes (the
pre-computed row predates the install) and report its actual result.
Never claim resolved without re-verifying. For everything else `apply` only points:

- missing Bash / Node.js: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: set `spelling_enabled` to `false` through Claude Code's native flow,
  interactively with `/plugin configure spelling@<marketplace>` or by a headless route, as the
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
- no typos config: offer to create a minimal `_typos.toml` in the repository root only when
  explicitly asked. The plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the spell-checker. `git commit` exercises the installed pre-commit entry.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install `typos`. Installation is always the consumer's own choice and command, at the
  machine level, never a project dependency this skill records.
- Download tools, or run any during `check` or `apply` beyond the read-only `typos --version` and
  `node --version` probes and the `install.mjs` commands named above.
