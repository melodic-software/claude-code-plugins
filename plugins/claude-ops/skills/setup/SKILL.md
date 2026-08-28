---
description: "Verify claude-ops's personal path configuration for this repository, where the known-issues registry and the skill-usage log resolve, and explain how to change them through Claude Code. Use when: 'set up claude-ops', 'configure claude-ops', 'claude-ops setup', 'where does the known-issues registry live', or 'where is skill usage logged'. Actions: check (read-only verification, default) | apply (route a reconfiguration once you've chosen a destination). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and reports the
effective personal path options, `apply` resolves what it found. `registry_dir` and `skill_usage_dir`
are personal `userConfig` scalars owned by Claude Code's native configuration surface. Claude Code
prompts for them when the plugin is enabled, stores non-sensitive options in user settings, and ignores
`pluginConfigs` entries in project and local settings on current releases (≥ 2.1.207). This skill never
writes them; `apply` verifies and routes.

Official contract (verified 2026-07-18):
<https://code.claude.com/docs/en/plugins-reference#user-configuration>.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the
reconfiguration guidance below. Both are non-interactive, never prompt when the action is given.

## `check` (read-only)

Read the rendered `${user_config.registry_dir}` and `${user_config.skill_usage_dir}` values from this
skill, never inspect or edit settings files or `pluginConfigs` directly. Report a PASS/FAIL/INFO
table, one remediation line per FAIL. Do not modify anything.

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
   root for `registry_dir` and repo-scope `skill_usage_dir`; `$HOME` for user-scope
   `skill_usage_dir`). FAIL any
   POSIX/rooted path, Windows drive-qualified or drive-relative path, UNC path, any `..` segment with
   either separator, and any existing symlink path that resolves outside that base. Do not normalize
   an invalid value into acceptance, and do not run any operation that would use an invalid destination.
4. **Personal-vs-project**. INFO: both options are personal, user-scoped preferences, not tracked team
   policy. Note the per-machine-vs-repository-resident tradeoff so the reader can choose in `apply`.

## `apply` (idempotent)

Run `check`, then resolve what it found. This skill has no legitimate write of its own, the two
options live in Claude Code's native config surface, which setup must not hand-edit, so `apply` is
verify-and-route:

- **Uncontained value (FAIL):** the destination is invalid; do not use it. Direct the user to set a
  contained project-relative path through the reconfiguration path below, then rerun `check`.
- **Choosing a destination:** if the reader wants the registry per-machine, leave `registry_dir` unset
  (default `${CLAUDE_PLUGIN_DATA}`); if repository-resident, recommend a portable contained path,
  inspecting the consumer's declared artifact conventions. Same for `skill_usage_dir` (default
  `.claude/observability`). State the tradeoff and let the reader pick. Do not prompt.
- **Reconfiguring a personal option:** `/plugin configure claude-ops@<marketplace>` (interactive, any
  time). Headless: rerun the install with the new value:
  `claude plugin install claude-ops@<marketplace> -s <scope> --config KEY=VALUE …` (repeatable per
  key). Against an already-installed plugin it prints `already installed` **and still writes the
  value**. Verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default
  value written to an installed plugin, then restored). The short-circuit is about the install, not
  the config write. Re-verify before relying on it outside those conditions. A `sensitive` option,
  or `project`/`local` scope, were not covered. Do **not** uninstall to reconfigure: uninstalling
  drops this plugin's entire stored `pluginConfigs` entry, resetting every option in the README's
  Options reference table to its manifest default. All fifteen, so the eight `*_audit_enabled`
  toggles come back on and `registry_dir`, `skill_usage_dir`, `skill_usage_scope`,
  `skill_usage_git_exclude`, `install_new`, `instructions_loaded_audit_log_session_start`, and
  `stdin_read_timeout` all revert. `-s` defaults to `user`, so pass the scope `claude plugin list`
  reports for this plugin, and run from that project's directory for a `project`/`local` scope, or
  the write lands at a scope that does not load. This skill never writes user settings or
  `pluginConfigs`.
  Afterwards, keep the two claims apart. The write is issued and the stored value is what you
  passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
  skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
  session start, so a same-session `check` still reports the OLD value. Reporting that as a
  failed write would be wrong. Verify the effective value by rerunning `check` in a **fresh
  session**, and never claim an unobserved change.

After any reconfiguration, rerun `check` in a **fresh session** and report both observed effective
destinations, never claim an unobserved change, and never read a same-session `check` still showing
the old value as a failed write (see the reconfiguration note above for why it does). Re-running
`apply` when both destinations are contained (or defaulted) changes nothing and reports
"already configured".

## What this skill does NOT do

- Run known-issues, registry, or observability operations. Those are the other claude-ops skills and
  have their own documented controls.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Invent organization-specific configuration.
