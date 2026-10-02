---
description: "Verify the discovery plugin's runtime prerequisites for this session and print the gate allow rules for the operator to paste so the acceptance-gate scripts stop prompting. Use when: 'set up discovery', 'configure the discovery plugin', 'is discovery configured', 'discovery setup', 'the research gates keep prompting', or a discovery skill reports a missing capability. Action: check (read-only, default). Re-runnable. Safe to invoke again."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Report whether this session can run the discovery plugin's dispatch design, and print the permission
rules that stop the acceptance-gate scripts prompting on every run. Artifact placement needs no
configuration: the plugin's artifact protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md))
fixes where `EXPLORE.md`, `RESEARCH.md` and `INTENT.md` land, in the memory slice
`<memory_dir>/<slug>/`, never committed.

This is a check-only setup. Everything it reports lives in the harness or in the operator's own
`~/.claude/settings.json`, which this skill never writes, so there is nothing for an `apply` to
write. Idempotent: re-running reads the current state again.

## `check` (read-only)

Report a PASS/INFO table. Do not write anything. No row is ever a FAIL or a blocker.

1. **Dispatch capability.** `/discovery:explore` and `/discovery:research` dispatch a subagent by
   default, and that posture degrades rather than breaks on a session that cannot support all of it.
   Report these as PASS/INFO rows:
   - **Harness version against the 2.1.219 floor** (`claude --version`). Below it, several behaviors
     the dispatch design relies on are false rather than merely absent: background became the default
     subagent execution mode in **2.1.198**, and below **2.1.218** a `context: fork` skill always
     blocked the invoking turn and the narrow background tool set did not apply to it. The dated
     record for background as the default is
     [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md),
     "Harness facts the dispatch design rests on". Report the
     observed version and, when it is under the floor, name which of those the session does not have.
     The skills still run, inline is always available, so this is INFO, not FAIL.
   - **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`**. Report the value, present or absent, and say what
     the running harness does with it rather than assuming. Read absent against the observed
     version, in four windows: below **2.1.172** nesting does not exist and the variable buys
     nothing; **2.1.172** to **2.1.216** absent means available at a fixed five; **2.1.217** to
     **2.1.218** absent means *off*, and setting the variable is the only way to turn nesting on;
     **2.1.219** and later absent means available at a configurable default of three, and the
     variable lowers the ceiling (`"1"` disables nesting) as readily as it raises one.
     Report absent as INFO in every window: nesting buys
     **throughput**, not coverage, without it a dispatched agent fans out sequentially, slower for
     the same result. The variable is still only one of **two** conditions: it cannot add a tool an
     agent definition left out. The shipped `discovery:explorer` / `discovery:researcher` definitions
     list `Agent` for exactly this reason; a third-party agent that does not is unaffected by setting
     it. It is not a correctness prerequisite here, because the one control that needs a context
     which has not seen the work is the outcome-gate verifier, and the parent dispatches that as a
     **sibling** rather than the agent as a child. Note that env vars are read at session start, so a
     value set now takes effect next session.
   - **Fork availability.** Report it as a control, not a gate: `CLAUDE_CODE_FORK_SUBAGENT=1` turns fork
     mode on in non-interactive mode and the SDK as well, and `=0` turns it off in every kind of
     session. When the variable is unset, the documented default is on in interactive sessions and
     off in non-interactive mode and the SDK, and the interactive default needs **2.1.232** or
     later. A default is not a runtime guarantee, so the only authoritative probe is still a live
     inheritance check (see `discipline:sweep-all`'s preflight). Report the env var when set; never
     claim forks are unconditionally available on every build. The user-facing command is
     `/subtask` as of **2.1.212**. Verified 2026-09-06 against Claude Code 2.1.263, the subagents
     documentation page and the environment-variables page as fetched that day; recheck when either
     page states a different default or a release note names fork mode.
2. **Gate allow rules.** The acceptance-gate scripts prompt on every run unless the operator's
   `~/.claude/settings.json` allows them. Read its `permissions.allow` (a missing file or key reads
   as no rules; read only, never write) and compare it with these six rules for this install root:

   ```text
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" *)
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh" *)
   Bash("${CLAUDE_PLUGIN_ROOT}/scripts/check-source-applicability.py" *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-coverage-complete.sh *)
   Bash(${CLAUDE_PLUGIN_ROOT}/scripts/check-source-applicability.py *)
   ```

   Report one row, **never FAIL**: PASS when all six are present for this install root; INFO "stale"
   when gate rules name a different `…/scripts/check-*` root (an earlier version's cache directory,
   which stops matching after an update), naming that root; INFO "absent" otherwise. On stale or
   absent, print the six rules resolved to this install root and ready to paste, each as a JSON
   string for `permissions.allow` (the quoted forms escape their inner `"`). Applying them is the
   operator's job: this skill never writes user settings. The rules pin this version's cache
   directory on purpose, so a plugin update invalidates them and `check` reports them "stale" again;
   why a version wildcard is unsafe is in
   [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md)
   ("Operator setup").

## Output

The PASS/INFO table and, when the gate allow rules are stale or absent, the six resolved rules as
JSON strings ready to paste.

## Gotchas

- **Env vars are read at session start.** A capability the check reports as missing stays missing for
  the rest of this session even after it is set, the recommendation takes effect next session.
- **The gate allow rules stop matching after a plugin update.** They name this version's cache
  directory, so the gates prompt again until the operator pastes the rules `check` prints; `check`
  reports them "stale".

## What this skill does NOT do

- Run an exploration, research, or intent-tracing pass. Those are the plugin's discovery skills
  (`/discovery:explore`, `/discovery:research`, `/discovery:research-deep`, `/discovery:trace-intent`).
- Write machine-local state. The plugin directory and the plugin data directory
  (`${CLAUDE_PLUGIN_DATA}`, for caches and generated state only) stay untouched.
- Write Claude Code user settings or `pluginConfigs`. `check` reads `~/.claude/settings.json` and
  prints the gate allow rules; the operator applies them.
