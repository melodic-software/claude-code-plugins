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
   when it carries a `[tool.ruff]` section (read the hook for the exact names and the
   section test). Report the governing config the walk discovers, or INFO that none exists —
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

- A uv- or Poetry-managed project (`uv.lock`, `poetry.lock`, or the matching
  `pyproject.toml` tool section) → use the project's own dependency command so the
  manifest and lockfile record it — `uv add --dev ruff` / `poetry add --group dev ruff` —
  never a bare install into the `.venv`, which the next `uv sync` or environment
  recreation would silently remove. State the change before running. **Poetry only when
  the environment is somewhere the hook resolves**: by default Poetry keeps its
  virtualenv in a cache directory, not the repo `.venv`, and the hook resolves only the
  repo-ancestor `.venv` interpreters or `PATH` — so first confirm an in-project
  environment (`poetry config virtualenvs.in-project` effective true, or a repo `.venv`
  Poetry manages). Without one, don't run the install; guide instead: enable
  `poetry config virtualenvs.in-project true` and recreate the environment, or otherwise
  put `ruff` on `PATH` — then re-check.
- A plain existing `.venv` with NO managing tool detected → install with the
  environment's own `pip install ruff`. State the change and the target environment
  before running.
- Anything ambiguous — no `.venv`, no recognized project tool, or conflicting signals —
  stops with guidance rather than guessing; never create a virtual environment or
  `pip install` outside a managed environment. The README's astral install URL
  (`https://docs.astral.sh/ruff/installation/`) is the fallback pointer, matching the
  hook's own skip-notice text.

After ANY remediation, re-run the relevant `check` probe and report its actual result —
never claim resolved on the install command's exit code alone. For everything else `apply`
only points:

- missing `jq` / Bash: platform install instructions from the README Requirements section;
  this skill never installs system packages.
- toggle off: direct to `/plugin configure ruff-format` or
  `claude plugin install ruff-format@<marketplace> --config ruff_format_enabled=true`;
  this skill never writes user settings or `pluginConfigs`.
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
