---
description: "Slowness diagnostic that never 'fixes', run while Claude Code is slow, before restarting or deleting: version, retention sweep, install bloat, hook and subagent fan-out, and a Windows kernel-leak census. Use when: 'Claude Code is slow', 'typing lags', 'my machine freezes when Claude runs', 'audit performance', 'why is this session sluggish', 'diagnose Claude slowness before I nuke anything', 'my hooks are slowing everything down', 'too many subagents'. Upstream bugs: /claude-ops:known-issues."
argument-hint: "[unattended] [--root <path>] [--session-id <id>] [--note <fact>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: operator
  summary: Capture slowness evidence while slow. Version, sweep health, tree walk, sessions, fleet, fan-out
  cadence: continuous
---

**Arguments.** `[unattended] [--root <path>] [--session-id <id>] [--note <fact>]`. The token `unattended` is consumed by the skill, is never passed to the engine script and never read as a root path; under it the suggestion is recorded in the report instead of asked. Full form: [unattended] [--root <path>] (defaults to $CLAUDE_CONFIG_DIR, else ~/.claude); pass the current session id via --session-id when known, and each operator fact via a repeated --note

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
| The historical cost of these hooks over past sessions | Not this engine: its Never-read rule bars transcripts. A `/doctor` session can read them, so the person asks there (see Reading the report) |
| What exactly is in the install tree, and is anything stale? | `/claude-ops:audit-install-state` |
| Which plugins are enabled at which scope, and is the fleet current? | `/claude-ops:plugins audit` |
| Is this a known upstream bug? | `/claude-ops:known-issues` (compose: search the symptoms this report surfaces) |
| Delete a genuinely unmanaged leftover | `/disk-hygiene:clean` |
| Shed one project's `~/.claude.json` state | `claude project purge <path>` |

## Boundary, the bundled `doctor` skill

One native Claude Code surface inspects two of this skill's four suspects, and the two get
conflated whenever a session feels slow:

- **`doctor` (bundled skill, alias `/checkup`).** Ships with Claude Code rather than as a
  marketplace plugin. It health-checks the installation and offers to fix what it finds, and its
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

The engine enumerates the hooks and the statusline command that will fire; it never runs one.
A hook is third-party code with arbitrary side effects, so timing one by executing it would turn
a read-only capture into a mutation, and a `PreToolUse` hook run outside a tool call may not even
be idempotent. Per-hook attribution is the operator's step, taken deliberately and with the
consequences understood. What the engine supplies for it is the no-op spawn baseline every hook
pays before doing any work of its own.

`fan_out.shell_resolution` resolves WHICH `bash.exe` the harness would hand a shell-form command
to, and it does so by reading `settings.json` and the environment and stat-ing the path. Neither
binary is spawned, and the documented search for an unset variable is reported rather than
walked.

## Run it

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/audit-performance/scripts/audit_performance.py" \
  --session-id "<current-session-id-if-known>" \
  --note "<one operator fact; repeat the flag per fact>" \
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

Pass what is already known through `--note`, one note per fact: what was slow (typing? tool calls?
the whole machine?), how many terminals were open, what the session was doing, and, on Windows,
whether Task Manager showed "Antimalware Service Executable" or disk saturation. Declare who
supplied them with `--note-source`, and let `operator_context` record `absent` for what nobody
passed, because the engine cannot see intent and a silent gap reads like a clean bill of health.

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
   firing. **Never present hook cost as a sum**: hooks on one event run in parallel, so the
   wall-clock cost is roughly the slowest hook plus contention, and adding them up can overstate
   the total several times over. To find which hook is the wall on `Stop`, point the operator at
   the `stop_hook_summary` durations named under "Never time a hook by running it" in Gotchas;
   a per-turn bucket counts the costliest hook as one row among many. Claim: shell form passes the `command` string to a shell,
   `sh -c` on macOS and Linux, Git Bash on Windows, PowerShell when Git Bash is absent, or the
   shell a hook's own `shell` field names, while exec form, with `args` present, spawns the
   executable directly with no shell
   ([hooks](https://code.claude.com/docs/en/hooks.md), verified 2026-09-20; recheck when that
   page's shell-form paragraph changes, when the `shell` field's accepted-value list changes,
   or when `args` gains a documented no-shell variant for shell form).
3. **`fan_out.shell_resolution`**, which names WHICH bash pays that wrapping spawn on Windows:
   `CLAUDE_CODE_GIT_BASH_PATH`, where the value came from, whether the path exists, whether
   Claude Code accepts the filename, and whether it resolves to Git's `bin` launcher or to
   `usr/bin/bash.exe`. A rejected filename and a path that does not exist get the SAME documented
   fallback, so a `resolves_to` shown beside either finding names a binary the harness will not
   use. Unset, Claude Code looks for `bash.exe` in two documented steps, the default install
   locations first and the `git` on `PATH` second, taking `bash.exe` from that installation's
   `bin` directory;
   this block reports that search and never performs it
   ([troubleshoot-install](https://code.claude.com/docs/en/troubleshoot-install), verified
   2026-09-20; recheck when that section's resolution order or accepted-name list changes). The
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
   against documented defaults. **Never advise setting one of these to 0**: they are read through
   a truthiness test on the raw string, the string `"0"` is truthy, and only removing the
   variable disables it.
6. **`fan_out.statusline`**. Reported, never rendered. `refresh_interval_seconds` is in SECONDS
   with a documented minimum of 1; reading it as milliseconds inverts the conclusion. Its
   `invocation_shape_findings` reads the same way as item 2: the command runs in a shell, Git
   Bash on Windows when Git Bash is installed and PowerShell when it is absent, so a command
   naming a shell puts at least two shells in the chain
   ([statusline](https://code.claude.com/docs/en/statusline.md), verified 2026-09-20; recheck
   when either of that page's shell sentences changes).
7. **`processes.orphan_attribution`**. Only a dead-parent process is an orphan. A long-lived
   process with a live parent is working software and killing it breaks whatever owns it, so
   report `parent_alive` per candidate and treat `unknown` as unknown. `processes.population`
   separates accumulation from churn across two samples; one sample cannot tell them apart, and a
   count that holds while pids turn over is churn.

Cross-cutting: `sessions.active_last_hour` (concurrent sessions multiply watcher and I/O load),
`sessions.largest_transcript` (a very large live transcript in a resumed session grows the
per-keystroke render cost), and every entry in `timings_seconds` (a slow phase names a slow
subsystem).

## Run-end suggestion

Relay the sentence below to the user and do not run `/doctor` yourself: it is reserved for the person to run.

If /doctor is available in your session (claim: `/doctor` is reserved for the person to run, `DISABLE_DOCTOR_COMMAND` or a `skillOverrides` entry hides it, and it survives `disableBundledSkills`; basis: the `/doctor` row on the commands reference and the bundled-skills section of the skills reference, both fetched 2026-09-29, and the 2.1.263 binary registering it as model-invocation-disabled on 2026-09-11; as of 2026-09-29; recheck: either page drops that gate, or a release lets the model invoke it), run it for the quick health-and-fix pass this timed capture does not perform.

**`unattended`:** record the suggestion in the report's final section; do not ask.

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
  operator attribute. The harness has already timed the Stop hooks that ran: a
  `stop_hook_summary` record in the session transcript carries `hookCount` and a `hookInfos`
  array of `{"command", "durationMs"}`, one entry per hook. Reading it executes nothing. The
  skill still never reads a transcript, so name the route and hand the operator a filter that
  extracts those records alone, for example
  `jq -c 'select(.subtype == "stop_hook_summary") | .hookInfos' <session>.jsonl`. Claim: the
  record and its fields are observed harness behavior, not documented, so treat the shape as
  unstable; basis: 41 such records in one session supplied every per-hook duration an audit
  produced, and [hooks](https://code.claude.com/docs/en/hooks.md) contains neither
  `stop_hook_summary` nor `durationMs`; verified 2026-09-27; recheck when the hooks page
  documents a per-hook timing record, or when a filtered transcript returns no
  `stop_hook_summary` record in a session whose Stop hooks ran.
- **A single spawn number, unlabeled by machine state, is worse than no number.** The floor
  itself moves with load, so a reading taken under a storm looks like a permanent property of the
  machine and is not one. Every quoted timing carries its `concurrent_processes_at_sample`, and a
  comparison against an earlier capture is only valid at comparable load.
- **A slow spawn floor at idle CPU with the four suspects clear is the host, not the fan-out
  layer.** On Windows check `kernel_objects` before writing up `slow-spawn-floor`: 1.4 to 4 s per
  creation at 7% CPU was a Token-object leak, suspending the busiest shells moved it 15%, and a
  reboot took it to 14 ms. Report the leak, route the reboot and the attribution to the operator,
  and do not let the fan-out numbers carry the diagnosis.
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
