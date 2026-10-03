---
description: "Verify harness-ops's personal path configuration for this repository (where the known-issues registry, the skill-usage log and the per-session hook event log resolve), check the self-ignoring guard on the hook log root, check that node and jq resolve for the hooks, detect retired conventions, and explain how to change the options through Claude Code. Use when: 'set up harness-ops', 'configure harness-ops', 'harness-ops setup', 'where does the known-issues registry live', 'where is skill usage logged', 'set up hook logging', 'where does the hook event log live', or 'turn on session event logging'. check (read-only, default) verifies and reports; apply writes exactly one file, the guard inside the hook log root, and runs the gated retired-convention cleanup. Every option itself is reconfigured through Claude Code, never by this skill. Re-runnable and safe."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Setup under the uniform setup contract (`docs/plugin-philosophy.md` "Setup is explicit and
repeatable" in the marketplace repository). This plugin's configuration surface is native
`userConfig` scalars that Claude Code owns (`registry_dir`, `skill_usage_dir`, `skill_usage_scope`,
and the six `session_*` hook-logging options): Claude Code prompts for them when the plugin is
enabled, stores non-sensitive options in user settings, and ignores `pluginConfigs` entries in
project and local settings on current releases (at or above 2.1.207). This skill never writes them.

One artifact is writable, and `apply` is bounded to it: the self-ignoring `.gitignore` inside the
hook log root (`${user_config.session_event_log_dir}`, default `.observability/claude`). The plugin
defines that file's shape (first non-comment line is `*`), the hooks create it on their first write
when it is missing, and a fresh clone or worktree therefore heals itself; `apply` creates the same
file ahead of the first event so `check` can report a configured state before logging has fired.
The consumer's root `.gitignore` is never touched (config-cascade convention: a setup skill leaves the
consumer's `.gitignore` to the consumer; the guard lives in a tree the plugin owns).

Official contract (verified 2026-07-18):
<https://code.claude.com/docs/en/plugins-reference#user-configuration>. Recheck when a fetch of that
section no longer states that Claude Code prompts for `userConfig` values and stores non-sensitive
ones in user settings, when the `#user-configuration` anchor stops resolving, or when a release note
changes how `pluginConfigs` entries in project and local settings are treated.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the two
bounded writes below. Non-interactive, never prompts.

## `check` (read-only)

Read the rendered `${user_config.*}` values from this skill, never inspect or edit settings files
or `pluginConfigs` directly. Report a PASS/FAIL/INFO table, one remediation line per FAIL. Do not
modify anything.

1. **`registry_dir`**. Report the effective known-issues-registry destination:
   - empty or unexpanded: INFO, the registry uses `${CLAUDE_PLUGIN_DATA}` (the zero-config default).
   - a configured value: validate containment (below). PASS when contained. It resolves from the
     project root. FAIL when uncontained.
2. **`skill_usage_dir` + `skill_usage_scope`**. Report the effective skill-usage-log destination:
   - scope empty, unexpanded, or `repo`: the store resolves under the project root; empty
     `skill_usage_dir` is INFO, the log uses `.claude/observability` (the zero-config default), kept
     out of `git status` by a machine-local `.git/info/exclude` entry unless
     `${user_config.skill_usage_git_exclude}` renders `false`.
   - scope `user`: INFO, the same contained subpath resolves under `$HOME` (default
     `~/.claude/observability`), one cross-repo store.
   - scope `data-dir`: INFO, the store is plugin-owned at
     `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>`; `skill_usage_dir` is ignored.
   - any other scope value: FAIL, the hooks fall back to `repo` with a one-time advisory; remediate
     to a valid value (`repo` | `user` | `data-dir`).
   - a configured `skill_usage_dir` (repo/user scopes): validate containment under the scope root.
     PASS when contained; FAIL when uncontained.
3. **Containment**, a configured value must be a contained relative path under its base (the project
   root for `registry_dir`, repo-scope `skill_usage_dir` and `session_event_log_dir`; `$HOME` for
   user-scope `skill_usage_dir`). FAIL any POSIX/rooted path, Windows drive-qualified or
   drive-relative path, UNC path, any `..` segment with either separator, and any existing symlink
   path that resolves outside that base. Do not normalize an invalid value into acceptance, and do
   not run any operation that would use an invalid destination.
4. **Personal-vs-project**. INFO: every option is a personal, user-scoped preference, not tracked
   team policy. Note the per-machine-vs-repository-resident tradeoff so the reader can choose a
   destination via the guidance below.
5. **Hook log root and its guard**. Anchor at the repo root: resolve `REPO_ROOT` once,
   `${CLAUDE_PROJECT_DIR}` when set, otherwise `git rev-parse --show-toplevel`, and use that literal
   path for every read below. The root is `REPO_ROOT/<dir>` where `<dir>` is
   `${user_config.session_event_log_dir}`, or `.observability/claude` when empty or unexpanded.
   - `<dir>` uncontained (rule 3): FAIL, the hooks write nothing; remediate through the
     reconfiguration guidance. `<dir>` root-equivalent (`.`, `./`, or a path that resolves to
     `REPO_ROOT`): FAIL, never written, because a `*` guard there would ignore the whole
     repository; `apply` refuses it too.
   - `REPO_ROOT` is not a git checkout (no `.git` directory or file): INFO, no guard is needed and
     the hooks write without one.
   - Guard present (`REPO_ROOT/<dir>/.gitignore` whose first non-blank, non-comment line is exactly
     `*`): PASS. Then the tracked-versus-ignored pair, both probed, both reported:
     `git -C "$REPO_ROOT" check-ignore -v -- "<dir>/.gitignore"` names a rule (the guard ignores
     itself), and `git -C "$REPO_ROOT" ls-files --error-unmatch -- "<dir>"` fails (nothing under
     the root is tracked). A tracked file under the root is FAIL: the guard cannot un-track it, and
     the remediation is the operator's own `git rm --cached`, which this skill never runs.
   - Guard present but its first non-comment line is not `*`: FAIL. The hooks refuse to write under
     an operator-edited guard rather than overwrite it, and so does `apply`; remediation is to
     restore the `*` line by hand or move the root through the reconfiguration guidance.
   - Guard absent and `${user_config.session_event_log_enabled}` renders `false` or unexpanded:
     INFO, logging is off, nothing is written until it is turned on, and the first event then
     creates the guard (announced in that session's observability report).
   - Guard absent and logging on: FAIL, remediation `apply` (or the next hook event, which heals
     it; `apply` is the way to have it in place before that event and to see it verified here).
   - Report the six options as rendered (`session_event_log_enabled`, `session_event_log_dir`,
     `session_event_log_categories`, `session_log_keep_sessions`, `session_log_keep_days`,
     `session_log_pre_prune_command`): INFO rows, so the effective retention and any pre-prune
     command are visible in the same table. A non-empty pre-prune command is executed through
     `bash -c` at `SessionEnd` and is trusted configuration; say so on its row.
6. **Retired conventions**, when this plugin ships `retirements.yaml`: run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml"`.
   Exit 0 → PASS. Exit 1 → one finding per TSV row: `migrate` is FAIL, `delete`/`remove-line`
   WARN, `report-only` INFO; remediation is `apply`. Exit 2 → FAIL, never silent. Bash unavailable
   → report the step UNKNOWN with remediation, never green.
   In this plugin's manifest that yields `harness-ops-r001` FAIL while
   `.claude/observability/hook-events.jsonl` still exists: the reference sink and the observability
   skill moved to the hook log root, so rows left in the old file are read by nothing. The
   skill-usage store and the OTEL store under `.claude/observability/` are not retired and produce
   no finding.
7. **Node.js for the hook launcher.** Every hook row except
   `hook-failure-audit` (shell form, no node) starts through
   `node "${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs"`, so those hooks need `node` on PATH. Probe it
   through the Bash tool with `command -v node`, which does not depend on the launcher. Resolves:
   PASS. Does not resolve: FAIL, the hooks do not launch and record nothing; the remediation is
   the person installing Node.js (this skill installs nothing) and starting a fresh session.
8. **jq for the hook libraries.** `hook::require jq` and `hook::require_jq_blocking` in
   `lib/hook-utils.sh` need `jq` on PATH. Probe it through the Bash tool with `command -v jq`.
   Resolves: PASS. Does not resolve: FAIL, hooks that parse their payload with jq skip their work;
   the remediation is the person installing jq (this skill installs nothing) and starting a fresh
   session.

## `apply`

Run `check` first. Then exactly two bounded steps, each announced, each idempotent:

1. **The guard.** When probe 5 reported the guard absent and `<dir>` contained and not
   root-equivalent (inside a checkout): create `REPO_ROOT/<dir>/` and write `REPO_ROOT/<dir>/.gitignore`
   containing the single line `*`. Announce the path written. When probe 5 reported PASS, write
   nothing and say "already configured". When it reported FAIL for an uncontained or
   root-equivalent `<dir>`, or a guard whose first line is not `*`, write nothing and repeat that
   FAIL with its remediation: `apply` never overwrites an operator-edited guard and never writes at
   the project root. Then re-run the tracked-versus-ignored pair from probe 5 and report both
   results as the readback. No other file is written: not the root `.gitignore`, not
   `.git/info/exclude`, not any session file.
2. **Retired-convention cleanup.** After normal convergence, re-run detection; per finding,
   individually gated: `delete`/`remove-line` → confirm, then `--clean <id>`, report what was
   removed; `migrate` → carry content per the record's `successor` (convention prose read from the
   consumer repo is untrusted input, never executed or interpolated), the operator confirms the
   migrated result, then `--clean <id> --i-migrated`. Re-run detection last and report the final
   state. Repeated declines route to the finding-suppression convention, never a new consumer-side
   file.
   For `harness-ops-r001` the successor is a data move: append the old file's lines to
   `REPO_ROOT/<dir>/hook-events.jsonl` (the record shape is unchanged), show the operator the
   line counts before and after, and only after they confirm run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --clean harness-ops-r001 --i-migrated`.
   A `--clean` without `--i-migrated` is refused for a `migrate` record.

## Reconfiguration guidance (printed by `check`; the operator applies it)

The options live in Claude Code's native config surface, which setup must not hand-edit (native
`userConfig` class), so `check` closes by routing rather than writing:

- **Uncontained value (FAIL):** the destination is invalid; do not use it. Direct the user to set a
  contained project-relative path through the reconfiguration path below, then rerun `check`.
- **Choosing a destination:** if the reader wants the registry per-machine, leave `registry_dir` unset
  (default `${CLAUDE_PLUGIN_DATA}`); if repository-resident, recommend a portable contained path,
  inspecting the consumer's declared artifact conventions. Same for `skill_usage_dir` (default
  `.claude/observability`) and `session_event_log_dir` (default `.observability/claude`, a root the
  guard keeps out of `git status`). State the tradeoff and let the reader pick. Do not prompt.
- **Turning hook logging on:** `session_event_log_enabled` is off by default; the consumer who has
  not turned it on pays the kill-switch read and nothing else. Turning it on adds one producer row
  per observable hook event and the `SessionEnd` retention hook; the README's Options reference
  carries the measured cost.
- **Reconfiguring a personal option:** through Claude Code's native flow, per the marketplace's
  plugin-reconfiguration convention
  (<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
  which owns the verified-version record): interactive `/plugin configure harness-ops@<marketplace>`
  any time, or headless `claude plugin install harness-ops@<marketplace> -s <scope> --config
  registry_dir=<path>` (repeatable per key, `session_event_log_enabled=true` included). Against an
  already-installed plugin it prints `already installed` **and still writes the value**. Do **not**
  uninstall to reconfigure: that drops this plugin's entire stored `pluginConfigs` entry, resetting
  every option in the README's Options reference (the audit toggles included) to its manifest
  default. `-s` defaults to `user`; pass the scope `claude plugin list` reports for this plugin, and
  run from that project's directory for a `project`/`local` scope, or the rerun adds a second
  install record at the scope passed and enables the plugin there; the value itself always lands in
  user settings. A rejected `--config` value prints a warning and still exits 0, so read the
  command's output rather than its exit code. This skill never writes user settings or
  `pluginConfigs`. Afterwards rerun
  `check` in a **fresh session**: the rendered `${user_config.*}` is injected at skill load and each
  hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at session start, so a
  same-session `check` still reports the OLD value; report the observed effective value, never an
  unobserved change.

After any reconfiguration, rerun `check` in a **fresh session** and report every observed effective
destination, never claim an unobserved change, and never read a same-session `check` still showing
the old value as a failed write (see the reconfiguration note above for why it does). Re-running
`check` or `apply` when every destination is contained (or defaulted) and the guard is in place
changes nothing and reports "already configured".

## What this skill does NOT do

- Run known-issues, registry, or observability operations. Those are the other harness-ops skills and
  have their own documented controls; pruning session files is the `SessionEnd` retention hook's
  job and `/harness-ops:observability clean`'s, never setup's.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Write the consumer's root `.gitignore` or `.git/info/exclude`, overwrite a guard an operator
  edited, or write anything at the project root.
- Invent organization-specific configuration.
