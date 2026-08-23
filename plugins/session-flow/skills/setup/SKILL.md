---
description: "Verify the session-flow observer's runtime prerequisites and configuration for this machine. Use when: 'set up session-flow', 'configure the observer', 'is the observer working', the SessionStart observer isn't arming, or the observer hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe; only the observer substrate has prerequisites — the other thirteen skills are zero-config."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply` resolves.
Only the **detached observer** (see [`${CLAUDE_PLUGIN_ROOT}/reference/observer.md`](${CLAUDE_PLUGIN_ROOT}/reference/observer.md))
has runtime prerequisites and configuration; the other skills are zero-config. The observer's tunables
are all native `userConfig`, and its remaining prerequisites are system tools (Python 3.10+, `jq`), so
`apply` is guidance-and-verify with **no write path**: it installs nothing and edits nothing (writing
`pluginConfigs` is what the setup contract forbids).

Action routing: no argument or `check` runs the check; `apply` runs the check first, then offers the
resolution for each finding. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook and launcher are the single source of truth for what they require and how they degrade:
`${CLAUDE_PLUGIN_ROOT}/hooks/observer-arm.sh`, `${CLAUDE_PLUGIN_ROOT}/skills/running-retro/scripts/arm_observer.py`,
and `observer.py` beside it. **Read them first** — probe what they actually do, don't recite this file.
Then run each probe via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do
not modify anything.

When the observer is disabled (`observer_enabled` off AND no `arm` invocation in use), every
prerequisite absence downgrades from FAIL to INFO — the hook exits through its opt-in gate before
touching anything, so a deliberately-off observer is not broken. Note that re-enabling restores FAIL
semantics.

1. **Python 3.10+** — the launcher and tailer are stdlib-only Python 3.10+. Probe the same interpreter
   detection the hook uses (`python3` then `python`, requiring `sys.version_info >= (3, 10)`). FAIL if
   none qualifies: without it the hook silently skips arming. Remediation: install Python 3.10+ on PATH.
2. **`jq`** — the SessionStart hook parses its stdin (`session_id`, `transcript_path`, `source`,
   `agent_type`) with `jq`. FAIL (auto-arm path only) if absent: the hook exits early and never arms.
   The manual `arm` action resolves inputs without `jq`, so absence is INFO for that path. Remediation:
   install `jq` (<https://jqlang.org/download/>).
3. **`claude` CLI on PATH** — the autonomous analysis leg invokes `claude -p`. INFO if absent: the
   observer still distills and retains observations under its plugin work dir; the analysis run is
   skipped and nothing is written to the ledger.
4. **Observer config** — report the effective value of each native key (an unexpanded `${user_config.…}`
   token or empty means the default): `${user_config.observer_enabled}` (default off),
   `${user_config.observer_analysis_enabled}` (default on), `${user_config.observer_analysis_model}`
   (default `claude-haiku-4-5`), `${user_config.observer_analysis_bare}` (default off),
   `${user_config.observer_idle_seconds}` (default 900), `${user_config.observer_poll_seconds}`
   (default 5), `${user_config.observer_max_seconds}` (default
   86400). Call out two hazards: `observer_analysis_bare` on is a FAIL on an OAuth-login install (the
   analysis run reports "Not logged in"); `observer_idle_seconds` below the machine's longest expected
   single turn risks firing analysis on a partial transcript.
5. **Hook registration** — INFO: confirm the plugin is enabled for this project (`/plugin` → Installed)
   rather than parsing settings files. The SessionStart hook only auto-arms when `observer_enabled` is on.

## `apply`

No write path. Run `check`, then for each FAIL offer the remediation: install the missing tool, or route
observer reconfiguration through Claude Code's native flow. Never write `pluginConfigs`, mutate user
settings, or edit the installed plugin cache.

Reconfiguring the observer's `userConfig` keys has exactly two routes, and both work on an already
installed plugin:

- **Interactive, any time:** `/plugin configure session-flow@<marketplace>`.
- **Headless:** rerun the install with the new value —
  `claude plugin install session-flow@<marketplace> -s <scope> --config <key>=<value>` (repeatable
  per key). Against an already-installed plugin it prints `already installed` **and still writes the
  value** — verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default
  value written to an installed plugin, then restored). The short-circuit is about the install, not
  the config write. Re-verify before relying on it outside those conditions — a `sensitive` option,
  or `project`/`local` scope, were not covered.

  `-s` defaults to `user`. Pass the scope the plugin is *actually* installed at —
  `claude plugin list` reports it per plugin — and run from that project's directory when the scope
  is `project` or `local`, or the write lands at a scope that does not load.

  Do **not** uninstall to reconfigure. Uninstalling drops the stored `pluginConfigs` entry outright,
  so every option in the README's Options reference table falls back to its manifest default —
  a customized `observer_analysis_model`, `observer_idle_seconds`, `observer_analysis_bare`, or
  `observer_max_seconds` is simply gone, with nothing left to read the old values from.

Afterwards, keep the two claims apart. The write is issued and the stored value is what you
passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
session start, so a same-session `check` still reports the OLD value — reporting that as a failed
write would be wrong. Verify the effective value by rerunning `check` in a **fresh session**, and
never claim an unobserved change.

## Gotchas

- **Setup covers only the observer.** The other session-flow skills need no setup; this skill exists
  because the observer added an external prerequisite and a `userConfig` surface (the setup contract's
  trigger).
- **`observer_analysis_bare` and auth.** `--bare` drops the login credential state on OAuth-login
  installs — leave it off unless auth is an env-var API key. Full detail in
  `${CLAUDE_PLUGIN_ROOT}/reference/observer.md`.
