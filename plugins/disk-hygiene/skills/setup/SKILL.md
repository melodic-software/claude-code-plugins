---
name: setup
description: "Verify the disk-hygiene plugin's runtime prerequisites and platform posture for this machine. Use when: 'set up disk-hygiene', 'configure disk-hygiene', 'is disk-hygiene working', a clean run reported a missing prerequisite, or before a first audit on a new machine. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — targets and modes arrive as
`/disk-hygiene:clean` arguments, and the only tunable is the native `userConfig` toggle —
so `apply` is pure guidance and writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The clean skill and its bundled scripts (`${CLAUDE_PLUGIN_ROOT}/skills/clean/`) are the
single source of truth for what the plugin requires per platform. **Read them first** —
probe what they actually require, don't recite this file. Then run each probe via Bash and
report a PASS/FAIL/INFO table with one remediation line per FAIL.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — a deliberately disabled plugin is not broken. Report the probes informationally and
note that re-enabling restores the FAIL semantics.

1. **Python floor on `PATH`** — the interpreter used by scanning, validation, the
   guard, and cleanup. (The guard registers on two surfaces: a plugin-level engine gate
   that acts only on engine-referencing commands, and the skill-scoped belt inside the
   `clean` skill's context. Both register unconditionally and resolve the kill switch by
   reading `disk_hygiene_enabled` from the user `settings.json`; the deny-by-default belt
   applies only during `clean`.) The required version has one origin: the `MIN_PYTHON`
   constant in `${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py` — parse it from
   there (`grep -m1 '^MIN_PYTHON' …`) and probe the interpreter against that value; do not
   recite a version number from this file or the README. FAIL if absent or older, naming
   the parsed floor in the remediation; the plugin never downloads a runtime. Report the
   absolute interpreter path (guarded engine calls must use the same absolute interpreter
   the guard reports — Bash aliases and functions cannot substitute).
2. **Git** — `command -v git`. Conditional per the README: optional for ordinary trees,
   required when a target contains or sits inside a Git worktree. Report presence as INFO
   with that conditionality stated; absence is only a FAIL for worktree-containing targets.
3. **Platform posture** — detect the current OS family and report its documented lane per
   the README, keeping the audit and execution lanes visibly separate: Windows (full
   **audit** — `lstat` reparse + Win32, never UAC; engine **execution unsupported** —
   `preview` reports `execution-platform-unsupported` as a per-candidate blocker, removal is
   a manual, per-path Recycle-Bin handoff only under `--execute` and after explicit
   approval), Linux (full audit; execution when
   `/proc/self/mountinfo` is readable — `lsof` needed only for that optional execution
   lane, absent `lsof` is INFO with the reduced-capability note), macOS (audit/report
   only by design; manual Trash handoff only under `--execute` — INFO, not a defect).
4. **Execution kill switch** — resolve the effective `disk_hygiene_enabled` value
   deterministically; never present an assumed value as the configured one. Run the bundled
   probe with the step-1 interpreter:
   `"<python>" "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/kill_switch_probe.py"`
   and report its `effective` value together with its `source` (`configured` vs `default`).
   When the probe says `degraded: true`, report that the configured value could not be read
   and that default `true` is being assumed — an assumption, never the configured value. The
   body token `${user_config.disk_hygiene_enabled}` is at most a cross-check: if it expanded
   to a boolean that contradicts the probe, report the discrepancy instead of silently
   preferring either channel (the probe sees user settings only; managed settings or a
   `--settings` flag can carry a value the probe cannot see).
5. **Plugin registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite is a system
tool or an OS capability, so `apply` installs nothing and writes nothing — it only points:

- missing/old Python: the platform's own install channel for the floor `check` parsed from
  the engine's `MIN_PYTHON`; never a plugin download.
- missing git (worktree targets): platform install instructions.
- toggle off: direct to `/plugin configure disk-hygiene` (interactive, any time).
  Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall disk-hygiene -s <scope>` then
  `claude plugin install disk-hygiene@<marketplace> -s <scope> --config disk_hygiene_enabled=true`;
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run an audit or cleanup — that is `/disk-hygiene:clean`.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool or runtime, during either `check` or `apply` — guidance only.
