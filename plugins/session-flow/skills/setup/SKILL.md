---
description: "Verify the session-flow observer's runtime prerequisites and configuration for this machine. Use when: 'set up session-flow', 'configure the observer', 'is the observer working', the SessionStart observer isn't arming, or the observer hook reported a missing prerequisite. Check-only: verifies, reports, and offers each remediation; installs nothing and there is nothing setup may write here. Re-runnable and safe; only the observer substrate has prerequisites, the other thirteen skills are zero-config."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Check-only setup under the Check-only carve-out (`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit
and repeatable" in the marketplace repository): this plugin's configuration surface contains no
writable artifact, so `check` inspects, reports, and offers each remediation, and no `apply` is
offered because there is nothing it could conformingly write. Only the **detached observer** (see
[`${CLAUDE_PLUGIN_ROOT}/reference/observer.md`](${CLAUDE_PLUGIN_ROOT}/reference/observer.md)) has
runtime prerequisites and configuration; the other skills are zero-config. The observer's tunables
are all native `userConfig` (the carve-out's native-`userConfig` class), and its remaining
prerequisites are system tools (Python 3.10+, `jq` — the external-prerequisites class), so setup
installs nothing and edits nothing (writing `pluginConfigs` is what the setup contract forbids).

Action routing: no argument or `check` runs the check. Non-interactive, never prompts.

## `check` (read-only)

The hook and launcher are the single source of truth for what they require and how they degrade:
`${CLAUDE_PLUGIN_ROOT}/hooks/observer-arm.sh`, `${CLAUDE_PLUGIN_ROOT}/skills/running-retro/scripts/arm_observer.py`,
and `observer.py` beside it.

**Read it first.** Probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

When the observer is disabled (`observer_enabled` off AND no `arm` invocation in use), every
prerequisite absence downgrades from FAIL to INFO, the hook exits through its opt-in gate before
touching anything, so a deliberately disabled plugin is not broken. Report the probes informationally
and note that re-enabling restores the FAIL semantics.

1. **Python 3.10+**, the launcher and tailer are stdlib-only Python 3.10+. Probe the same interpreter
   detection the hook uses (`python3` then `python`, requiring `sys.version_info >= (3, 10)`). FAIL if
   none qualifies: without it the hook silently skips arming. Remediation: install Python 3.10+ on PATH.
2. **`jq`**, the SessionStart hook parses its stdin (`session_id`, `transcript_path`, `source`,
   `agent_type`) with `jq`. FAIL (auto-arm path only) if absent: the hook exits early and never arms.
   The manual `arm` action resolves inputs without `jq`, so absence is INFO for that path. Remediation:
   install `jq` (<https://jqlang.org/download/>).
3. **`claude` CLI on PATH**, the autonomous analysis leg invokes `claude -p`. INFO if absent: the
   observer still distills and retains observations under its plugin work dir; the analysis run is
   skipped and nothing is written to the ledger.
4. **Observer config**. Report the effective value of each native key (an unexpanded `${user_config.…}`
   token or empty means the default): `${user_config.observer_enabled}` (default off),
   `${user_config.observer_analysis_enabled}` (default on), `${user_config.observer_analysis_model}`
   (default `claude-haiku-4-5`), `${user_config.observer_analysis_bare}` (default off),
   `${user_config.observer_idle_seconds}` (default 900), `${user_config.observer_poll_seconds}`
   (default 5), `${user_config.observer_max_seconds}` (default
   86400). Call out two hazards: `observer_analysis_bare` on is a FAIL on an OAuth-login install (the
   analysis run reports "Not logged in"); `observer_idle_seconds` below the machine's longest expected
   single turn risks firing analysis on a partial transcript.
5. **Hook registration**. INFO: confirm the plugin is enabled for this project (`/plugin` → Installed)
   rather than parsing settings files. The SessionStart hook only auto-arms when `observer_enabled` is on.

## Remediation guidance (printed by `check`; the operator applies it)

No write path. For each FAIL, `check` closes by offering the remediation: install the missing
tool, or route observer reconfiguration through Claude Code's native flow.
Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.

Reconfigure the observer's `userConfig` keys through Claude Code's native flow, per the
marketplace's plugin-reconfiguration convention
(<https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md>,
which owns the verified-version record): interactive `/plugin configure session-flow@<marketplace>`
any time, or headless `claude plugin install session-flow@<marketplace> -s <scope> --config <key>=<value>`
(repeatable per key) — against an already-installed plugin it prints `already installed` and still
writes the value. Do **not** uninstall to reconfigure: that drops the stored `pluginConfigs` entry
outright, resetting every option in the README's Options reference to its manifest default, with
nothing left to read the old values from. `-s` defaults to `user`; pass the scope
`claude plugin list` reports, and run from that project's directory for a `project`/`local` scope,
or the write lands at a scope that does not load. Afterwards rerun `check` in a **fresh session** —
the rendered `${user_config.*}` is injected at skill load and each hook's `CLAUDE_PLUGIN_OPTION_*`
is fixed at session start, so a same-session `check` still reports the OLD value; report the
observed effective value, never an unobserved change.

## Gotchas

- **Setup covers only the observer.** The other session-flow skills need no setup; this skill exists
  because the observer added an external prerequisite and a `userConfig` surface (the setup contract's
  trigger).
- **`observer_analysis_bare` and auth.** `--bare` drops the login credential state on OAuth-login
  installs. Leave it off unless auth is an env-var API key. Full detail in
  `${CLAUDE_PLUGIN_ROOT}/reference/observer.md`.
