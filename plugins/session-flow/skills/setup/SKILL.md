---
description: "Verify the session-flow observer's runtime prerequisites and configuration for this machine. Use when: 'set up session-flow', 'configure the observer', 'is the observer working', the SessionStart observer isn't arming, or the observer hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe; only the observer substrate has prerequisites — the other eleven skills are zero-config."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and reports,
`apply` resolves. Only the **detached observer** (see
[`${CLAUDE_PLUGIN_ROOT}/reference/observer.md`](${CLAUDE_PLUGIN_ROOT}/reference/observer.md)) has
runtime prerequisites and configuration; the other skills are zero-config. The observer's tunables are
all native `userConfig`, and its remaining prerequisites are system tools (Python 3.10+, `jq`), so
`apply` is guidance-and-verify with **no write path**: it installs nothing and edits nothing (writing
`pluginConfigs` is what the setup contract forbids).

Action routing: no argument or `check` runs the check; `apply` runs the check first, then offers the
resolution for each finding. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

The hook and launcher are the single source of truth for what they require and how they degrade:
`${CLAUDE_PLUGIN_ROOT}/hooks/observer-arm.sh`, `${CLAUDE_PLUGIN_ROOT}/skills/running-retro/scripts/arm_observer.py`,
and `observer.py` beside it.

**Read it first** — probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the observer is disabled (`observer_enabled` off AND no `arm` invocation in use), every
prerequisite absence downgrades from FAIL to INFO — the hook exits through its opt-in gate before
touching anything, so a deliberately-off observer is not broken. Report the probes informationally
and note that re-enabling restores the FAIL semantics.

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
observer reconfiguration through Claude Code's native flow.
Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.

Reconfiguring the observer's `userConfig` keys has exactly two routes, and only the first works on an
installed plugin:

- **Interactive, any time:** `/plugin configure session-flow@<marketplace>`.
- **Headless:** `--config` only applies on a fresh install (ignored once installed), so reconfigure
  via `claude plugin uninstall session-flow -s <scope>` then
  `claude plugin install session-flow@<marketplace> -s <scope> --config <key>=<value>`. Both
  commands default to `-s user` — pass the scope `claude plugin list` reports for
  this plugin, and run from that project's directory for a `project`/`local` scope. Defaulting
  instead uninstalls a separate user-scope record while the effective install stays in place, so
  the reinstall lands at a scope that does not load. The `--config` flag repeats per key. `-y` only skips `uninstall`'s `--prune`
  confirmation; this recipe never passes `--prune`, so `-y` has no effect here and should not be
  added.

  Uninstalling also drops the stored `pluginConfigs` entry, so the reinstall must re-supply
  **every** key whose value should stay non-default, not only the keys being changed — this plugin
  declares seven, and reinstalling purely to enable the observer otherwise resets a customized
  `observer_analysis_model`, `observer_idle_seconds`, `observer_analysis_bare`, and
  `observer_max_seconds` to their manifest defaults. Run `check` first and record the current
  values, because after the uninstall there is nothing left to read them from.

## Gotchas

- **Setup covers only the observer.** The other session-flow skills need no setup; this skill exists
  because the observer added an external prerequisite and a `userConfig` surface (the setup contract's
  trigger).
- **`observer_analysis_bare` and auth.** `--bare` drops the login credential state on OAuth-login
  installs — leave it off unless auth is an env-var API key. Full detail in
  `${CLAUDE_PLUGIN_ROOT}/reference/observer.md`.
