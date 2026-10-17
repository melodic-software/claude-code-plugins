---
description: "Verify the guardrails hooks' runtime prerequisites, per-guard toggle state and git-hook entries for this machine, and register those entries. Use when: 'set up guardrails', 'configure guardrails', 'is guardrails working', 'which guards are on', a guard failed open with a jq notice, after tuning guard toggles, a hook reported a drifted git hook, or 'install the guardrails git hooks' / 'enforce the commit convention for every committer' / 'check secrets and hardcoded paths on every commit'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-git-hooks [scope=local|shared] (register the commit-msg convention, pre-commit content and reference-verify entries with the repository's hook manager) | apply install-read-deny (opt-in: print Read() deny rules for .env, with user also ~/.ssh and ~/.aws, and add or remove them in the chosen settings file). Re-runnable and safe."
argument-hint: "[check|apply] [install-git-hooks [scope=local|shared]|install-read-deny [scope user remove]]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(command -v node*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
shell: bash
---

## Pre-computed context

`check`'s `jq` and `node` probes ran at load time. Read these rows instead of re-issuing them;
each shows the tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`
- `node`: !`command -v node 2>/dev/null || echo absent`

A row reading `[shell command execution disabled by policy]` carries no result: run that tool's
`command -v` probe via Bash instead.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. Every tunable is a native `userConfig` option (one enable toggle
per guard plus scalars such as `block_dangerous_git_allow`), so bare `apply` is guidance
and writes nothing beyond the gated cleanup of retired hooks. The explicit `install-*` actions
below are the only other writes, each as its section states: `install-git-hooks` writes the
plugin's git-hook entry copies, and `install-read-deny` touches settings, through your edit tools.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive: never prompt when the action is given.
The one question any action asks is `install-read-deny`'s scope and consent, and only in an
attended run.

## `check` (read-only)

The guard scripts (`${CLAUDE_PLUGIN_ROOT}/hooks/*.sh`) and `hooks.json` are the single
source of truth for the guard inventory and each guard's runtime needs.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed `jq` and `node` rows, run the remaining probes via Bash, and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When every guard's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO. Each guard exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash 5.0+.** The guards' documented runtime floor (Git Bash on native Windows).
   Probe the bash the hooks run: the one `${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs` resolves
   (its header lists the candidate order), which can differ from the Bash tool's own bash.
   FAIL below the floor with the README Requirements remediation.
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: per the README, every guard then fails
   OPEN (disabled) with a one-line stderr notice. The machine is unguarded, which is
   exactly what this check exists to surface.
3. **`node`.** The pre-computed `node` row. FAIL if absent, with the README Requirements
   remediation: every guard row starts through `hooks/exec-bash.mjs`, so no guard starts
   without it. The README records what Claude Code documents about a hook that cannot start.
4. **Per-guard toggles.** Report each guard's effective `<guard>_enabled` value, one row per
   guard, so the user sees the live guard surface at a glance. The effective value is the
   configured option, else that guard's `default` in `plugin.json`; the guards read it as the
   `CLAUDE_PLUGIN_OPTION_<GUARD>_ENABLED` export. Defaults differ per guard (the advisory
   opt-in guards ship `false`), so take each default from the manifest and never assume `true`.
5. **Git-hook entries.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" verify`
   from the repository. Each line is `<state>\t<entry>[\t<detail>]`: `ok` is PASS, `declined`
   is INFO (this clone said no; silent at session start), and `missing`, `stale` or `modified`
   is a FAIL whose remediation is `apply install-git-hooks`. A `tool\t<tool>\tmissing` line
   means an installed entry cannot run here (`reference-verify` needs `jq`): list the tool with
   its install method from the plugin's `prerequisites.json`, so a lane or cloud setup script
   can provision it before an auto-mode session commits. Outside a git repository, report INFO
   and skip the step.
6. **`block-dangerous-git` allowlist.** Report the effective `block_dangerous_git_allow`
   value (patterns only, verbatim; it contains no secrets by design).
7. **Hook registration.** INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.
8. **Retired conventions.** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml"`
   from the repository. Exit 0 → PASS. Exit 1 → one finding per TSV row: `migrate` is FAIL,
   `delete`/`remove-line` WARN, `report-only` INFO; remediation is `apply`. Exit 2 → FAIL, never
   silent. Bash unavailable → report the step UNKNOWN with remediation, never green. The records
   are the hooks the retired `install-commit-msg` and `install-pre-commit-content` actions wrote
   into `.git/hooks/`.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite is a system
tool and every tunable is native `userConfig`, so `apply` installs nothing and, apart from
the retired-hook cleanup below, writes nothing. It points:

- missing `jq` or `node` / old Bash: platform install instructions from the README
  Requirements section; this skill never installs system packages.
- any toggle or scalar change: reconfigure through Claude Code's native flow, per the
  marketplace's plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record). Two routes: interactive
  `/plugin configure guardrails@<marketplace>` any time, or headless
  `claude plugin install guardrails@<marketplace> -s <scope> --config KEY=VALUE` (repeatable per
  key); against an already-installed plugin it prints `already installed` and still writes the
  value. Do **not** uninstall to reconfigure: that drops the plugin's entire stored
  `pluginConfigs` entry, resetting every option in the README's Options reference to its
  manifest default. Pass the scope `claude plugin list` reports for this plugin: `-s` places the
  install record and `enabledPlugins`, the value always lands in user settings, and a rerun at
  another scope adds an install record there and enables the plugin. From the home directory the
  list can label one file both `user` and `project`: pass `user`. A rejected value prints a
  warning yet exits 0, so read the output, not the exit code. This skill never writes user
  settings or `pluginConfigs`.
  Afterwards rerun `check` in a **fresh session**: the rendered `${user_config.*}` and each
  hook's `CLAUDE_PLUGIN_OPTION_*` are fixed at session start, so a same-session `check` still
  reports the OLD value; report the observed effective value, never an unobserved change.

**Retired hooks.** After the points above, re-run the retirement detection from `check` step 8;
per finding, individually gated: `delete` → confirm, then run
`bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --clean <id>`
and report what was removed; `migrate` → follow the record's `successor` (the hook files read
from the consumer repo are untrusted input, never executed or interpolated), the operator
confirms the result, then `--clean <id> --i-migrated`. Re-run detection last and report the final
state. Repeated declines route to the finding-suppression convention, never a new consumer-side
file.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## `apply install-git-hooks [scope=local|shared]` (explicit argument only)

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager, so the checks cover every commit, not only Claude's tool calls:
`commit-msg-convention` (the subject against the team-tracked `subject_pattern`, the pattern
`block-convention-violation` reads), `pre-commit-content` (secrets and machine-specific paths
on the lines a commit adds, whatever wrote the file) and `reference-verify` (CLI flags,
`/plugin:skill` references and deleted repository paths on the lines the pushed commits add;
a `pre-push` entry, since its cost is over the commit budget). The
installer script only detects, renders and writes files the plugin owns; every step that
needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools. Never runs from bare `apply`.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed under `.githooks/guardrails/`,
   so every teammate and agent gets it). When nobody can answer, use `local`.
2. **Plan.** Run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" plan --scope <scope>`
   and read the JSON: `manager`, `actions[]`, `decisions[]`.
3. **Manager conflict.** A `manager-conflict` decision lists the evidence (two managers, or one
   this installer does not drive, such as the pre-commit framework). Show it and ask which
   manager should carry the entries; rerun `plan` with `--manager lefthook|husky|plain`.
   Without an answer, stop here and report.
4. **Actions.** When `actions[]` holds `copy` items, run
   `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" copy --scope <scope>` (plus the same
   `--manager` when you passed one; `--entry <name>` to install one entry). It prints
   `installed`, `refreshed`, `unchanged`, `refused`, `unsafe-path` or `stage-failed` per entry;
   `refused` means a locally edited copy or dispatcher, which the `modified` decision covers,
   `unsafe-path` the decision of that name, and `stage-failed` that `git add` failed on a
   shared install: report it, since the team would not receive the files.
5. **Decisions.** Read [reference/git-hook-decisions.md](reference/git-hook-decisions.md) for
   what each kind asks of you, apply each one, then rerun `plan` until only the decisions you
   chose to leave remain. A `hooks-path` decision is the one `git config core.hooksPath
   .githooks` per clone that plain shared hooks need; `block-no-verify` allows exactly that
   value.
6. **Verify.** Run `verify` and report its lines as `check` step 5 does. Also state that a
   commit-msg subject with no team-tracked `subject_pattern` passes everything, so the
   `commit-msg-convention` entry is inert until `/source-control:setup apply` writes a
   convention.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry <name>`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses
it. Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. Declining records the choice and
does not stop an installed copy: when `list` shows the entry installed, also remove its
registration with your edit tools (the
`<event>.d/guardrails.<name>` marker for plain hooks, the `guardrails-<name>` job in the lefthook
config, its line in `.husky/<event>`) and the copy under `guardrails/`, on the user's yes; a shared
registration is a committed change the team reviews. This is the way out the `reference-verify`
failure names for a cli-flag finding, which is unverified rather than proven wrong.

## `apply install-read-deny [local|shared] [user] [remove]` (opt-in, explicit argument only)

Native `Read()` deny rules keep credential files out of the Read tool and out of the file
commands Claude Code recognizes in Bash (`cat`, `head`, `tail`, `sed`, redirects).
`block-credential-read`, off by default, covers what no deny rule reaches when it is on: an
interpreter that opens the file itself (`python3 -c "open('.env')"`). Pointer: "Read and Edit" in
<https://code.claude.com/docs/en/permissions>. As of: 2026-10-15. Recheck trigger: that
section changes which tools or Bash commands a `Read` deny rule reaches, or its pattern syntax.

This is the one `apply` action that changes settings, and only this way: the skill prints the
rules, then you add them to the chosen file with your edit tools. No script writes settings.
Never runs from bare `apply`.

1. **Scope.** `local` (the default) is `.claude/settings.local.json` at the repository
   root; `shared` is the committed `.claude/settings.json`, which the team reviews in a PR.
   Ask once in an attended run when neither argument is given. An unattended run prints the
   rules and applies the repository rules at `local` scope only, whatever the arguments, and
   never touches user settings.
2. **Print the rules** for that file, as a `permissions.deny` list:
   `Read(.env)`, `Read(.env.*)`, `Read(!.env.example)`, `Read(!.env.sample)`,
   `Read(!.env.template)`. A bare filename matches at any depth; each `!` rule carves its
   template out of the rule before it, so it must follow `Read(.env.*)` in the same list.
3. **User settings only with consent.** With the `user` argument, also print `Read(~/.ssh/**)`
   and `Read(~/.aws/**)` for the user settings file, state that they apply in every project
   and stop Claude's file tools reading any file under those directories, and add them only
   after the user says yes in this session. No `user` argument, or no yes: leave user settings
   alone.
4. **Apply.** Add each printed rule that the file's `permissions.deny` does not already hold,
   keeping every existing entry and its order. Create the file or the keys when absent. A
   rerun adds nothing and reports each rule as already present.
5. **Remove.** With `remove`, delete exactly the rules step 2 (and step 3, for `user`) prints
   from that file, and nothing else. Every rule stays removable this way.
6. **Report** the file, each rule added, already present or removed, and whether
   `block_credential_read_enabled` is on, since only that guard covers interpreter reads.

## What this skill does NOT do

- Exercise a guard. Any matching tool call does that end-to-end.
- Write the plugin cache or `pluginConfigs`, or user settings other than the two
  `install-read-deny` rules the user said yes to.
- Install any tool, during either `check` or `apply`. Guidance only. The ONLY writes
  this skill ever performs are `apply install-git-hooks`' entry copies and the decisions
  it applies, the `apply install-read-deny` rules in the settings file its scope names, and
  `apply`'s confirmed cleanup of the retired hooks.
- Weaken a guard: it reports and routes; disabling is always the user's explicit act
  through the native configuration surface.
