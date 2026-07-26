---
name: setup
description: "Verify the ruff-format hook's runtime prerequisites and configuration for this repository. Use when: 'set up ruff-format', 'configure ruff-format', 'is ruff-format working', formatting silently isn't happening, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply [install-ruff]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — rules come from the
repository's own Ruff config, and the only tunable is the native `userConfig` toggle — so
`apply` is guidance-and-verify, with exactly one write path: the explicitly invoked
`apply install-ruff` install into the repo's existing managed environment described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation; `apply install-ruff` additionally authorizes the consumer-repo install
described below. All are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook script (`${CLAUDE_PLUGIN_ROOT}/hooks/ruff-format.sh`) is the single source of
truth for what it requires and how it resolves things. **Read it first** — probe what it
actually does, don't recite this file. Then run each probe via Bash and report a
PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check against the hook's documented floor (README Requirements),
   noting any features the hook degrades without (for example telemetry's `EPOCHREALTIME`,
   Bash 5.0+).
2. **`jq`** — `command -v jq`. FAIL if absent: the hook then skips with a visible
   once-per-session notice instead of formatting.
3. **Ruff binary** — resolve it exactly the way the hook's resolution code does: its
   repo-managed virtual-environment walk (the exact `.venv` interpreter paths it tests for
   the current platform, walking up from the edited file toward the repo root) and then
   `PATH`. Test only what the hook tests — a binary the hook would not accept must not PASS
   here. FAIL when nothing the hook would resolve is present while a Ruff config governs the
   repo; the hook then emits a visible once-per-session skip notice instead of formatting.
4. **Consumer Ruff config** — mirror the hook's opt-in walk: it stops at the FIRST
   (closest) governing config found walking from the edited file's directory up to the repo
   root, honoring Ruff's own same-directory precedence and counting a `pyproject.toml` only
   when it carries a `[tool.ruff]` section or any `[tool.ruff.*]` subtable such as
   `[tool.ruff.lint]` (read the hook for the exact names and the section test — its test is
   the authority). Report the governing config the walk discovers, or INFO that none exists —
   absence is the opt-out by design, so the plugin is inert (INFO, not FAIL), matching the
   README's "ships no rules of its own" stance.
5. **Hook toggle** — report the effective `ruff_format_enabled` value:
   `${user_config.ruff_format_enabled}` (unexpanded or empty means default `true`).
6. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution — never install anything without the
consumer's explicit go-ahead in the invocation. `apply install-ruff` installs Ruff **only
into a managed Python environment the repo already uses**, never by creating one and never
globally, mirroring how the hook resolves the binary. Resolve the target from what the repo
already declares:

Principles, in order — they decide every case, whatever the tool:

1. **Identify the repo's dependency manager from its own markers** — a lockfile or a
   `pyproject.toml` tool section (uv, Poetry, Pipenv, PDM, Hatch, …). Recognize the tool
   from what the repo declares; don't assume from an enumerated list.
2. **Record through the manager, never around it.** A managed project gets Ruff via that
   tool's own dev-dependency add command (e.g. `uv add --dev ruff`,
   `poetry add --group dev ruff`, `pipenv install --dev ruff`, `pdm add -d ruff`) so the
   manifest and lockfile record it — a bare `pip install` into its environment is state
   the tool's next sync or clean silently removes.
3. **Never create or mutate an environment.** When no environment exists yet, use the
   tool's record-only mode when it has one (e.g. `uv add --dev ruff --no-sync` — plain
   `uv add` syncs and would create `.venv`) and hand the sync/install step to the
   consumer as their own command; when the tool's add command cannot avoid
   creating/instantiating an environment, don't run it — give it as guidance instead.
4. **Only where the hook resolves.** The hook resolves repo-ancestor `.venv` interpreters
   or `PATH`, nothing else. Tools that default their environment to a cache directory
   (Poetry, Pipenv, and any similar) must have an in-project environment confirmed first
   (the tool's own config/env answers — e.g. `poetry config virtualenvs.in-project`,
   `PIPENV_VENV_IN_PROJECT`); otherwise guide (enable in-project mode + recreate, or put
   `ruff` on `PATH`) rather than installing somewhere the hook never looks.
5. **Bare `pip install` only into a plain existing `.venv`** with no manager markers of
   any kind. State the change and target environment before running.
6. **Ambiguity stops.** No environment plus no recognized manager, or conflicting
   signals → guidance only, anchored on the README's astral install URL
   (`https://docs.astral.sh/ruff/installation/`), matching the hook's own skip-notice
   text.

After ANY remediation, re-run the relevant `check` probe and report its actual result —
never claim resolved on the install command's exit code alone. For everything else `apply`
only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure ruff-format` (interactive, any
  time). Headless: `--config` only applies on a fresh install (ignored once installed), so
  reconfigure via `claude plugin uninstall ruff-format -s <scope>` then
  `claude plugin install ruff-format@<marketplace> -s <scope> --config ruff_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`. Both commands default to `-s user` —
  pass the scope `claude plugin list` reports for this plugin, and run from that project's
  directory for a `project`/`local` scope. Defaulting instead uninstalls a separate user-scope
  record while the effective install stays in place, so the reinstall lands at a scope that
  does not load.
- no Ruff config: offer to create a minimal Ruff config in the repository root only when
  explicitly asked — the plugin imposes no rules of its own.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## What this skill does NOT do

- Run the formatter — editing any `.py`/`.pyi` file exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Create a virtual environment, install Ruff globally, or install outside a managed
  environment the repo already uses.
- Download or execute tools during `check`; network use happens only in an explicitly
  requested `apply install-ruff` inside the consumer repository.
