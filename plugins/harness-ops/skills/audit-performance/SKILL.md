---
description: "Slowness diagnostic that never 'fixes', run before restarting or deleting: version, retention sweep, install bloat, hook/subagent fan-out, kernel-leak census. Use when: 'Claude Code is slow', 'typing lags', 'my machine freezes when Claude runs', 'why is this session sluggish', 'my hooks are slowing everything down', 'too many subagents'. Upstream bugs: /harness-ops:known-issues. Stale files: /harness-ops:audit-install-state."
argument-hint: "[unattended] [--root <path>] [--session-id <id>] [--note <fact>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Capture slowness evidence while slow. Version, sweep health, tree walk, sessions, fleet, fan-out
  cadence: continuous
---

**Arguments.** `[unattended] [--root <path>] [--session-id <id>] [--note <fact>]`. `--root` defaults to `$CLAUDE_CONFIG_DIR`, else `~/.claude`; pass the current session id via `--session-id` when known, and each operator fact via a repeated `--note`. The skill consumes `unattended`: never pass it to the engine or read it as a root; under it, record the suggestion in the report instead of asking.

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
| The historical cost of these hooks over past sessions | Not this engine (Never read bars transcripts); the person asks a `/doctor` session (see Reading the report) |
| What exactly is in the install tree, and is anything stale? | `/harness-ops:audit-install-state` |
| Which plugins are enabled at which scope, and is the fleet current? | `/harness-ops:plugins audit` |
| Is this a known upstream bug? | `/harness-ops:known-issues` (compose: search the symptoms this report surfaces) |
| Delete a genuinely unmanaged leftover | `/disk-hygiene:clean` |
| Shed one project's `~/.claude.json` state | `claude purge <path>` |

## Boundary, the bundled `doctor` skill

One native Claude Code surface inspects two of this skill's four suspects, and the two get
conflated whenever a session feels slow:

- **`doctor` (bundled skill, alias `/checkup`)**: health-checks the installation and offers to
  fix what it finds, and its
  checks include slow hooks and a newer version on the release channel. It reports first and asks
  before changing anything; `claude doctor` in the terminal prints read-only diagnostics without a
  session.
- **This skill (marketplace plugin).** A timed, read-only capture taken while it is slow: engine
  phase timings, spawn baselines, per-hook buckets, and the census, with remediation routed out.

**Routing.** Capture first. This skill is capture-at-moment tooling: a report taken after the
stall ends supports no conclusion about the incident, and prepending a prerequisite adds latency
on a host that is already slow. Transcript-derived history is covered under Reading the report,
and the run-end suggestion offers `/doctor`. Prefer `claude doctor` when a session will not
start. Prefer this skill when the question is why it is slow right now: the timings, the fan-out
layer, and the retention-sweep state have no native counterpart. Its sibling `audit-install-state`
owns the deep inventory of the tree against the same surface.

**Mutation gate.** `doctor` mutates: fixing is its point. This skill's contract is report-only and
it refuses deletion, so never chain into a `doctor` fix on this skill's behalf. Surface the
finding and let the user invoke the fix.

**Availability is never assumed.** `doctor` survives the bundled-skill kill switch but an
environment variable or a `skillOverrides` entry still hides it; this section states what to do
when it resolves, never that it is present. The four-part records live in
[reference/bundled-doctor.md](reference/bundled-doctor.md).

## Never read

`.credentials.json`, `daemon/*.key`, `ide/*.lock` bodies, the values inside `~/.claude.json`, and
the contents of `history.jsonl` and transcript files. The engine's content-read allowlist is four
non-secret config files: `settings.json`, `.last-cleanup`, a plugin's `hooks/hooks.json`, and
`plugins/installed_plugins.json`. Everything else is stat-only. Name, size, mtime. The allowlist
is enforced in `read_json`, which raises rather than reading a file it does not name, so the
prose and the code cannot drift apart. On Linux the engine also reads `/proc/<pid>/status` and
`/proc/<pid>/stat`, kernel-generated text with no user content, to tell kernel threads from user
processes, enforced the same way in `read_proc_text`.

The last two entries are what makes hook enumeration possible: a hook manifest holds an event, a
matcher, and a command string, and the installed-plugins manifest holds install paths. Neither
carries credential material.

**This rule is inherited by every subagent this skill dispatches; say so explicitly in any prompt
you fan out.**

## Never execute

The engine enumerates the hooks and the statusline command that will fire; it never runs one: a
hook is third-party code with arbitrary side effects, so executing it would make the capture a
mutation. Per-hook attribution is the operator's deliberate step; the engine supplies the no-op
spawn baseline every hook pays before its own work.

`fan_out.shell_resolution` resolves which `bash.exe` the harness would hand a shell-form command
to by reading `settings.json` and the environment and stat-ing the path. No binary is spawned, and
the documented search for an unset variable is reported, not walked.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-performance/scripts/audit_performance.py" \
  --session-id "<current-session-id-if-known>" \
  --note "<one operator fact; repeat the flag per fact>" \
  --project-dir "${CLAUDE_PROJECT_DIR:-.}" > ./claude-performance-report.json
```

Pass `--project-dir` whenever a project root is known, so project-scope hooks are counted; without
it the hook inventory is a floor, not a total.

Write the report **outside** the install root. Requires Python 3.11+ only. On a struggling machine
the run itself is slow; that is signal. Report the phase timings prominently.

Escape hatches for a machine too contended for the full pass, in this order:
`--subprocess-timeout <seconds>` raises the per-probe bound (default 20 s; a probe that times out
is recorded as a finding, not dropped); `--spawn-samples <n>` and `--population-gap 0` shorten the
two wall-clock probes; `--skip-fan-out` and `--skip-processes` drop whole phases. Say which flags
you passed: each narrows what the report can conclude.

Pass what is already known through `--note`, one note per fact: what was slow (typing? tool calls?
the whole machine?), how many terminals were open, what the session was doing, and, on Windows,
whether Task Manager showed "Antimalware Service Executable" or disk saturation. Declare who
supplied them with `--note-source`; `operator_context` records `absent` for what nobody passed, so
a gap never reads as a clean bill of health.

## Reading the report. Separate the four suspects

Lead with `sweep_health.findings`, then work the suspects in order. For each, state what the
evidence supports and what it cannot distinguish. This report is one sample, not a longitudinal
study.

This engine never reads `history.jsonl` or transcript files, so it cannot report hook cost
over past sessions. A `/doctor` session can read them, so a person who wants the transcript-derived
history asks there. That is not time-sensitive: do not prepend it.

**Clearing the first three does not end the audit.** A machine can have a current binary, a
healthy sweep, and a modest fleet and still stall for a minute per tool call, because none of
those measure what a spawn costs. Suspect 4 is where that lives, and it is the suspect a report
most often has to reach.

**On Windows, read `kernel_objects` before any of them.** It is the floor the host imposes on every
process creation, and one mechanism moves it by an order of magnitude with CPU idle and memory
free: a leaked kernel reference to Token objects. `state_label: token-leak` (the finding
`token-objects-leaked`) means every spawn-denominated number below is a multiple of a broken host,
and the remediation is a reboot followed by the elevated attribution runbook in
[reference/known-performance-issues.md](reference/known-performance-issues.md), neither of which
is this skill's to run. `paged-pool-high` on its own is a different, weaker signal: the pool
figure is aggregate and unattributed, so route it to `poolmon` (elevated, operator-run) to name
the tag before anyone calls it a Token leak or a reboot. `token.objects_per_uptime_second` is a
population ratio, not a measured mint rate: it includes the boot population (so it overstates
early in a boot and the projection errs short) and cannot see churn, and it is reported because
a short in-run window under-reads bursty minting; `hours_to_leak_threshold_at_uptime_ratio` says
how long a clean boot lasts on that basis. `supported: false` names why the census could not
run; it is never silently absent.

**Suspect 1. Accumulated install-tree state.** Evidence: `tree_census.walk_seconds` and
`total_files` (the sweep pays roughly this walk daily; minutes here means minutes of background
I/O after the first launch of the day), `settings-unparsable-pauses-sweep` (the sweep has been
OFF, and `/status` warns. Nothing was cleaned for as long as that error existed), `history.mb` and
`home_root_state` sizes (unmanaged, grow forever). `last-cleanup-stale` is weaker evidence than it
looks: the sweep defers while sessions are active, so a stale sentinel on a busy machine has a
benign explanation. Report both readings.

**Suspect 2. Version regression.** Evidence: `cli.version` against the bundled
[reference/known-performance-issues.md](reference/known-performance-issues.md). Several 2.1.2xx
releases fixed quadratic long-session slowdowns, per-turn CPU regressions, and keystroke lag, so
an out-of-date binary is a complete alternative explanation. Always capture the version *before*
any reinstall; after one, the confound is permanent. Cross-check current symptoms via
`/harness-ops:known-issues` when it is installed; otherwise search the upstream issue tracker
directly.

**Suspect 3. Component bloat.** Evidence: `plugin_fleet` counts and `processes`. Community-
confirmed slowness causes cluster here (many MCP servers/plugins each add per-tool-call and
startup cost). This report only counts; the enablement-and-scope verdict belongs to
`/harness-ops:plugins audit`. Tell the user to run it rather than eyeballing.

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
   `invocation_shape_findings` names three shapes: `git-bin-bash-wrapper-costs-an-extra-spawn`
   and `nested-shell-invocation`, each an extra process creation before the hook's own work
   starts, and `shell-form-hook-names-a-second-shell`, a shell-form command that spells a shell
   inside the shell the harness has already wrapped the string in. **An empty list does not mean
   the hooks run un-nested.** A shell-form command is handed to a shell whatever it names, so a
   row with no finding still pays one wrapping shell; the list names only the rows that add a
   second, and its command-position rule is a floor, so a shell reached through a position the
   rule does not cover is missed rather than reported: a subshell (`$(bash x.sh)` or a
   backquoted one) and a runner taking arguments of its own first (`timeout 5 bash x.sh`) are
   examples, not a closed list: `xargs bash x.sh` and `find . -exec sh {} \;` miss for the same
   reason. It errs the other way too: a shell named in a trailing comment (`./x.sh # ; bash`)
   is reported, because comments are not parsed, and so is a `<tool> exec <shell>` form
   (`docker exec bash`, `npm exec sh`), because `exec` grants command position without knowing
   whose subcommand it is. Confirm a row against its own manifest before acting on it. The
   command-position rule honors quotes: a quoted executable containing spaces
   (`"C:/Program Files/PowerShell/7/pwsh.exe" -File hook.ps1`) stays one token and is
   recognized, and a shell operator inside a quoted argument (`grep -e 'a|sh' f`) is not read
   as a delimiter. The two LEGACY findings still flatten quotes and read their own token
   list, unchanged on every input. A row spelling an explicit `"args": []` is exec form and reports
   no second shell; a row that omits the key is shell form.
   Which bash pays the wrapping spawn is item 3. `per_tool_call.count` is the
   registered-row ceiling, so read `by_matcher` and
   `projection` beside it for what one tool call of a given shape actually spawns, and
   `unclassified_rows` for the `if` gates the engine could not decide and therefore counted as
   firing. Each projection row carries a `floor` (rows known to fire) and a `ceiling` (the
   floor plus `fire_always_unclassified`); quote the pair, never the ceiling alone, as the
   count one edit spawns. **Never present hook cost as a sum**: hooks on one event run in parallel, so the
   wall-clock cost is roughly the slowest hook plus contention, and adding them up can overstate
   the total several times over. To find which hook is the wall on `Stop`, point the operator at
   the `stop_hook_summary` durations named under "Never time a hook by running it" in Gotchas;
   a per-turn bucket counts the costliest hook as one row among many. We treat shell form as
   always wrapped in a shell and exec form, with `args` present, as spawned with none; which
   shell wraps a row per OS, and the `shell` field's values, are read live.
   - **Pointer**: when naming the wrapping shell, fetch
     [hooks: exec form and shell form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form)
     live. **As of**: 2026-10-11. **Recheck trigger**: that section changes which shell wraps
     shell form, or `args` gains a no-shell variant for shell form.
3. **`fan_out.shell_resolution`**, which names WHICH bash pays that wrapping spawn on Windows:
   `CLAUDE_CODE_GIT_BASH_PATH`, where the value came from, whether the path exists, whether
   Claude Code accepts the filename, and whether it resolves to Git's `bin` launcher or to
   `usr/bin/bash.exe`. A rejected filename and a path that does not exist get the SAME documented
   fallback, so a `resolves_to` shown beside either finding names a binary the harness will not
   use. Unset, Claude Code searches for `bash.exe` itself; this block reports the engine's copy of
   that search and never performs it.
   - **Pointer**: when stating the search order, the accepted filenames, or the fallback, fetch
     [troubleshoot install: Git for Windows or PowerShell](https://code.claude.com/docs/en/troubleshoot-install#claude-code-on-windows-requires-either-git-for-windows-for-bash-or-powershell)
     live. **As of**: 2026-10-11. **Recheck trigger**: that section's resolution order,
     accepted-name list, or fallback changes.

   The
   `bin` launcher's re-exec of `usr/bin/bash.exe` rides in `observation` as a one-host
   observation with its provenance, never as a count this engine asserts. The block answers
   only for rows the harness wraps with bash, and only from the install-root `settings.json`:
   a hook whose own `shell` field is `"powershell"`, or a Windows host with no Git Bash
   installed, has PowerShell wrap that row and no `bash.exe` resolved for it, and a project or
   local `.claude/settings.json` `env` that outranks the install root is not read here.
4. **`fan_out.config_liveness`** before attributing any cost to configuration. Claude Code reads
   plugin enablement at startup, so `sessions_predating_settings` greater than zero means the
   file on disk does not describe what is running: a plugin toggled off an hour ago can still
   have every one of its hooks live. Reporting the disk state as the running state is how a
   confident and wrong diagnosis gets written. The advisory says restart is required; that
   restart is the operator's, not this skill's.
5. **`fan_out.concurrency_ceilings`**. Spawn depth multiplies against the per-session concurrency
   limit, and every subagent carries the same statusline and hook fan-out as its parent, so two
   individually modest settings can license a very large population. Report effective values
   against documented defaults. **Never present any value, or removing the variable, as
   disabling either cap**; read what a value does, and where a cap is not enforced, from the
   pointer. The engine's `trap` string beside them describes only the truthiness-gated observer
   flag and says removing that variable disables it; never relay it for the caps. Rewording it
   is left undone because `scripts/test_audit_performance.py:910` pins that text.
   - **Pointer**: when judging what a cap value does or where it is not enforced, fetch
     [sub-agents: concurrent subagent limit](https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit),
     [sub-agents: let subagents spawn their own subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents),
     and the two variables' rows in
     [env-vars: variables](https://code.claude.com/docs/en/env-vars#variables) live. **As of**:
     2026-10-11. **Recheck trigger**: any of those changes the values a cap accepts, documents a
     way to disable a cap, or adds or drops a session kind that is exempt from one.
6. **`fan_out.statusline`**. Reported, never rendered. The engine reads `refreshInterval` as
   seconds (`refresh_interval_seconds`); reading it as milliseconds inverts the conclusion. Its
   `invocation_shape_findings` reads the same way as item 2: the command runs in a shell, so a
   command naming a shell puts at least two shells in the chain.
   - **Pointer**: when checking the interval's unit and minimum or the shell it runs in, fetch
     [statusline: manually configure a status line](https://code.claude.com/docs/en/statusline#manually-configure-a-status-line)
     live. **As of**: 2026-10-11. **Recheck trigger**: that section changes the interval's unit
     or which shell runs the command.
7. **`processes.orphan_attribution`**. Only a dead-parent process is an orphan. A long-lived
   process with a live parent is working software and killing it breaks whatever owns it, so
   report `parent_alive` per candidate and treat `unknown` as unknown. `dead_parent_any_age`,
   beside that verdict, is a census and not a kill list: one row per name (`name`, `count`,
   `youngest_h`, `oldest_h`, `cpu_seconds`) for a process in the orphan candidate set, or named
   `tail.exe`, `grep.exe`, `sleep.exe`, `cat.exe`, `rm.exe`, or `du.exe`, whose parent is gone
   or whose parent pid was recycled, and which is older than 5 seconds. `count` is every such
   process of that name; `cpu_seconds` is their summed kernel plus user time, `null` when any
   member's time is unreadable. `dead_parent_by_cpu` drops the name list: every dead-parent
   process of any name under the same rules, ranked by CPU, top 10, each row `name`, `pid`,
   `age_h`, `cpu_seconds`, and `cpu_share` (CPU seconds over age; above 1.0 means more than one
   core). It is a ranking, not a kill list, and a high `cpu_share` there is the first thing to
   report: a detached process burning CPU after its parent exited slows the whole machine at any
   age, well inside the 24-hour orphan floor.
   A census process whose parent start time is unreadable is no row; it is counted in
   `dead_parent_any_age_unknown_count`, while the verdict's `unknown_count` holds only its
   own 24-hour candidates. The 24-hour orphan floor and the orphan candidate set are
   unchanged, and a census row is not a process to kill. The census, its unknown count, and the
   CPU ranking are `null` off Windows, which is not measured rather than none found: Linux, macOS, and
   WSL reparent an orphan to a live init or subreaper, so the process table cannot show its
   dead parent. The orphan verdict reads the same table, so off Windows (`orphans_note` says
   so) `orphan_count: 0` is not a negative to record, and a `live_parent` row whose parent is
   init, launchd, or a subreaper is unresolved rather than working software.
   `processes.population` separates accumulation from churn across two samples; one sample
   cannot tell them apart, and a count that holds while pids turn over is churn.

Cross-cutting: `sessions.active_last_hour` (concurrent sessions multiply watcher and I/O load),
`sessions.largest_transcript` (a very large live transcript in a resumed session grows the
per-keystroke render cost), and every entry in `timings_seconds` (a slow phase names a slow
subsystem).

## Run-end suggestion

Relay the sentence below to the user and do not run `/doctor` yourself: it is reserved for the person to run.

If /doctor is available in your session (claim: `/doctor` is reserved for the person to run, `DISABLE_DOCTOR_COMMAND` or a `skillOverrides` entry hides it, and it survives `disableBundledSkills`; basis: the `/doctor` row on the commands reference and the bundled-skills section of the skills reference, both fetched 2026-09-29, and the 2.1.263 binary registering it as model-invocation-disabled on 2026-09-11; as of 2026-09-29; recheck: either page drops that gate, or a release lets the model invoke it), run it for the quick health-and-fix pass this timed capture does not perform.

**`unattended`:** record the suggestion in the report's final section; do not ask.

## Gotchas

- **Do not convert this audit into a cleanup.** Big is not the finding; *unswept* is. A healthy
  sweep bounds the tree by itself; route a paused sweep to `/harness-config:audit` (settings fix),
  invoked via the Skill tool, and tell the user to run `/disk-hygiene:clean` for unmanaged
  leftovers.
- **A number alone never convicts.** 100k files with `walk_seconds: 4` on an excluded NVMe volume
  is healthy; 20k files with `walk_seconds: 90` behind a scanning filter driver is the problem.
  Pair counts with timings in every claim.
- **Run it while slow.** A report captured after a restart supports no conclusion about the
  incident.
- **`quiesced: false` always.** Counts drift while the engine walks a live tree; report ranges, not
  false precision.
- **Reinstalling before capturing destroys the version evidence permanently.** If the operator
  already reinstalled, say plainly that suspect 2 can no longer be tested for the past incident.
- **Never time a hook by running it** (see Never execute). Report the enumeration and the spawn
  baseline, and let the operator attribute. The harness has already timed the Stop hooks that ran:
  a `stop_hook_summary` record in the session transcript carries `hookCount` and a `hookInfos`
  array of `{"command", "durationMs"}`, one entry per hook. The skill still never reads a
  transcript, so name the route and hand the operator a filter that extracts those records alone,
  for example
  `jq -c 'select(.subtype == "stop_hook_summary") | .hookInfos' <session>.jsonl`. Claim: the
  record and its fields are observed harness behavior, not documented, so treat the shape as
  unstable; basis: 41 such records in one session supplied every per-hook duration an audit
  produced, and [hooks](https://code.claude.com/docs/en/hooks.md) contains neither
  `stop_hook_summary` nor `durationMs`; verified 2026-09-27; recheck when the hooks page
  documents a per-hook timing record, or when a filtered transcript returns no
  `stop_hook_summary` record in a session whose Stop hooks ran.
  For other events' hooks, filter to the timing fields:
  `jq -c 'select(.type == "attachment") | .attachment | select(.type == "hook_success" or .type == "hook_non_blocking_error") | {hookEvent, hookName, command, durationMs}' <session>.jsonl`.
  `/harness-ops:observability hooks <session>.jsonl` reads both shapes and owns the record of
  their keys and stability.
- **Label every spawn number with machine state.** The floor moves with load: every quoted timing
  carries its `concurrent_processes_at_sample`, and a comparison against an earlier capture is
  valid only at comparable load.
- **A slow spawn floor at idle CPU with the four suspects clear is the host, not the fan-out
  layer.** On Windows check `kernel_objects` before writing up `slow-spawn-floor`: a Token-object
  leak can produce seconds per process creation at low CPU that a reboot clears. Report the leak,
  route the reboot and the attribution to the operator, and do not let the fan-out numbers carry
  the diagnosis.
- **Do not present parallel hook cost as additive.** Summing hook timings overstates the stall the
  operator observes several times over.
- **Config on disk is not config in force.** Check `fan_out.config_liveness` before saying a
  setting is or is not the cause: everything can look disabled while its hooks still run.
- **Age is not orphanhood.** Read `parent_alive`, and leave `unknown` unresolved rather than
  guessing; most long-lived helpers have live parents.
- **Record the negatives.** When a suspect is tested and cleared, say so and how, as the bundled
  reference's tested-and-cleared section does. Antivirus, filesystem, and shell choice have each
  looked like the cause and been wrong.
