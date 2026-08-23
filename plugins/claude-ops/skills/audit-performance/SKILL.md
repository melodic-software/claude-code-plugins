---
description: "Read-only slowness-diagnostic capture for a Claude Code installation. Run it AT THE MOMENT the machine or a session feels slow, before restarting or deleting anything. One timed engine pass captures: CLI version (the version-regression suspect), retention-sweep health including the silent unparsable-settings pause (the accumulated-state suspect), a timed stat-walk of the install tree approximating the product's own daily sweep cost, active-session and plugin-fleet counts (the component-bloat suspect), and the fan-out layer (the per-spawn suspect): a load-labelled no-op spawn baseline, every hook that will fire bucketed per-tool-call versus per-turn, the statusline, subagent concurrency ceilings against documented defaults, whether running sessions predate the settings file, and orphan attribution by parent liveness not age. Plus a process census, Defender guidance, and a bundled known-performance-issues reference. Reports and routes; never mutates, never deletes, never 'fixes', never executes a discovered hook. Use when: 'Claude Code is slow', 'typing lags', 'my machine freezes when Claude runs', 'audit performance', 'why is this session sluggish', 'diagnose Claude slowness before I nuke anything', 'my hooks are slowing everything down', 'too many subagents'. Not for: install-tree inventory (/claude-ops:audit-install-state), deleting anything (/disk-hygiene:clean), plugin enablement verdicts (/claude-ops:plugins audit), or upstream bug lookup alone (/claude-ops:known-issues, which this composes with)."
argument-hint: "[--root <path>] (defaults to $CLAUDE_CONFIG_DIR, else ~/.claude); pass the current session id via --session-id when known"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Capture slowness evidence while slow. Version, sweep health, tree walk, sessions, fleet, fan-out
  cadence: continuous
---

## Purpose

"It was slow, so I deleted everything and reinstalled" destroys the evidence and confounds the fix:
a reinstall crosses version upgrades, so nobody learns whether accumulated state, a version
regression, or component bloat was the cause. This skill is the five-minute capture that runs
*while it is slow*, so the diagnosis rests on measurements instead of a nuked crime scene.

It deliberately answers "what is true right now" and refuses "so delete X". Remediation routes
out (see the boundary table). The engine's own phase timings are first-class evidence: a census
walk that takes minutes IS the cost the product's retention sweep pays on that tree; a
`claude --version` probe that takes ten seconds is itself a finding.

## Scope boundary

| Question | Owner |
|---|---|
| Why is Claude Code slow right now? | **this skill** |
| What exactly is in the install tree, and is anything stale? | `/claude-ops:audit-install-state` |
| Which plugins are enabled at which scope, and is the fleet current? | `/claude-ops:plugins audit` |
| Is this a known upstream bug? | `/claude-ops:known-issues` (compose: search the symptoms this report surfaces) |
| Delete a genuinely unmanaged leftover | `/disk-hygiene:clean` |
| Shed one project's `~/.claude.json` state | `claude project purge <path>` |

## Never read

`.credentials.json`, `daemon/*.key`, `ide/*.lock` bodies, the values inside `~/.claude.json`, and
the contents of `history.jsonl` and transcript files. The engine's content-read allowlist is four
non-secret config files: `settings.json`, `.last-cleanup`, a plugin's `hooks/hooks.json`, and
`plugins/installed_plugins.json`. Everything else is stat-only. Name, size, mtime. The allowlist
is enforced in `read_json`, which raises rather than reading a file it does not name, so the
prose and the code cannot drift apart.

The last two entries are new, and they are what makes hook enumeration possible: a hook manifest
holds an event, a matcher, and a command string, and the installed-plugins manifest holds install
paths. Neither carries credential material. Nothing else was opened to add them.

**This rule is inherited by every subagent this skill dispatches; say so explicitly in any prompt
you fan out.**

## Never execute

The engine enumerates the hooks and the statusline command that will fire; it never runs one.
A hook is third-party code with arbitrary side effects, so timing one by executing it would turn
a read-only capture into a mutation, and a `PreToolUse` hook run outside a tool call may not even
be idempotent. Per-hook attribution is the operator's step, taken deliberately and with the
consequences understood. What the engine supplies for it is the no-op spawn baseline every hook
pays before doing any work of its own.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-performance/scripts/audit_performance.py" \
  --session-id "<current-session-id-if-known>" \
  --project-dir "${CLAUDE_PROJECT_DIR:-.}" > ./claude-performance-report.json
```

Pass `--project-dir` whenever a project root is known, so project-scope hooks in that repo's
`.claude/settings.json` are counted alongside the user-scope and plugin ones. Without it the hook
inventory reports a floor, not a total.

Write the report **outside** the install root. Python 3.11+ is the only requirement. No
PowerShell, no third-party packages. On a machine that is currently struggling, expect the run
itself to be slow; that is signal, not failure. Report the phase timings prominently.

Escape hatches for a machine too contended for the full pass, in the order to reach for them:
`--subprocess-timeout <seconds>` raises the per-probe bound (the default of 20 s is below the
range a statusline render can reach under a storm, and a probe that times out is recorded as a
finding rather than dropped); `--spawn-samples <n>` and `--population-gap 0` shorten the two
probes that deliberately take wall-clock time; `--skip-fan-out` and `--skip-processes` drop whole
phases. Say which flags you passed, because each one narrows what the report can conclude.

Alongside the engine run, record what only the operator knows, in one or two sentences each: what
was slow (typing? tool calls? the whole machine?), how many terminals were open, what the session
was doing, and, on Windows, whether Task Manager showed "Antimalware Service Executable" or
disk saturation. The engine cannot see intent; the report is incomplete without this paragraph.

## Reading the report. Separate the four suspects

Lead with `sweep_health.findings`, then work the suspects in order. For each, state what the
evidence supports and what it cannot distinguish. This report is one sample, not a longitudinal
study.

**Clearing the first three does not end the audit.** A machine can have a current binary, a
healthy sweep, and a modest fleet and still stall for a minute per tool call, because none of
those measure what a spawn costs. Suspect 4 is where that lives, and it is the suspect a report
most often has to reach.

**Suspect 1. Accumulated install-tree state.** Evidence: `tree_census.walk_seconds` and
`total_files` (the sweep pays roughly this walk daily; minutes here means minutes of background
I/O after the first launch of the day), `settings-unparsable-pauses-sweep` (the sweep has been
silently OFF. Nothing was cleaned for as long as that error existed), `history.mb` and
`home_root_state` sizes (unmanaged, grow forever). `last-cleanup-stale` is weaker evidence than it
looks: the sweep defers while sessions are active, so a stale sentinel on a busy machine has a
benign explanation. Report both readings.

**Suspect 2. Version regression.** Evidence: `cli.version` against the bundled
[reference/known-performance-issues.md](reference/known-performance-issues.md). Several 2.1.2xx
releases fixed quadratic long-session slowdowns, per-turn CPU regressions, and keystroke lag, so
an out-of-date binary is a complete alternative explanation. Always capture the version *before*
any reinstall; after one, the confound is permanent. Cross-check current symptoms via
`/claude-ops:known-issues` when it is installed; otherwise search the upstream issue tracker
directly.

**Suspect 3. Component bloat.** Evidence: `plugin_fleet` counts and `processes`. Community-
confirmed slowness causes cluster here (many MCP servers/plugins each add per-tool-call and
startup cost). This report only counts; the enablement-and-scope verdict belongs to
`/claude-ops:plugins audit`. Tell the user to run it rather than eyeballing.

**Suspect 4, the fan-out layer.** What the machine pays per spawn, multiplied by everything that
spawns. Read `fan_out` in this order:

1. **`fan_out.spawn_cost`** first, because every other number in this section is denominated in
   it. A no-op spawn is the floor a hook, a statusline render, and a subagent each pay before
   doing any work of their own. The floor MOVES WITH LOAD, so read `min_ms` together with
   `concurrent_processes_at_sample` and never quote one without the other. `slow-spawn-floor`
   means the machine is contended before Claude Code does anything; `bimodal-spawn-latency`, a
   wide spread whose slow mode is itself slow, IS the contention diagnosis rather than a hint
   toward one.
2. **`fan_out.hooks`**. `per_tool_call.count` scales with tool-call volume; `per_turn.count` is
   what makes a long conversation degrade and is the bucket most audits never look at.
   `invocation_shape_findings` names hooks paying extra process creations before their own work
   starts. **Never present hook cost as a sum**: hooks on one event run in parallel, so the
   wall-clock cost is roughly the slowest hook plus contention, and adding them up can overstate
   the total several times over.
3. **`fan_out.config_liveness`** before attributing any cost to configuration. Claude Code reads
   plugin enablement at startup, so `sessions_predating_settings` greater than zero means the
   file on disk does not describe what is running: a plugin toggled off an hour ago can still
   have every one of its hooks live. Reporting the disk state as the running state is how a
   confident and wrong diagnosis gets written. The advisory says restart is required; that
   restart is the operator's, not this skill's.
4. **`fan_out.concurrency_ceilings`**. Spawn depth multiplies against the per-session concurrency
   limit, and every subagent carries the same statusline and hook fan-out as its parent, so two
   individually modest settings can license a very large population. Report effective values
   against documented defaults. **Never advise setting one of these to 0**: they are read through
   a truthiness test on the raw string, the string `"0"` is truthy, and only removing the
   variable disables it.
5. **`fan_out.statusline`**. Reported, never rendered. `refresh_interval_seconds` is in SECONDS
   with a documented minimum of 1; reading it as milliseconds inverts the conclusion.
6. **`processes.orphan_attribution`**. Only a dead-parent process is an orphan. A long-lived
   process with a live parent is working software and killing it breaks whatever owns it, so
   report `parent_alive` per candidate and treat `unknown` as unknown. `processes.population`
   separates accumulation from churn across two samples; one sample cannot tell them apart, and a
   count that holds while pids turn over is churn.

Cross-cutting: `sessions.active_last_hour` (concurrent sessions multiply watcher and I/O load),
`sessions.largest_transcript` (a very large live transcript in a resumed session grows the
per-keystroke render cost), and every entry in `timings_seconds` (a slow phase names a slow
subsystem).

## Gotchas

- **Do not convert this audit into a cleanup.** The single most tempting wrong move is "the tree
  is big, delete it." Big is not the finding. *unswept* is. A healthy sweep bounds the tree by
  itself; route a paused sweep to `/claude-config:audit` (settings fix), invoked via the Skill tool, and tell the user to run
  `/disk-hygiene:clean` for unmanaged leftovers.
- **A number alone never convicts.** 100k files with `walk_seconds: 4` on an excluded NVMe volume
  is healthy; 20k files with `walk_seconds: 90` behind a scanning filter driver is the problem.
  Pair counts with timings in every claim.
- **The report is capture-at-moment tooling.** Run it while slow. A report captured after a
  restart mostly measures a healthy machine and supports no conclusion about the incident.
- **`quiesced: false` always.** Counts drift while the engine walks a live tree; report ranges of
  confidence, not false precision.
- **Reinstalling before capturing destroys the version evidence permanently.** If the operator
  already reinstalled, say plainly that suspect 2 can no longer be tested for the past incident.
- **Never time a hook by running it.** The obvious way to attribute per-hook cost is to execute
  one and measure it, and it is the one move this skill will not make: a hook is third-party code
  with arbitrary side effects. Report the enumeration and the spawn baseline, and let the
  operator attribute.
- **A single spawn number, unlabelled by machine state, is worse than no number.** The floor
  itself moves with load, so a reading taken under a storm looks like a permanent property of the
  machine and is not one. Every quoted timing carries its `concurrent_processes_at_sample`, and a
  comparison against an earlier capture is only valid at comparable load.
- **Do not present parallel hook cost as additive.** Summing hook timings produces a number
  several times larger than the stall the operator actually observes, which then fails to match
  the symptom and discredits the whole report.
- **Config on disk is not config in force.** Check `fan_out.config_liveness` before saying a
  setting is or is not the cause. This is the failure mode that produces a confidently wrong
  report: everything looks disabled, and every one of its hooks is still running.
- **Age is not orphanhood.** Most long-lived helper processes have live parents and are doing
  their job. Convicting on age alone routes working software to a kill, so read `parent_alive`
  and leave `unknown` unresolved rather than guessing.
- **Record the negatives.** When a suspect is tested and cleared, say so and say how it was
  tested. The bundled reference carries a tested-and-cleared section for exactly this: a plausible
  cause ruled out by measurement is a finding, and the next operator should not have to re-derive
  it. Antivirus, filesystem, and shell choice have all looked like the cause and been wrong.
