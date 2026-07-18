---
name: setup
description: "Verify the firecrawl plugin's runtime prerequisites — the firecrawl-cli binary and FIRECRAWL_API_KEY auth — for this machine, respecting the plugin's lazy-install design. Use when: 'set up firecrawl', 'configure firecrawl', 'is firecrawl working', 'firecrawl auth', a scrape reports the CLI is missing, or before a first Firecrawl call. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin is **lazy-install by design** — the main skill treats `firecrawl-cli`
as an escalation option installed when first needed and flags its own absence in its status
line — so a missing CLI is an INFO here, not a failure. This plugin owns no consumer-project
configuration and no `userConfig`; auth is an OS-environment concern. So `apply` is pure
guidance-and-verify with **no write path**: it installs nothing, writes no environment
variables, and defers to the main skill's own documented install flow.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers the resolution for each finding. Both are non-interactive — never prompt when the
action is given.

## `check` (read-only)

The main skill is the single source of truth for what the CLI requires and how auth is wired:
`${CLAUDE_PLUGIN_ROOT}/skills/firecrawl/SKILL.md` (Prerequisites + Configuration sections) and
`${CLAUDE_PLUGIN_ROOT}/skills/firecrawl/context/configuration.md` (the exact env vars the CLI
reads). **Read them first** — probe what they actually require, don't recite this file. Then
run each probe via Bash and report a PASS/FAIL/INFO table. Do not modify anything.

1. **`firecrawl-cli` binary** — the installed binary is `firecrawl` (the npm package is
   `firecrawl-cli`). `command -v firecrawl`. INFO when absent (lazy-install design): report
   that the CLI installs on first need and the main skill self-flags it; remediation is the
   `apply` guidance below. When present, report the version (`firecrawl --version`) and the
   auth line from `firecrawl --status` (which states authenticated/unauthenticated).
2. **Authentication** — the verdict comes from the CLI itself when present: the
   `firecrawl --status` auth line is authoritative, because `firecrawl login`/`config` state
   in the user-level config dir authenticates without any env var. Alongside it, report
   `FIRECRAWL_API_KEY` presence only — test `[[ -n "${FIRECRAWL_API_KEY:-}" ]]` and report
   **set** or **unset**; NEVER print, echo, log, or persist the value. Verdicts, matching the
   lazy-install design: status says authenticated → PASS (INFO-note when the source is
   persisted CLI config rather than the env var — env-var auth is the plugin's preferred
   single source of truth, but never direct the user to ADD an env key on top of working
   CLI-config auth; that would create the second source the plugin warns against). Status
   says unauthenticated (or the CLI cannot answer) and the key is unset → FAIL. CLI absent
   AND key unset → INFO — both arrive at first use, nothing is broken yet.
3. **Optional env vars** — INFO the effective state of the other two the CLI reads
   (`FIRECRAWL_API_URL` for a self-hosted endpoint, `FIRECRAWL_NO_TELEMETRY`), presence only,
   again without printing any value.
4. **Install flow location** — INFO: the main skill's own install and update flow lives in
   `${CLAUDE_PLUGIN_ROOT}/skills/firecrawl/SKILL.md`; `apply` defers there rather than
   duplicating it.

## `apply` (idempotent)

Run `check`, then for each finding offer the resolution — this skill installs nothing and
writes nothing, so every remediation is a pointer the user acts on:

- **CLI absent** — defer to the main skill's documented flow: `npm install -g firecrawl-cli`
  (stated guidance; the user runs it). Do not duplicate the update/rollback mechanics the main
  skill owns. Avoid `firecrawl init --all --browser`, which installs a parallel shadow copy —
  the main skill IS the maintained integration.
- **`FIRECRAWL_API_KEY` unset** — obtain a key from the <https://firecrawl.dev> dashboard and
  set `FIRECRAWL_API_KEY` as an OS user environment variable (Windows: `setx` or System
  Properties → Environment Variables; macOS/Linux: the login shell profile or a secret store).
  Prefer env-var auth over `firecrawl login` / `firecrawl config`, which write a second source
  of truth. This skill never writes the key anywhere. Persistent env changes (`setx`, a
  profile edit) do NOT reach the already-running session — tell the user the variable becomes
  visible only in a new terminal/Claude Code session, and skip the immediate re-check for this
  remediation: report "set persistently; verify with `setup check` in a fresh session" instead
  of a false failure.

After the user reports acting on any remediation, re-run the relevant `check` probe (for the
key, re-check `firecrawl --status` / presence — never the value) and report its actual result.
Re-running `apply` when everything already passes changes nothing and reports "already
configured".

## What this skill does NOT do

- Install `firecrawl-cli`, write `FIRECRAWL_API_KEY` or any environment variable, or print the
  key's value — `apply` is guidance-and-verify with no write path.
- Perform scrapes, searches, or any Firecrawl API call — that is `/firecrawl:firecrawl`.
- Run the maintainer update flow (`/firecrawl:firecrawl update`) — a separate, gated action.
