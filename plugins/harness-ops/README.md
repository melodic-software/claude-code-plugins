# harness-ops

## Contents

- [Skills](#skills)
- [The audit hooks](#the-audit-hooks)
- [Install](#install)
- [How the skills adapt to your repo](#how-the-skills-adapt-to-your-repo)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [License](#license)

A Claude Code plugin for running Claude Code well over time. One cohesive
capability across sixteen skills and a family of telemetry-emitter hooks, including diagnosing why
most of an installed skill fleet never gets used.
audit-native-overlap maps native Claude Code surfaces against the current
repo's own components so a custom skill never silently duplicates what the
product now ships.
audit-install-state reports on the machine-scope `~/.claude` install directory
itself. audit-performance captures slowness evidence at the moment a machine or
session feels slow so the cause is diagnosed instead of nuked, including the
fan-out layer of hooks, statusline, spawn cost, and subagent concurrency.
observability reads what your sessions actually did. known-issues tracks what
upstream has broken, and changelog integration keeps your repo current with what
upstream has shipped. The plugins skill keeps your own plugin fleet current,
morning-brief prints your read-only operator morning view, and lanes launches and
manages your loop lanes as background sessions. A
re-runnable `setup` action settles where the known-issues registry lives,
and the `*-audit` hooks feed observability with per-hook execution telemetry
Claude Code's native OTEL cannot see.

## Skills

| Skill | What it does |
|---|---|
| `/harness-ops:audit-skill-visibility` | Audits whether the model can actually **see** each installed skill, the question behind "why does most of my fleet never get used?", since a skill the model cannot see can never be chosen. Reports three independent things per skill: **reachability** (visible, `user-only` by design, hidden by an override or disabled plugin, or invisibly misconfigured), **observation** (what usage was actually recorded, always horizon-qualified), and **starvation** (whether it is losing the description-budget contest: Claude Code drops descriptions starting with the skills you invoke least, so an unused skill loses the keywords a request would match and stays unused). Whether the listing overflows is computed from documented settings; which particular skills lose their descriptions is a labeled likelihood band, never an exact cutoff. Withholds every cold verdict the data cannot support instead of reporting absence of data as absence of use. Read-only. |
| `/harness-ops:audit-install-state` | Read-only audit of the machine-scope Claude Code installation directory, the `~/.claude` tree plus the home-root `~/.claude.json`. Inventories every file (entries labeled as an authored surface or a rolled-up bulk tree, with the complete per-file rows in a CSV artifact), separates what Claude Code's own `cleanupPeriodDays` sweep already manages from what nothing manages, resolves what each number in a filename actually *is* before attempting any process-liveness lookup, and deny-lists any subtree holding a revert ledger before classifying anything as stale. Never deletes; hands off to `claude purge` and `/disk-hygiene:clean`. |
| `/harness-ops:audit-native-overlap` | Maps native Claude Code surfaces, built-in CLI commands, bundled skills, plugin-backed built-ins, session-provided skills, against the current repo's plugin skills and agents. Bare invocation is a read-only overlap report (candidates with evidence, detection integrity floors carried through, and a shared-listing-budget exposure section); verdicts (`prefer-native` / `prefer-ours` / `complementary` / `superseded` / `defer`) are human-gated in a committed store (`docs/native-surfaces/records.json`) rendered into a generated registry (`docs/native-surfaces.md`) whose every row carries an observable recheck trigger; only an explicit `apply` step bakes presence-gated native references into component descriptions and Boundary sections. |
| `/harness-ops:audit-performance` | Read-only slowness-diagnostic capture, run at the moment the machine or a session feels slow, before restarting or deleting anything. One timed engine pass separates four documented suspects: accumulated install-tree state, version regression, component bloat, and the fan-out layer, plus on Windows a kernel-object census that names the host-level Token-object leak beneath all four. Each suspect's evidence and verdict routing is documented in the skill. Phase timings are first-class evidence; content reads are allowlisted to four non-secret config files (`settings.json`, `.last-cleanup`, `hooks.json`, `installed_plugins.json`), so `~/.claude.json` and `history.jsonl` stay stat-only. Reports and routes; never mutates, never elevates, and never executes a discovered hook or statusline command. |
| `/harness-ops:observability` | Reads locally captured Claude Code telemetry, OTEL DuckDB store, machine-owned collector, optional Aspire dashboard, hook-event JSONL, ccusage, and renders cross-session trend reports (`session`/`day`/`week`/`month`/`since:`/`all` scopes). Read-only except the explicit `clean` action, which prunes the JSONL log and OTEL store by age. |
| `/harness-ops:known-issues` | Searches known Claude product GitHub bugs before you build on a feature, checks service health and model quality, and maintains a persistent registry of tracked issues (what they block, workarounds, follow-ups when fixed). Actions: `status` (default), `search`, `check-all`, `scan`, `list`, `quality`, `create`. |
| `/harness-ops:changelog` | Ingests Claude Code changelog entries and integrates them into the current repo: `fetch` (read-only display), `diff` (decision rows by owner surface and action lens over a release range, no edits), `status` (the read marker from the repo's Claude Code ledger, the default range to the newest release, and the replay cap), and `apply` (executes the decisions in scope one PR per owner plugin, hands larger ones off as work items, then runs a native-surface drift pass that files work items for new overlap candidates, fired store triggers, and a degraded or broken inventory; explicit user intent only). |
| `/harness-ops:behavior-probes` | Runs live probes of Claude Code platform behavior (permission rules, auto mode, hooks, worktrees, subagent caps, sandbox) as data-driven cases, each negative case with a paired positive control, and gives each a pass, fail or inconclusive verdict stamped with the Claude Code version. `--dry-run` (the default) runs every scaffold against a fake `claude` and costs nothing; a live run is opt-in and capped per case and per suite. `recheck` lists the cases a changelog range touches. Outcomes are recorded in the skill's `records.md`. |
| `/harness-ops:plugins` | Brings a machine's plugin fleet current on demand: marketplace refresh, updates for the plugins that actually load (including in-repo project/local-scope installs), new-catalog-plugin install per policy, and scope-divergence detection. Actions: `sync` (default, CLI-mediated mutations only), `audit` (read-only dry run), `converge` (the one action that can touch a committed `.claude/settings.json`. Previews and confirms per plugin first). |
| `/harness-ops:morning-brief` | Prints the read-only, `gh`-based operator morning view for the current repo in one pass: open counts per queue label (`needs-triage`, `status: ready`, `status: needs-decision`, `needs-human`), the gh-native merge-ready PR list (non-draft + `mergeStateStatus=CLEAN`, with a clean PR whose head is behind its base marked `UNVERIFIED`), parked `status: needs-decision` issues with their RECOMMENDED lines, and loop-lane telemetry freshness (per-lane `last-cycle` age + `flags:`). Never mutates anything; the authoritative PR merge gate stays `/source-control:babysit-prs`. |
| `/harness-ops:lanes` | Starts, restarts, stops, and reports loop lanes as named background Claude Code sessions seeded from canonical prompt files. `start` (default) / `restart` pull the repo and refresh the plugin marketplace, then launch each configured lane (`claude --bg -n <lane> --permission-mode auto`, plus `--permission-prompts none` on CLI 2.1.259 or later) with its per-lane `model`/`effort`; `status` shows per-lane running state and live sessionId; `stop` ends a lane via `claude stop`; `consume-restarts` is the OS-schedulable restart-request consumer. It reads each configured lane's telemetry `restart_request` and relaunches the stopped lanes that asked, through the same launcher (#1653). Acts only on sessions whose name is a configured lane. Lanes come from a JSON config (`--config`, else `$HARNESS_OPS_LANES_CONFIG`, else `<repo>/.work/lanes/lanes.json`, with a temporary default-only fallback to the pre-move `<repo>/.work/lanes.json` under a deprecation warning); config and prompts live in the reserved `lanes/` concern home under a hardcoded `.work` root, which is a sanctioned placement but still session-local, so a durable cross-machine home stays #480's job. |
| `/harness-ops:check` | Read-only check that `node` and `jq` resolve for the hooks, with the install route for a missing tool. Model-invocable; never installs. |
| `/harness-ops:machine-profile` | Discovers this machine's facts and identity domains (each tree's git include, `gh` directory and verdicts), stores them as a re-runnable profile that records the observation behind every value, and reports drift between the stored profile and the host now. Actions: `profile` (default), `diff`, `explain <key>`, `apply --option <key>`. Read-only unless the operator confirms a write: `record --confirm` writes the profile document, and `apply --confirm` prints what to hand to each setup and writes nothing. Never installs and never reapplies a stored value on its own. Design: [machine-profile-design](https://github.com/melodic-software/claude-code-plugins/blob/038c2ae22c23f60500b339fd2f66e4569ecbe2fd/docs/specs/machine-profile-design.md). |
| `/harness-ops:setup` | `check` reports the effective known-issues-registry, skill-usage-log and hook-log-root destinations, their defaults, path containment, the hook log root's self-ignoring guard, and retired conventions (`retirements.yaml`), and prints the guidance for routing personal option changes through Claude Code's plugin configuration prompt; `apply` writes exactly one file, the guard inside the hook log root, and runs the gated retirement cleanup. |

## The audit hooks

Eight advisory `*-audit` hooks, registered as nine rows because
`skill-usage-audit` has two producers, emit the marketplace
[hook-telemetry envelope](../../docs/conventions/hook-telemetry/README.md). One
JSON event per run carrying that hook's own `duration_ms`, outcome, and a
privacy-safe subject. Each is independently toggleable via its own `userConfig`
boolean (default **on**; see [Per-hook kill switches](#per-hook-kill-switches)).

Three scripts serve those nine rows. `hooks/audit-event-emitter.sh` carries
seven of them and picks the row from the payload's `hook_event_name`, the way
`session-event-log.sh` next to it serves 28 events from one file; the
seven events are distinct, so the event alone selects the row. Each row still
reads its own `<name>_enabled` switch and emits the same telemetry `hook` id,
`hook_event`, `status` and `data` fields it emitted as a standalone script, so
no downstream reader can tell the difference. The two rows with earned behavior
of their own keep their files: `skill-usage-audit.sh`, whose kill switch is
inlined above its library `source` because it sits on the hot `PostToolUse`
path, and `hook-failure-audit.sh` (below).

The [hook budget](../../docs/conventions/hook-budget/README.md) is accounted per
`hooks.json` entry, and the collapse changes no entry: the same nine audit rows,
on the same events, with the same matchers, and one event still spawns exactly
one process. Per-entry cost is unchanged for an enabled row (the same library,
the same `jq` passes, plus one bash pattern match to read the event) and lower
when every switch is off, because the emitter reads all seven switches before it
parses the library. A row that is off on its own pays one buffered payload it
did not pay before, because the row is only known once the event has been read;
it parsed the same library then as now, and no extra process runs either way.

The six pure emitter rows are a no-op until a consumer wires a sink (below);
`skill-usage-audit` is one exception. Both its producers also write the shared
`skill-usage.jsonl` second store unconditionally (disable the whole feature with
`skill_usage_audit_enabled=false`; pick the store's home with `skill_usage_scope`
and `skill_usage_dir`). In the default repo scope the store dir is kept out of
`git status` via an idempotent machine-local `.git/info/exclude` entry
(`skill_usage_git_exclude=false` opts out for teams that commit the telemetry).

One row per Skill call, with these fields:

| Field | Present | What it holds |
|---|---|---|
| `ts` | always | UTC timestamp of the call, `YYYY-MM-DDTHH:MM:SSZ` |
| `event` | always | `SkillUse`, the key readers filter this store on |
| `skill` | always | the skill name, leading slash stripped |
| `branch` | always | the checked-out branch, `unknown` outside a git work tree |
| `project` | always | the project root's basename, for display |
| `project_id` | always | basename plus a digest, collision-resistant across checkouts in the user and data-dir scopes |
| `hook` | always | `skill-usage-audit` |
| `source` | always | `tool` (the Skill tool) or `expansion` (a user-typed slash command) |
| `expansion_type` | expansion path only | `slash_command` or `mcp_prompt` |

`hook-failure-audit` is the other exception. Its user-facing `systemMessage`
warning fires regardless of sink wiring (only its envelope needs a sink),
because its whole subject is failures nothing else surfaces: a hook that fails
to launch is a non-blocking error, the guarded tool call proceeds as if
approved, and the only durable trace is a transcript attachment no human reads
(#2577). It runs once per `Stop`, tails a bounded window of the session
transcript for `hook_non_blocking_error` attachments (structural match on the
attachment type, never substring), and warns once per session per distinct
failing hook registration, keyed on `hookName` plus the registered command because several plugins
share an event and matcher, re-warning when a new registration starts failing. It
lives in this
plugin, not in the plugin it might report on, deliberately: an in-plugin
detector shares its plugin's registration form and dies with it, which is
exactly how disk-hygiene's guard monitor missed the #1416 incident class.

Each failure record is classed one of four ways, and the warning gives each
class its own diagnosis and remedy:

- **launch failure**: stderr carries an exec-failure signature; the hook never
  ran.
- **stale config**: exit 127 and the whole stderr is bash's missing-script line
  (`bash: <path>: No such file or directory`). The session still runs hook
  config it loaded before a plugin update or an in-place edit deleted that
  script; the remedy is `/reload-plugins`, or a restart.
- **ambiguous**: exit 126 or 127 with neither of the above, so the registered
  command and the hook's own commands are both suspects.
- **completed non-zero exit**: the hook ran and failed.

Its budget share is stated as a **process count**, not a duration, and the host
is the reason. The [hook-budget
convention](../../docs/conventions/hook-budget/README.md) states each
always-on hook's budget as k x S plus measured work (k = fewest spawns, S = one no-op spawn's time), not a fixed millisecond figure, and on the host in #3508 one
process creation costs 180-2,841 ms (median 1,108 ms at 501 concurrent
processes), so the count is what decides whether the set fits and a duration
measured anywhere else does not transfer. On a turn with **no** hook failure
recorded, the common case, the hook costs **9 process creations and 4 program
execs**: one `wc` for the tail-cap decision, one `grep` pre-filter that opens
the transcript directly, and two `jq` passes inside the synced `hook-utils.sh`.
The creations above that are subshell forks inside the same shared library. It
was 18 creations and 6 execs before #3512. Counts are measured with `strace -ff
-e trace=clone,clone3,fork,vfork,execve`, not `bash -x`: a command substitution
whose command carries its own redirection forks a subshell that xtrace cannot
see, and those forks were most of the cost. `hook-failure-audit.test.sh`
asserts both ceilings. Windows Git Bash, the host the convention binds to,
measured S (the bash spawn floor) at 33 ms on 2026-09-30, through the bash the
launcher spawns (20 ms on the PATH bash), but the hook-failure-audit wall
there is still unmeasured for this row, so its spawn-equivalents (hook wall
divided by the same-run S) are still owed.

`skill-usage-audit` is captured by two disjoint producers so both invocation
paths are measured: the model-invoked `Skill` tool (`PostToolUse`) and the
user-typed slash command (`UserPromptExpansion`, which bypasses the `Skill`
tool). Events carry a `source` field (`tool` vs `expansion`) so consumers can
tell the paths apart; both share the same telemetry `hook` id and second store.

Its share of the budget is stated as a **git process count**, the part of the
row's cost that varies with the store's contents. The store write spawns
**3 git processes**: the repo-root read, the `.git/info/exclude` hygiene read
(repo scope only), and one `git rev-parse --abbrev-ref HEAD` for the branch.
Measured with `strace -ff -e trace=execve` on a throwaway fixture repository,
the same method the `hook-failure-audit` counts above use. This row is not in
the always-on per-tool-call set: its matcher is `Skill`, so an ordinary tool
call spawns nothing.

| Hook | Event | Emits | Why it earns its spawn |
|---|---|---|---|
| `api-error-audit` | StopFailure | API turn-failure `error_type` (never the message body) | The event only fires when a turn fails at the API, so the hook costs nothing on a healthy session |
| `config-change-audit` | ConfigChange | the mutated `config_source` | Matcher-scoped to the four sources that can change behavior, and a settings or skills change is rare |
| `instructions-loaded-audit` | InstructionsLoaded | `<repo-relative-file>:<load_reason>` (absolute prefix stripped; session_start filtered by default) | The highest-volume row here, and the only one whose cost is worth watching. It is advisory: InstructionsLoaded ignores the exit code, so the hook never gates a load, and the session_start write-time filter keeps the noisiest reason out of the store by default |
| `permission-denied-audit` | PermissionDenied | classifier denials, `Bash:<first-token>` subject | Fires only on an actual denial, and it is the only durable record of what the classifier refused |
| `pre-compact-audit` | PreCompact | compaction `trigger` (`manual`/`auto`) | Once per compaction, which is the rarest event this plugin observes |
| `skill-usage-audit` (tool path) | PostToolUse (`Skill`) | model-invoked skill; `source: "tool"`; also writes the `skill-usage.jsonl` second store | Matcher-scoped to `Skill`, so it is skipped on every other tool call rather than firing per PostToolUse |
| `skill-usage-audit` (expansion path) | UserPromptExpansion | user-typed `/command` (`slash_command`/`mcp_prompt`); `source: "expansion"` + `expansion_type`; same second store | Fires per expanded slash command, not per prompt, and it is the only path that sees a user-typed invocation (the `Skill` tool never runs) |
| `tool-failure-audit` | PostToolUseFailure | Write/Edit/Bash failures, privacy-safe subject | Matcher-scoped to the three tools whose failures are actionable, and the event fires only on failure |
| `hook-failure-audit` | Stop | unsurfaced `hook_non_blocking_error` attachments; envelope subjects are hook names only; also warns via `systemMessage` | The only per-turn row, and it is the sole surface for a hook that failed to launch while its guarded tool call proceeded |

None captures a command body, absolute path, error message, or argument body, only category labels, privacy-safe subjects, and (for `instructions-loaded-audit`)
the repo-relative path of the loaded rule file.

The InstructionsLoaded row carries no matcher on purpose. That event's matcher selects on load
reason, and the row passes every reason through verbatim into its subject, so
scoping to the full documented set would skip nothing and would silently drop any reason a later
release adds. Scoping below that set is worse: the only reason worth excluding for cost is
`session_start`, which the row already drops at write time, and it drops it behind the
`instructions_loaded_audit_log_session_start` option. A matcher that excluded `session_start` would
stop the hook from ever spawning on it, leaving that option switched on but unable to log anything.
The row therefore stays unscoped until the option is retired.

### Per-hook kill switches

Each audit hook is toggled by its own `userConfig` boolean (default **on**; set
to `false` for a clean no-op). Disable one hook without touching the others.
The hooks read them through the native `CLAUDE_PLUGIN_OPTION_<KEY>` hook-process
mirror. Seven rows share `audit-event-emitter.sh`, which reads the switch of the
row the event selected: sharing a script does not share a switch, and turning one
row off leaves the other six emitting.

| Hook | Option |
|---|---|
| `api-error-audit` | `api_error_audit_enabled` |
| `config-change-audit` | `config_change_audit_enabled` |
| `instructions-loaded-audit` | `instructions_loaded_audit_enabled` |
| `permission-denied-audit` | `permission_denied_audit_enabled` |
| `pre-compact-audit` | `pre_compact_audit_enabled` |
| `skill-usage-audit` (both paths) | `skill_usage_audit_enabled` |
| `tool-failure-audit` | `tool_failure_audit_enabled` |
| `hook-failure-audit` | `hook_failure_audit_enabled` |

`instructions-loaded-audit` drops deterministic, high-volume `session_start`
loads by default; set `instructions_loaded_audit_log_session_start=true` to opt
back into logging them. A `stdin_read_timeout` option (seconds, default `2`) is
an **idle** bound on reading each hook's payload: any byte arriving resets it, so
a large or slowly-delivered payload is never cut off while it is still coming,
and it fires only once the pipe has gone silent for that long, at which point
these audit hooks fail open (skip). On a shell whose `read -t` accepts fractional
values the bound is read in four slices, so the stall is detected within a
quarter of the configured interval of it; where fractional timeouts are
unavailable (Bash 3.2, the macOS system shell) it is read as one window and a
producer that sends bytes then goes silent can take up to two intervals. A producer
that keeps emitting is bounded by Claude Code's own hook timeout, not by this
value. A setting this shell's `read -t` will not accept, or `0`, falls back to
the default.

Set them interactively with `/plugin configure harness-ops@<marketplace>`, or headless on the
install command:

```shell
claude plugin install harness-ops@<marketplace> --config skill_usage_audit_enabled=false
```

Option scoping (user vs project settings, and the per-repository escape hatch)
per "How to set these" below.

### Wiring the reference sink

A migrated emitter is inert without a consumer. `hooks/hook-telemetry-sink.sh`
is a **reference** sink: it reads an envelope on stdin and appends one line under
the hook log root, `<project-root>/.observability/claude` by default (the
`session_event_log_dir` option moves it). An envelope carrying
`data.session_id` lands in `sessions/<session_id>.jsonl`, beside the
per-session event log; one without lands in the shared `hook-events.jsonl`
in the legacy shape; that file rotates to `hook-events.jsonl.1` at
`hook_events_max_bytes` whatever the session-log switch is set to. Both are
what the `observability` skill reads. The root carries a self-ignoring
`.gitignore`, created on the first write (or by
`/harness-ops:setup apply`); rows left at the old
`.claude/observability/hook-events.jsonl` location are detected by setup as
retirement `harness-ops-r001` and migrated on request.

Wire it by pointing `HOOK_TELEMETRY_SINK` at an **executable that exists at
resolution time**. A *relative* value resolves against the **consuming repo
root**, not the plugin cache, so the marketplace-installed copy under
`${CLAUDE_PLUGIN_ROOT}` is **not** reachable by a relative path (and Claude Code
injects `settings.json` `env` values literally, with no `${CLAUDE_PLUGIN_ROOT}`
expansion). Two workable forms:

- **Copy the reference sink into your repo** (e.g. `.claude/hooks/hook-telemetry-sink.sh`)
  and wire that repo-relative path, the portable, team-shared, clone-safe form:

  ```json
  { "env": { "HOOK_TELEMETRY_SINK": ".claude/hooks/hook-telemetry-sink.sh" } }
  ```

  The sink `source`s `hook-utils.sh` from its own directory, so a bare copy
  fails at startup: either copy `hook-utils.sh` alongside it, or edit the copy's
  `source` line to point at a `hook-utils.sh` your repo already carries.

- **Or** point at an **absolute** path to the installed sink under your plugin
  cache. It is per-machine, and it moves on each plugin update, so it is not
  clone-portable.

Any envelope producer (this plugin's hooks, guardrails, the formatters) then
flows into the same store. The sink is fire-and-forget and best-effort, a slow
or absent sink silently drops the event; it is for observability, not
audit-of-record.

### The per-session hook event log (off by default)

Independently of any sink, `session_event_log_enabled=true` turns on the log.
It is a mod: the hooks module `hooks/register.ts` hooks one `classic.<Event>`
per observable hook event (28 events; the generated
`hooks/hook-events.registry.json` says which, and why `WorktreeCreate`,
`MessageDisplay` and `FileChanged` are left out), and only while the switch is
on. `PreToolUse` and `PostToolUse` are left out too: they fire on every tool
call, so an enabled log would cost a process creation per call. Tool activity
is still recorded through `PostToolUseFailure` and `PostToolBatch`. A batch is
one line, not a per-call record: it carries the first `tool_name` and
`tool_use_id` the payload text holds, normally the first call's. Each fire
appends one line to `<root>/sessions/<session_id>.jsonl`: the correlation keys
the payload carries (`prompt_id`, `tool_use_id`, `agent_id`), the event and its
category, the tool and a repo-relative file path when present.

Process cost: with the switch off (the default) the module hooks nothing, so no
event starts a process (k = 0; `hooks/session-event-log.test.ts` counts the
processes for every event). On, a mod cannot append to a file, so each event
starts one process: the module hands the event's payload to
`hooks/session-event-log.sh` through `node hooks/exec-bash.mjs`, the same script
and launcher the settings rows ran, and `SessionEnd` starts a second for
retention. No event waits on the write, which runs on a timer after the event
goes on; `SessionEnd` waits for both, inside its teardown budget. Enabled, a 2 KB payload costs about 5 ms and a 512 KB one 36 ms of
script time on the Linux CI host. The parallel wall, the 4 KB and 16 KB appends,
`ls -t`, and the late-EOF stall are measured by
[`hooks/measure-hook-log-budget.sh`](hooks/measure-hook-log-budget.sh) and
recorded in
[`reference/hook-log-budget.md`](reference/hook-log-budget.md). On Windows Git
Bash (2026-09-30), thirty parallel events take 466 ms wall on, and the 4 KB and
16 KB appends leave 0 corrupt lines out of 33. `ls -t` ties at one-second
resolution there, so no ordering is claimed. The switch stays off by default.

The module needs Claude Code 2.1.287 or later with mods on, and was tested with
`claude plugin test` on Claude Code 2.1.289; no live session type was run. Where
mods are off (below 2.1.287, under `disableAllHooks`, with `--bare`, or when
mods are switched off), the log does not run: no session file is written and
retention does not prune. On a machine with managed settings, or for a user
signed in with a Team or Enterprise plan, the built-in guard `sec-default`
holds every `classic.*` event, so the log does not run there either. Mods start
processes in the CLI only; where `$.process.run` cannot run, the module writes
nothing and logs that once to the debug log. A row's `traceparent` key is not
written, since a mod receives no per-hook `TRACEPARENT`. These differences from
the settings rows the log replaced are recorded in
[ADR 0058](../../docs/adr/0058-move-the-harness-ops-session-event-log-into-a-mod.md).

`session_event_log_categories` narrows the set. At `SessionEnd` the retention
script, gated by the same switch, keeps the newest
`session_log_keep_sessions` or the last `session_log_keep_days` days, and
`session_log_pre_prune_command` hands an archiver the files about to go. The
root carries its own `*` `.gitignore`, so nothing under it reaches
`git status`; `/harness-ops:setup` reports the toggles and the guard,
`/harness-ops:observability session` reads the result.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install harness-ops@<marketplace>
```

## How the skills adapt to your repo

The defaults are repo-agnostic and everything project-specific routes through
your own repository's context:

- **Observability data locations.** The OTEL store defaults to
  `<project-root>/.claude/observability/otel` and is overridable via the
  `CC_OTEL_STORE` env var (retention windows via `CC_OTEL_RETENTION_DAYS` /
  `CC_OTEL_BODY_RETENTION_DAYS`). The hook-event JSONL source is read from
  the hook log root (`<project-root>/.observability/claude` by default, the
  `session_event_log_dir` option moves it): `sessions/<session_id>.jsonl`
  when the per-session event log is on or the sink is wired, and the shared
  `hook-events.jsonl` (rotated to `.1` at the size cap) for envelopes without
  a session id; every source degrades gracefully when absent.
- **Persistent state** defaults to the plugin's own per-machine data directory
  (`${CLAUDE_PLUGIN_DATA}`): the known-issues registry
  (`registry.json`), `check-all` output, `--write` observability reports, and
  the `lanes` skill's per-lane launch-commit markers
  (`${CLAUDE_PLUGIN_DATA}/lanes/<repo-key>/<lane>-launch-commit`, overridable
  via `lane-launcher.sh --data-dir`). `<repo-key>` namespaces markers by
  repository, the data directory is plugin-wide, while a lane name like `work`
  is only unique within one checkout. `<repo-key>` is a digest of the repository's
  canonical path; print the one for a given checkout with
  `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`. By default nothing is written into your
  repository. Opt in for the registry via the `registry_dir` option (see
  Configuration) to keep it git-tracked and team-shared inside your repo
  instead.
- **Work-item and docs integration.** Where the skills propose follow-up work
  items or cross-reference quirks/workaround docs, they use whatever tracker
  and docs your project has (e.g. `gh issue create`, your `CLAUDE.md` /
  `.claude/rules`) and skip silently when there is none.

## Requirements

The audit hooks are Bash scripts (Git Bash on native Windows, so install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)) and
use `jq`; without jq they fail open (no audit line is written).

**Node.js on PATH.** Every hook row except `hook-failure-audit` starts through
`node hooks/exec-bash.mjs`, which finds the real Bash and runs the script. Claude Code's native
binary neither ships nor uses Node.js ([setup](https://code.claude.com/docs/en/setup), fetched
2026-09-29), so without `node` on PATH those hooks do not launch. The `hook-failure-audit` Stop row
is shell form (`"shell": "bash"`) and needs no node, so it still reports the failed launches. `/harness-ops:check` reports whether `node` and `jq` resolve.

**Mods for the session event log.** The per-session hook event log runs in the hooks module, so it
needs Claude Code 2.1.287 or later with mods on; where mods are off it does not run (see
[The per-session hook event log](#the-per-session-hook-event-log-off-by-default)). The audit rows
are settings hooks and run with mods off.

`audit-install-state` needs **Python 3.11+ only**. No PowerShell, no third-party packages, no
`jq`. Its inventory, surface classification, filename-scheme resolution, retention resolution and
sampling are pure `os.walk` + `stat` + regex and behave identically on every platform. The single
OS-specific seam is one function, `probe_pid()`, with a POSIX body (`os.kill(pid, 0)`) and a Windows
body (`OpenProcess`); a probe that cannot run reports `unverified`, never `dead`.

Core flows need only `git`, `jq`, `gh` (authenticated), and `python3`.
Optional: `duckdb` for OTEL store queries and `npx` for ccusage. The machine-level
`otelcol-contrib` service and Aspire dashboard Compose stack are provisioned separately; the
plugin observes them but does not start them. Every skill reports missing optional tooling
instead of failing.

## Configuration

The per-hook kill switches, `instructions_loaded_audit_log_session_start`, and
`stdin_read_timeout` are documented under
[Per-hook kill switches](#per-hook-kill-switches). Three further `userConfig`
options tune the skills:

- **`install_new`** (string, optional). New-catalog-plugin install policy for the `plugins`
  skill's `sync` action. `ask` (default) offers not-yet-installed catalog plugins in one batched
  multi-select prompt, then installs and enables each pick; `all` installs every one
  automatically, leaving one the CLI installs disabled by default off; `none` reports them without
  installing. `/config` shows these three as a picker; a value set by hand outside it is treated
  as `ask` and named in the sync digest.
- **`registry_dir`** (string, optional). Project-relative directory for the
  known-issues registry (`registry.json`). Set it to keep the
  registry inside your repo (git-tracked, team-shared) instead of the
  per-machine plugin data directory; leave unset to use `${CLAUDE_PLUGIN_DATA}`.
  Absolute, drive-qualified, UNC, traversal, and escaping-symlink paths are
  invalid; known-issues operations must stop and direct you to reconfigure
  rather than write outside the project.
- **`skill_usage_scope`** (string, optional), where the `skill-usage-audit`
  second store lives. `repo` (default) keeps it in the project tree, with a
  machine-local `.git/info/exclude` entry so `git status` stays clean; `user`
  resolves the same `skill_usage_dir` subpath under `$HOME` for one cross-repo
  operator store (rows carry `project` + collision-resistant `project_id`
  fields); `data-dir` writes
  `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>`. Plugin-owned, update-safe,
  never in any repo tree. `/config` shows the three values as a picker; a value
  set by hand outside it falls back to `repo` with a one-time advisory. The default
  stays `repo` deliberately: the store stays in the project tree, matching
  the observability posture that telemetry is project-local, and the exclude
  entry removes the status noise that motivated the scope knob. (The hook log
  root is a separate tree with its own self-ignoring guard; see "Wiring the
  reference sink".)
- **`skill_usage_git_exclude`** (boolean, default `true`). Repo scope only:
  idempotently exclude the store dir via `.git/info/exclude` (never touches
  `.gitignore` or tracked files). Set `false` when your team deliberately
  commits the telemetry.
- **`skill_usage_dir`** (string, optional). Contained relative directory,
  resolved under the scope root (repo scope: repo root; user scope: `$HOME`),
  where `skill-usage-audit` writes its `skill-usage.jsonl` second store (the
  "measuring skills" record, separate from the telemetry envelope); leave unset
  to use `.claude/observability`. The same containment rules apply in every
  scope; the `data-dir` scope ignores it. An invalid
  value produces a visible advisory and skips the second-store write; telemetry
  through an independently configured sink can still proceed.

Run `/harness-ops:setup` to validate this choice. Claude Code owns persistence through its plugin
configuration prompt; rerun setup afterward to verify the rendered value.

Remaining variability is covered by the env vars above and conventional
project-relative defaults; the bundled scripts make no outbound network calls
except `gh`/`curl` reads of GitHub and Claude status pages in the
known-issues skill.

### Option details

**`session_event_log_enabled`.** Off, the hooks module hooks no event, so the log starts no process.
On, each recorded event starts one process. The log runs only where mods load.

**`session_event_log_dir`.** Inside a checkout the directory carries a self-ignoring `.gitignore`,
created on the first write.

**`hook_events_max_bytes`.** Read only when a harness-ops hook emits the envelope: an emitter in
another plugin that runs the sink keeps the 10485760 default. A value above 999999999999999999 is
ignored and the default applies.

**`session_log_pre_prune_command`.** The session files about to be pruned are moved into the
directory passed as the argument, and its physical delete waits for the next retention run after
24 hours, so an archiver has a stable set to read. The command runs through `bash -c`, so it is
trusted configuration: on current releases project and local `pluginConfigs` are ignored and only
the user's own settings supply it (recheck: the plugins reference's user-configuration section).

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `registry_dir` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_REGISTRY_DIR` | Project-relative directory holding the known-issues registry (registry.json). Leave unset to keep the registry in the plugin data directory, ${CLAUDE_PLUGIN_DATA}. Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid. |
| `install_new` | string | `"ask"` | `CLAUDE_PLUGIN_OPTION_INSTALL_NEW` | What the plugins skill's sync action does with catalog plugins not yet installed. ask (default) offers them in one batched multi-select prompt, then installs and enables each pick, including one the CLI installs disabled; all installs every one automatically; none reports them and never installs. |
| `skill_usage_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED` | Emits telemetry on skill usage, on by default. Shared by both skill-usage audit hooks (the Skill-tool and slash-command expansion paths), and also gates the shared skill-usage.jsonl store. |
| `skill_usage_scope` | string | `"repo"` | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE` | Where the skill-usage store lives. repo (default) keeps it in the project tree, out of git status via a machine-local .git/info/exclude entry; user puts the skill_usage_dir subpath under $HOME as one cross-repo store; data-dir uses ${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>. |
| `skill_usage_dir` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR` | Relative directory where the skill-usage-audit hooks write skill-usage.jsonl, under the skill_usage_scope root (repo: the project root; user: $HOME). Leave unset to use .claude/observability. The data-dir scope ignores it. Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid. |
| `skill_usage_git_exclude` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SKILL_USAGE_GIT_EXCLUDE` | Adds the repo-scope store's directory to .git/info/exclude when it sits inside a git work tree, so git status stays clean. On by default; machine-local, and never touches .gitignore or tracked files. Set false if your team deliberately commits the telemetry. |
| `api_error_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_API_ERROR_AUDIT_ENABLED` | Emits turn-failure telemetry on API errors. On by default. |
| `config_change_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONFIG_CHANGE_AUDIT_ENABLED` | Emits telemetry on config-source mutations. On by default. |
| `instructions_loaded_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_ENABLED` | Emits telemetry on rule and instruction file loads. On by default. |
| `instructions_loaded_audit_log_session_start` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START` | Makes the instructions-loaded-audit hook log session_start instruction loads. Off by default, because those loads are deterministic and high-volume. |
| `permission_denied_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PERMISSION_DENIED_AUDIT_ENABLED` | Emits telemetry on permission denials. On by default. |
| `pre_compact_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_PRE_COMPACT_AUDIT_ENABLED` | Emits telemetry on context-compaction events. On by default. |
| `tool_failure_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_TOOL_FAILURE_AUDIT_ENABLED` | Emits telemetry on Write, Edit, and Bash tool failures. On by default. |
| `hook_failure_audit_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED` | Warns once per session per hook when the transcript records hook launch or exec failures Claude Code never surfaced. On by default. |
| `session_event_log_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED` | Appends one JSON line per hook event to <session_event_log_dir>/sessions/<session_id>.jsonl, on every event the generated registry marks observable. Runs in the hooks module, so it needs mods on. Off (the default), no event starts a process; on, each starts one. It also gates SessionEnd retention. |
| `session_event_log_dir` | string | `".observability/claude"` | `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR` | Project-relative directory holding the per-session hook event log (sessions/) and the telemetry sink's hook-events.jsonl. Default .observability/claude. Absolute, drive, UNC, traversal and escaping paths are invalid, and the project root itself is refused. |
| `session_event_log_categories` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES` | Comma-separated event categories to record (session, prompt, tool, permission, agent, task, turn, config, worktree, compaction, model, mcp, display, other). Empty, the default, records every category the registry marks observable. |
| `session_event_log_content` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CONTENT` | Also records each event's top-level content strings (prompt, last_assistant_message, message, task text, error and the like) in the session event log; content the 64 KB read cap cuts is marked truncated. Off by default; has no effect while session_event_log_enabled is off. |
| `session_log_keep_sessions` | number<br>*min 1* | `30` | `CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_SESSIONS` | At SessionEnd, keeps the newest N session files regardless of age; default 30. A file is kept when it is among the newest N OR younger than session_log_keep_days. |
| `session_log_keep_days` | number<br>*min 1* | `14` | `CLAUDE_PLUGIN_OPTION_SESSION_LOG_KEEP_DAYS` | At SessionEnd, keeps every session file younger than N days regardless of count; default 14. A file is kept when it is younger than N days OR among the newest session_log_keep_sessions. |
| `session_log_pre_prune_command` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_SESSION_LOG_PRE_PRUNE_COMMAND` | Command run detached at SessionEnd with one argument: a directory holding the session files about to be pruned, deleted on the next retention run after 24 hours. Leave unset to delete directly. Runs through bash -c, so only your own user settings can supply it. |
| `hook_events_max_bytes` | number<br>*min 1* | `10485760` | `CLAUDE_PLUGIN_OPTION_HOOK_EVENTS_MAX_BYTES` | Size at which the telemetry sink rotates the shared hook-events.jsonl to hook-events.jsonl.1, replacing any older .1, so the pair stays near twice this value. Default 10485760. Applies whether or not the per-session event log is on. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` | Idle bound on reading the hook payload from stdin: how long the pipe may go silent before the hook gives up and fails open. Default 2. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure harness-ops@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install harness-ops@<marketplace> -s <scope> --config registry_dir=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "harness-ops@<marketplace>": {
         "options": {
           "registry_dir": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
