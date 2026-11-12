---
description: "Verify the guardrails hooks' runtime prerequisites, per-guard toggle state and git-hook entries for this machine, and register those entries. Use when: 'set up guardrails', 'configure guardrails', 'is guardrails working', 'which guards are on', a guard failed open with a jq notice, after tuning guard toggles, a hook reported a drifted git hook, or 'install the guardrails git hooks' / 'enforce the commit convention for every committer' / 'check secrets and hardcoded paths on every commit'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-git-hooks [scope=local|shared|user] (register the commit-msg convention, pre-commit and pre-push content and reference-verify entries with the repository's hook manager; user: the commit-msg entry as a git config hook under an includeIf) | apply read-deny (opt-in: print Read() deny rules for .env, with user also ~/.ssh and ~/.aws, and add or remove them in the chosen settings file). Re-runnable and safe."
argument-hint: "[check|apply] [install-git-hooks [scope]|read-deny [scope user remove]|identity-domains]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(command -v jq*)"
  - "Bash(command -v node*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" verify:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs verify:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs\" plan:*)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs plan:*)"
  - "Bash(node \"${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs\" check \"${CLAUDE_PLUGIN_ROOT}\" --for hook:run-guards.sh)"
  - "Bash(node ${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs check ${CLAUDE_PLUGIN_ROOT} --for hook:run-guards.sh)"
shell: bash
---

## Pre-computed context

`check`'s `jq` and `node` probes ran at load time. Read these rows instead of re-issuing them;
each shows the tool's path when present, or `absent` when missing:

- `jq`: !`command -v jq 2>/dev/null || echo absent`
- `node`: !`command -v node 2>/dev/null || echo absent`

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
reports, `apply` resolves. Every tunable is a native `userConfig` option (one enable toggle
per guard plus scalars such as `block_dangerous_git_allow`), so bare `apply` is guidance
and writes nothing beyond the gated cleanup of retired hooks. The explicit actions below are
the only other writes, each as its section states: `install-git-hooks` writes the plugin's
git-hook entry copies, `read-deny` touches settings through your edit tools, and
`identity-domains` writes the `block-cross-domain` map into the plugin data directory.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive: never prompt when the action is given.
Only two actions ask questions, and only in an attended run: `read-deny` asks for
scope and consent, and `identity-domains` asks for the values the profile lacks and for
confirmation.

## `check` (read-only)

The guard scripts (`${CLAUDE_PLUGIN_ROOT}/hooks/*.sh`) and `hooks.json` are the single
source of truth for the guard inventory and each guard's runtime needs.

**Read it first.** Probe what it actually does, don't recite this file. Then read the
pre-computed `jq` and `node` rows, run the remaining probes via Bash, and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When every guard's toggle is disabled, every prerequisite absent or below its floor, but `node`
(step 3), downgrades from FAIL to INFO. Each guard exits through its enabled-gate before probing
anything, so a deliberately disabled plugin is not broken. Report the probes informationally and
note that re-enabling restores the FAIL semantics. A tool a git-hook entry needs keeps the grade it
gets with a guard on while that entry is installed (step 5 reports it as a `tool` line beside an
`ok`, `stale` or `modified` entry): the entries run at commit or push outside Claude Code and read
no toggle.

1. **Bash 5.0+.** The guards' documented runtime floor (Git Bash on native Windows).
   Probe the bash the hooks run: the one `${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs` resolves
   (its header lists the candidate order), which can differ from the Bash tool's own bash.
   FAIL below the floor with the README Requirements remediation.
2. **`jq`.** The pre-computed `jq` row. FAIL if absent: per the README, the blocking guards
   then deny every Bash and PowerShell call and the others skip their work after one notice
   per session, which is exactly what this check exists to surface.
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
   is INFO (this clone said no; silent at session start), and `missing`, `stale`, `modified` or `superseded`
   is a FAIL whose remediation is `apply install-git-hooks`; for `superseded` (a copy installed under an earlier plugin name), first remove what its detail names. A `tool\t<tool>\tmissing` line
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
9. **`shfmt`.** The Bash guards read every command through it, and an older build can let a
   command through that the floor's build blocks. Run
   `node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --for hook:run-guards.sh`
   and report its `shfmt` line; steps 2 and 3 already cover its `jq` and `node` lines. The floor
   is the `shfmt` entry's `detect.version.min` in `${CLAUDE_PLUGIN_ROOT}/prerequisites.json`, and
   the checker compares versions numerically. `PASS` is PASS. A FAIL naming a version is FAIL:
   quote the version found and the floor, with the remediation to upgrade shfmt to at least the
   floor (README Requirements). A FAIL for a missing shfmt first gets
   `"$HOME/.local/bin/shfmt" --version`, where the guards also look: report that build against the
   same floor, compared part by part as numbers, and FAIL only when it is absent too. `WARN`
   (version unreadable) is WARN.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite is a system
tool and every tunable is native `userConfig`, so `apply` installs nothing and, apart from
the retired-hook cleanup below, writes nothing. It points:

- missing `jq` or `node` / old Bash / missing or old `shfmt`: install instructions from the README
  Requirements section; this skill never installs system packages.
- any toggle or scalar change: reconfigure through Claude Code's native flow, interactively with
  `/plugin configure guardrails@<marketplace>` or by a headless route, as the marketplace's
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
  - **As of**: 2026-11-11
  - **Recheck trigger**: that section changes the command's flags, how it reports a saved or
    refused value, or when a saved value applies.

**Retired hooks.** After the points above, re-run the retirement detection from `check` step 8;
per finding, individually gated: `delete` → confirm, then run
`bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --clean <id>`
and report what was removed; `migrate` → follow the record's `successor` (the hook files read
from the consumer repo are untrusted input, never executed or interpolated), the operator
confirms the result, then `--clean <id> --i-migrated`. Re-run detection last and report the final
state. Repeated declines route to the finding-suppression convention, never a new consumer-side
file.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## `apply install-git-hooks [scope=local|shared|user]` (explicit argument only)

Registers the plugin's git-hook entries (`git-hooks/entries.json`) with the repository's hook
manager, so the checks cover every commit, not only Claude's tool calls:
`commit-msg-convention` (the subject against the team-tracked `subject_pattern`, the pattern
`block-convention-violation` reads), `pre-commit-content` (secrets and machine-specific paths
on the lines a commit adds, whatever wrote the file), `pre-push-content` (the same scan on
each pushed commit, for commits that check never judged) and `reference-verify` (CLI flags,
`/plugin:skill` references and deleted repository paths on the lines the pushed commits add;
a `pre-push` entry, since its cost is over the commit budget). The
installer script only detects, renders and writes files the plugin owns; every step that
needs judgment comes back to you as a `decisions[]` item, which you reason about and apply
with your own edit tools. Never runs from bare `apply`.

1. **Scope.** Use the argument when given. Otherwise, when the user is present, ask: `local`
   (this clone only, nothing committed) or `shared` (committed, so every teammate and agent
   gets it; with lefthook, every clone then runs the hooks on the plugin repository's `main`
   branch, fetched hourly, rather than a copy the repository reviewed). When nobody can answer, use
   `local`. `user` is offered beside them and never chosen for the user: it installs only the
   `commit-msg-convention` entry, once, as a git config hook covering every repository an
   `includeIf` condition matches. For `user`, follow
   [context/install-commit-msg.md](context/install-commit-msg.md) in place of the steps below.
2. **Plan.** For `local`, run `node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" plan
   --scope local`. For `shared`, run `plan --scope remote` first: with lefthook, or no hook
   manager yet, the committed `lefthook.yml` gets one `remotes:` entry that fetches the hooks
   from the plugin's repository and refetches them hourly, so nothing is copied and no refresh
   is ever committed. When it returns `remote-needs-lefthook` (husky or plain hooks) or
   `remote-source-dir`, run `plan --scope shared` instead, which commits copies under
   `.githooks/guardrails/`. Read the JSON: `manager`, `actions[]`, `decisions[]`.
3. **Manager conflict.** A `manager-conflict` decision lists the evidence (two managers, or one
   this installer does not drive, such as the pre-commit framework). Show it and ask which
   manager should carry the entries; rerun `plan` with `--manager lefthook|husky|plain`.
   Without an answer, stop here and report.
4. **Actions.** A remote plan has none. When `actions[]` holds `copy` items, run
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
6. **Verify.** Run `verify` and report its lines as `check` step 5 does. Also state that with
   no team-tracked `subject_pattern`, and no personal one in a git-ignored
   `docs/conventions/source-control.local.yaml`, every commit-msg subject passes, so the
   `commit-msg-convention` entry is inert until `/source-control:setup apply` writes a
   convention or the operator writes that file.

When the user does not want an entry in this clone, run
`node "${CLAUDE_PLUGIN_ROOT}/lib/git-hooks/install.mjs" decline --entry <name>`; the
session-start drift line then stays silent until `verify` runs by hand, and `--undo` reverses
it. Add `--global` (with or without `--undo`) to decline the entry in every clone;
`git config --global checks.git-hooks.declined true` declines every entry of every plugin, and an
entry's own key set to `false` in a clone opts that entry back in. The [adoption
path](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md) explains each install scope to the user. Declining records the choice and
does not stop an installed copy: when `list` shows the entry installed, also remove its
registration with your edit tools (the
`<event>.d/guardrails.<name>` marker for plain hooks, the `guardrails-<name>` job in the lefthook
config, its line in `.husky/<event>`) and the copy under `guardrails/`, on the user's yes; a shared
registration is a committed change the team reviews. A remote entry stays in the committed
`lefthook.yml`, so stop it in this clone alone by skipping its job, `guardrails-remote-<name>`,
in the clone's gitignored lefthook local config, written as lefthook's docs say at the time
(pointer: [lefthook-local](https://lefthook.dev/examples/lefthook-local/) and
[skip](https://lefthook.dev/configuration/skip/); as of 2026-10-23; recheck trigger: a lefthook
release that changes how a local config overrides a remote's job). This is the way out the `reference-verify`
failure names for a cli-flag finding, which is unverified rather than proven wrong.

## `apply read-deny [local|shared] [user] [remove]` (opt-in, explicit argument only)

Native `Read()` deny rules keep credential files out of the Read tool and out of the Bash file
commands Claude Code applies them to.
`block-credential-read`, off by default, covers what no deny rule reaches when it is on: an
interpreter that opens the file itself (`python3 -c "open('.env')"`). Pointer:
[What Read and Edit rules cover](https://code.claude.com/docs/en/permissions#what-read-and-edit-rules-cover)
and [Special characters and negation](https://code.claude.com/docs/en/permissions#special-characters-and-negation).
As of: 2026-11-10. Recheck trigger: either section changes which tools or Bash commands a
`Read` deny rule reaches, or its pattern syntax.

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
   `Read(!.env.template)`. Each `!` rule must follow `Read(.env.*)` in the same list (how a
   bare filename and a `!` rule match: the pointer above).
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

## `apply identity-domains` (explicit argument only)

Writes `block-cross-domain`'s map, `${CLAUDE_PLUGIN_DATA}/identity-domains.json`, from the
identity domains `/harness-ops:machine-profile` recorded. `<script>` is
`bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/identity-domains.sh"`; its header has the
full rules. Never runs from bare `apply`.

1. **Profile.** The stored profile is `machine-profile/profile.json` in the harness-ops
   plugin's data directory. A saved `/harness-ops:machine-profile` discover output works
   too. When neither path is known, ask the operator. With no profile, point at
   `/harness-ops:machine-profile` and stop.
2. **Preview.** Run `<script> --profile <file> --data-dir "${CLAUDE_PLUGIN_DATA}"`, which
   writes nothing and also says whether a map is already there. Each domain with an absolute tree and no
   wildcard becomes one map domain, named after the tree's last segment: the tree is its
   root, and a `gh` directory the profile records `set` is its `gh_config_dir`. Show the map
   and every `note:` line, since those name the skipped trees and the values left out.
3. **Values the profile lacks.** Owners, identity markers, `az_config_dir` and shared
   exceptions are not discovered. In an attended run, ask for them once, by domain name, and
   pass them as `--owner NAME=OWNER`, `--marker NAME=TEXT`, `--az-config-dir NAME=DIR` and
   `--shared-exception FROM[,FROM...]:TO=PATH`. When the machine keeps repositories outside
   `~/src/github.com` and `~/worktrees/github.com`, also pass `--owner-root DIR`, repeatable,
   for each directory that holds one directory per owner, such as `"$(ghq root)/github.com"`,
   or flat `<owner>-<repo>-<slug>` trees, such as `"$(git config worktreeroot.path)"`. A
   flat tree whose name does not start with its owner stays unguarded, and a name that does
   also names any other domain's root above it, so a session in either domain is denied it.
   A shared exception
   opens PATH, a directory of domain TO, to sessions in the FROM domains, one way; the script
   refuses a PATH that is
   not TO's tree or below it or one of TO's owner directories, and a FROM that lists TO. A
   value nobody gives is left out of the map. A map that still holds a plain-path
   `shared_exceptions` entry from the earlier shape grants nothing for it: re-run this action
   with `--replace` to rewrite it.
4. **Write.** Run `<script> --profile <file> [values] --data-dir "${CLAUDE_PLUGIN_DATA}"
   --confirm` only after the operator says yes to that map in this turn. An unattended run
   stops at the preview. When a different map is already there, the script refuses unless
   you add `--replace`, and you add it only when the operator agrees to overwrite that map.
5. **Report** the map path and the domains written. The map names this machine's trees, so it
   never goes in a tracked file, a fixture or a doc. The guard compiles it on its next call.

## What this skill does NOT do

- Exercise a guard. Any matching tool call does that end-to-end.
- Write the plugin cache or `pluginConfigs`, or user settings other than the two
  `read-deny` rules the user said yes to.
- Install any tool, during either `check` or `apply`. Guidance only. The ONLY writes
  this skill ever performs are `apply install-git-hooks`' entry copies (at `scope=user`, the
  stable copy under the user's git config directory) and the decisions it applies, the
  `apply read-deny` rules in the settings file its scope names, the confirmed
  `apply identity-domains` map, and `apply`'s confirmed cleanup of the retired hooks.
- Weaken a guard: it reports and routes; disabling is always the user's explicit act
  through the native plugin configuration.
