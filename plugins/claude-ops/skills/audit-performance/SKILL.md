---
description: "Read-only slowness-diagnostic capture for a Claude Code installation. Run it AT THE MOMENT the machine or a session feels slow, before restarting or deleting anything. One timed engine pass captures: CLI version (the version-regression suspect), retention-sweep health including the silent unparsable-settings pause (the accumulated-state suspect), a timed stat-walk of the whole install tree whose duration approximates what the product's own daily sweep costs, home-root file sizes (stat-only), active-session and plugin-fleet counts (the component-bloat suspect), a process census, and Windows Defender guidance. Interprets against a bundled known-performance-issues reference. Reports and routes; never mutates, never deletes, never 'fixes'. Use when: 'Claude Code is slow', 'typing lags', 'my machine freezes when Claude runs', 'audit performance', 'why is this session sluggish', 'diagnose Claude slowness before I nuke anything'. Not for: deep install-tree inventory (/claude-ops:audit-install-state), deleting anything (/disk-hygiene:clean), plugin enablement verdicts (/claude-ops:plugins audit), or upstream bug lookup on its own (/claude-ops:known-issues, which this skill composes with)."
argument-hint: "[--root <path>] (defaults to $CLAUDE_CONFIG_DIR, else ~/.claude); pass the current session id via --session-id when known"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: operator
  summary: Capture slowness evidence while slow. Version, sweep health, tree walk, sessions, fleet
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
the contents of `history.jsonl` and transcript files. The engine's content-read allowlist is two
files: `settings.json` and `.last-cleanup`. Everything else is stat-only. Name, size, mtime.
**This rule is inherited by every subagent this skill dispatches; say so explicitly in any prompt
you fan out.**

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-performance/scripts/audit_performance.py" \
  --session-id "<current-session-id-if-known>" > ./claude-performance-report.json
```

Write the report **outside** the install root. Python 3.11+ is the only requirement. No
PowerShell, no third-party packages. On a machine that is currently struggling, expect the run
itself to be slow; that is signal, not failure. Report the phase timings prominently. If even
this engine cannot finish, capture `--skip-processes` first and say so.

Alongside the engine run, record what only the operator knows, in one or two sentences each: what
was slow (typing? tool calls? the whole machine?), how many terminals were open, what the session
was doing, and, on Windows, whether Task Manager showed "Antimalware Service Executable" or
disk saturation. The engine cannot see intent; the report is incomplete without this paragraph.

## Reading the report. Separate the three suspects

Lead with `sweep_health.findings`, then work the suspects in order. For each, state what the
evidence supports and what it cannot distinguish. This report is one sample, not a longitudinal
study.

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
