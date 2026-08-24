---
description: "Verify the disk-hygiene plugin's runtime prerequisites and platform posture for this machine. Use when: 'set up disk-hygiene', 'configure disk-hygiene', 'is disk-hygiene working', a clean run reported a missing prerequisite, or before a first audit on a new machine. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration, targets
and modes arrive as `/disk-hygiene:clean` arguments, and the only tunable is the native
`userConfig` toggle, so `apply` is pure guidance and writes nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
points at each remediation. Both are non-interactive, never prompt when the action is given.

## `check` (read-only)

The clean skill and its bundled scripts (`${CLAUDE_PLUGIN_ROOT}/skills/clean/`) are the
single source of truth for what the plugin requires per platform.

**Read it first**. Probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

The toggle is an audit-only kill switch, not a short-circuit: the guard registers
unconditionally and still scans with the toggle off, so most prerequisite absences keep their
FAIL semantics regardless of the toggle. Only the execution-tier tools the audit lane never
invokes (step 4's `lsof`-class probes) downgrade from FAIL to INFO when the toggle is
disabled, report those informationally and note that re-enabling restores the FAIL semantics.
A missing `git` stays FAIL either way: the audit lane itself calls it, and its absence degrades
the VCS-tracked-content evidence the plugin's fail-closed posture depends on.

Every step-1 and step-2 failure likewise stays FAIL with the toggle disabled.
Audit-only mode is *enforced by* the guard, every guard surface
depends on a Python 3 interpreter resolving (every surface through
`hooks/run-python-hook.sh`, which tries `python3`, then `python`, then `py -3`), and a
guard that never runs can neither read nor enforce the configured `false`, so the fail-open
is most dangerous in exactly this
configuration. That covers an **exhausted** interpreter ladder, every rung absent, a stub, or
`indeterminate`, a rung whose version probe then fails to launch at all (a corrupt or
zero-length binary outside `WindowsApps`, a broken shim, a permission error), *and* an
interpreter that starts but reports a version below the parsed floor. It does **not** cover a
stubbed `python3` alongside a working `python` or `py -3`: the launcher skips the stub, every
guard launches, and that is a WARN (see step 2), not a failure to downgrade.
Launching the version probe proves only that something executes, not that it can run
the guard's own source: Python 3.6, for example, rejects the guard's
`from __future__ import annotations` and exits without a deny, which PreToolUse treats as
non-blocking, the same silent fail-open through a different door. Unproven guard execution
fails closed like every other guard-relevant unknown in this plugin.

1. **Shell-form launcher registration**. All three registrations (both wired hooks in
   `hooks/hooks.json` and the skill-scoped belt in `skills/clean/SKILL.md` frontmatter) must name
   `hooks/run-python-hook.sh` directly in `command`, with `"shell": "bash"` and **no `args`**, so
   Claude Code routes them through its own Git Bash rather than a `PATH` lookup. FAIL if any
   registration carries an `args` key or sets `command` to a bare interpreter name such as `bash`
   or `python3`: that is exec form, which on Windows resolves `bash` to the WSL relay
   `System32\bash.exe` and `python3` to the zero-length `WindowsApps` App Execution Alias stub, and
   fails to launch, and a failed hook launch is non-blocking, so the guard silently enforces
   nothing (#1416 for the wired hooks, #2568 for the belt). Do **not** report this as a
   `PATH`-ordering problem: shell form is resolved by
   Claude Code, so reordering `PATH` neither causes nor fixes it. Also FAIL if the launcher is
   missing or not executable. Report a missing Git Bash on Windows as an environment prerequisite
   (shell form falls back to PowerShell there, which cannot run a `.sh`), not as a `PATH` fix.
2. **Python floor on `PATH`**. The interpreter used by scanning, validation, the
   guard, and cleanup. (The guard registers on two surfaces: a plugin-level engine gate
   that acts only on engine-referencing commands, and the skill-frontmatter belt that
   Claude Code keeps armed for the rest of the session after `/disk-hygiene:clean` is
   invoked. Both register unconditionally and resolve the kill switch by
   reading `disk_hygiene_enabled` from the user `settings.json`.) The required version has one origin: the `MIN_PYTHON`
   constant in `${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py`, parse it from
   there (`grep -m1 '^MIN_PYTHON' …`) and probe the interpreter against that value; do not
   recite a version number from this file or the README. FAIL if absent or older, naming
   the parsed floor in the remediation; the plugin never downloads a runtime. Report the
   absolute interpreter path (guarded engine calls must use the same absolute interpreter
   the guard reports. Bash aliases and functions cannot substitute).

   On Windows, confirm the name the guard resolves is real BEFORE anything executes it,
   including this floor check's own version probe. `python3` is the first rung of the ladder
   `hooks/run-python-hook.sh` walks for every guard surface; on stock Windows it resolves to a
   zero-length `WindowsApps\python3.exe` App Execution Alias that opens the Microsoft Store
   (or hangs) instead of running an interpreter, and executing that name from setup pops the
   Store instead of probing. Since #2568 the stub no longer stops any guard by itself, the
   launcher skips it and falls through to `python`, then `py -3`. **The ladder, not the first
   rung, is the verdict.** A host with real Python installed without "Add to PATH" but with the
   `py` launcher has a stubbed `python3` and a perfectly working guard; failing it would report a
   healthy install as broken and send the operator to reinstall Python. So the alias probe is
   **diagnostic input**. It says what the first rung is, and keeps setup from executing it,
   while the verdict comes from resolving the ladder and checking the selected interpreter
   against the parsed floor.
   Order of operations: (a) locate the resolution without executing it (`Get-Command python3`
   / `command -v python3`, locating is inspection; running is not); (b) classify it with the
   bundled inspect-only probe, launched via an interpreter that is NOT the bare name
   `python3` (`py -3`, `python`, or an absolute interpreter path, any interpreter already
   proven real):
   `"<python>" "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/python3_alias_probe.py"`; if no
   such interpreter exists **or the one you chose emits no JSON verdict**, apply the probe's own
   portable signal directly in PowerShell. Proven real is not the same as able to run the probe:
   a pre-3.7 interpreter rejects its `from __future__ import annotations` and a legacy `python`
   2.x fails earlier still, each before anything is classified, so a machine whose only
   alternate launcher is Python 3.6 reaches the verdict through PowerShell, not by having no
   launcher at all. The signal: a zero-length file under a `WindowsApps` path component is the stub
   (`(Get-Item -Force (Get-Command python3).Source)` → `Length` 0 plus a `ReparsePoint`
   attribute); (c) resolve the ladder in the launcher's own order, skipping any rung the probe
   classified as a stub: `python3` only when its verdict is `ok`, then `python`, then `py -3`.
   The version probe may execute a rung only once that rung is not a stub, that is the whole
   point of (b), and it is why the bare name `python3` is never executed on a
   `store-alias-stub` verdict. Report the absolute path of the first rung that runs and meets
   the floor.

   **FAIL when the ladder is exhausted or below the floor**. No rung resolves, or the one that
   does reports a version under the parsed `MIN_PYTHON`. That is the real fail-open: the guard
   cannot run, and it emits neither exit 2 nor a `deny`. Distinguish the two for the remediation
   wording, an interpreter that starts and reports a version below the floor is a floor miss
   (name the parsed floor), one that fails to launch at all is an absent-interpreter failure
   (the plugin never downloads a runtime). Both keep the FAIL under a disabled toggle: a
   below-floor interpreter is not proven able to execute the guard's source, so audit-only mode
   is unenforceable there too. `indeterminate` on **every** rung is the same case, identity the
   probe could not read anywhere on the ladder is uncertainty about whether the guard can launch
   at all, and fails closed like every other guard-relevant unknown in this plugin.

   **PASS with a WARN when the ladder resolves a supported interpreter but `python3` is the
   stub.** Every guard launches, so nothing is failing open. State the residual plainly: the
   operator's own bare `python3` still opens the Microsoft Store, and guarded engine calls must
   use the absolute interpreter path reported above rather than that name. Offer the same
   remediation as an optional tidy-up, not as a fix for a broken install, disable the `python3`
   App execution alias (Settings > Apps > Advanced app settings > App execution aliases), or put
   real Python ahead of WindowsApps on `PATH`. A bare `command -v python3` success is not
   evidence on its own, it matches the stub too.
3. **Git**. `command -v git`. Conditional per the README: optional for ordinary trees,
   required when a target contains or sits inside a Git worktree. Report presence as INFO
   with that conditionality stated; absence is only a FAIL for worktree-containing targets.
4. **Platform posture**. Detect the current OS family and report its documented lane per
   the README, keeping the audit and execution lanes visibly separate: Windows (full
   **audit**: `lstat` reparse + Win32, never UAC; engine **execution unsupported**.
   `preview` reports `execution-platform-unsupported` as a per-candidate blocker, removal is
   a manual, per-path Recycle-Bin handoff only under `--execute` and after explicit
   approval), Linux (full audit; execution when
   `/proc/self/mountinfo` is readable, `lsof` needed only for that optional execution
   lane, absent `lsof` is INFO with the reduced-capability note), macOS (audit/report
   only by design; manual Trash handoff only under `--execute`. INFO, not a defect).
5. **Execution kill switch**. Resolve the effective `disk_hygiene_enabled` value
   deterministically; never present an assumed value as the configured one. Run the bundled
   probe with the step-2 interpreter:
   `"<python>" "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/kill_switch_probe.py"`
   and report its `effective` value together with its `source` (`configured` vs `default`).
   When the probe says `degraded: true`, report that the configured value could not be read
   and that default `true` is being assumed, an assumption, never the configured value. The
   body token `${user_config.disk_hygiene_enabled}` is at most a cross-check: if it expanded
   to a boolean that contradicts the probe, report the discrepancy instead of silently
   preferring either channel (the probe sees user settings only; managed settings or a
   `--settings` flag can carry a value the probe cannot see).
6. **Plugin registration**. INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL point at the resolution. Every prerequisite is a system
tool or an OS capability, so `apply` installs nothing and writes nothing, it only points:

- missing/old Python: the platform's own install channel for the floor `check` parsed from
  the engine's `MIN_PYTHON`; never a plugin download.
- missing git (worktree targets): platform install instructions.
- toggle off: direct to `/plugin configure disk-hygiene` (interactive, any time).
  Headless: rerun the install with the new value:
  `claude plugin install disk-hygiene@<marketplace> -s <scope> --config disk_hygiene_enabled=true`
  (repeatable per key). Against an already-installed plugin it prints `already installed` **and
  still writes the value**. Verified on Claude Code 2.1.240 (a non-sensitive option at `user`
  scope: a non-default value written to an installed plugin, then restored). The short-circuit is
  about the install, not the config write. Re-verify before relying on it outside those
  conditions, a `sensitive` option, or `project`/`local` scope, were not covered. Do **not**
  uninstall to reconfigure: uninstalling drops this plugin's entire stored `pluginConfigs` entry,
  resetting every option in the README's Options reference table to its manifest default. `-s`
  defaults to `user`, so pass the scope `claude plugin list` reports for this plugin, and run from
  that project's directory for a `project`/`local` scope, or the write lands at a scope that does
  not load. This skill never writes user settings or `pluginConfigs`.
  Afterwards, keep the two claims apart. The write is issued and the stored value is what you
  passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
  skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
  session start, so a same-session `check` still reports the OLD value, reporting that as a
  failed write would be wrong. Verify the effective value by rerunning `check` in a **fresh
  session**, and never claim an unobserved change.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run an audit or cleanup, that is `/disk-hygiene:clean`.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Install any tool or runtime, during either `check` or `apply`, guidance only.
