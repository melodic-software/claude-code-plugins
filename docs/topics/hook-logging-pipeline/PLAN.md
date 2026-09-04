# hook-logging-pipeline

## Brief

### TLDR

Design the logging and telemetry pipeline for the marketplace's hooks, and settle the upstream
decisions that determine what it instruments. Evidence base is [FINDINGS.md](FINDINGS.md), a
measured read-only audit of the 26 wired `PostToolUse` rows plus a doc-alignment pass, reproducible
via [harness/measure-posttooluse.sh](harness/measure-posttooluse.sh). Interview rounds 1 to 3
resolved; round 4 (retention, rotation, file granularity, concurrent-append safety) open.

### Goal

Observability across every hook event, defaulting to off, costing effectively nothing when off and
as close to nothing as measurable when on, with no surface left as a black box and every toggle
reachable by Claude on the operator's behalf rather than by hand.

### Constraints

Established by measurement or by a raw fetch of the official reference, not assumed. Each upstream
claim below carries its basis in FINDINGS.md and is subject to the four-part record and recheck
trigger that `docs/conventions/upstream-drift` requires.

- Hooks run in parallel with no ordering control. Order is reconstructable only.
- `--include-hook-events` requires `--output-format stream-json`, which is a headless invocation
  mode. It is not available in an interactive session.
- `SessionEnd` has a 1.5 second default timeout, and a plugin-provided timeout does not raise the
  budget. Only a settings-file hook or `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` does.
- `OTEL_*` is stripped from hook subprocesses; `TRACEPARENT` is passed through when tracing is
  active. `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips more.
- Claude Code configures no retention. The pipeline owns it entirely.
- Measured cost floor for one enabled hook that does nothing: 2.07 ms bare, 3.41 ms reading stdin,
  7.45 ms once `lib/hook-utils.sh` is sourced, against a 1.71 ms spawn floor. Concurrent scaling is
  sublinear: 33 simultaneous bare hooks cost 19.5 ms, not 33 times one.
- `docs/MIGRATION-PLAYBOOK.md`: "do not ship a plugin per hook." Selectivity is a `userConfig`
  toggle, a `matcher`, or an `if` guard.

### Decisions locked

**Round 1.**

- **Q1. Primary consumer is guard-precision measurement**, latency second, prerequisite-skip
  visibility as a field. ADR-0003 requires a guard to earn default-on by measured precision, and the
  only mechanism today is a manual corpus sweep. The schema records non-fires, not only fires: a
  guard that never fires has undefined precision, not zero.
- **Q2. No `async: true` for the formatter family.** Prefer `PostToolBatch`. Async breaks the
  context-versus-disk contract, suppresses `classifierContext` outright, and frees nothing on a
  non-slowest hook because the parallel wall is max-of-set.
- **Q3. Telemetry hooks stay in `claude-ops`** with a group-level toggle, not an extraction. The
  playbook forbids plugin-per-hook, the hooks produce what the `observability` skill consumes, and
  `${CLAUDE_PLUGIN_DATA}` is keyed to plugin id so a split would fork the state directory.
- **Q4. The six-plugin hooks/skills split is out of scope**, no playbook amendment. 14 of the 20
  hook-bearing plugins ship only a `setup` skill, which is the hook's own installer.

**Round 2.**

- **Q5. Native first where native reaches, envelope where it cannot.** The envelope is the only
  source of per-hook `duration_ms` and outcome in an interactive session. `claude_code.hook` and
  `--include-hook-events` are documented as diagnostic modes with their limitations stated, never as
  the backbone, because the latter is headless-only.
- **Q6. Logging hooks on every documented event, plugin default-OFF.** Observability is turned on
  when needed, so nothing is paid by a consumer who has not asked for it. The event list is a
  **generated registry**, never a hardcoded list: derived from a live fetch, each entry stamped with
  claim, basis, as-of date, and recheck trigger per `docs/conventions/upstream-drift`, and phrased
  per `docs/conventions/native-references`, which forbids asserting that any native surface is
  present or absent and requires read-time presence gating instead.
- **Q7 and Q12. Storage at `.observability/claude/`, configurable.** Grouping by parent concern then
  by application. Avoids the `.claude/` write-permission friction, gives a consumer one observability
  root across tools rather than per-vendor scatter, and one ignore rule covers the tree permanently.
  The existing sink writes `.claude/observability/hook-events.jsonl`; that is current-state fact and
  its migration is a task, not a premise.
- **Q10. Three independent toggle levels, and the off-path made free first.** Level 1, whole pipeline
  off when the sink is unconfigured. Level 2, per-producer `CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED`.
  Level 3, a category filter so guard fires can be kept while formatter noise is dropped. The
  operator is not expected to know these: the plugin's skill configures them on request and reports
  what is in effect. Prerequisite: the kill switch is read **before** any library load, which
  measurement shows recovers 55% of the disabled cost.
- **Q11. Five correlation keys as a hierarchy, not alternatives.** `session_id` (session),
  `prompt_id` (turn, and the documented join to `prompt.id` on OTEL events), `tool_use_id` (call,
  joins `claude_code.tool_result` and `tool_decision`), `agent_id` (subagent attribution, without
  which a subagent fire is indistinguishable from the main thread), and `TRACEPARENT` when present.
  This supersedes an earlier recommendation in this session that `tool_use_id` replaces `prompt_id`;
  the docs state the opposite and #930's premise was correct.

**Round 3.**

- **Q13. The `setup` skill writes the ignore rule and the sink refuses to log until it is present.**
  A consumer finding untracked files they cannot explain is a failure to make impossible, not to
  document.
- **Q14. A fixed spine on every event, per-event payload only where a decision was made.** Spine is
  the five correlation keys plus `hook_event_name`, `status`, `duration_ms`. Payload is added only
  for events carrying a decision or a change: what a guard blocked, what a formatter rewrote, which
  permission was denied, which model was switched. Events carrying neither get the spine alone.
- **Q15. The logging producer ships its own minimal emitter and does not source
  `lib/hook-utils.sh`.** Measured: the library costs 4 ms, more than the rest of the hook, and at
  full event coverage that is the difference between a 31 ms and a 62 ms worst case.

### Acceptance criteria

Not yet complete; round 4 supplies the retention and volume criteria. Established so far:

- With the plugin disabled, per-event cost is at or below the bare spawn floor plus one stdin read.
- No logging hook sources `lib/hook-utils.sh`.
- Every event-registry entry carries a basis and a recheck trigger; no upstream fact is restated
  without one.
- The ignore rule is present before the first write, verified rather than assumed.

### Captured assumptions

- The consuming repo owns sink configuration and retention policy.
- No consumer outside this machine has wired `HOOK_TELEMETRY_SINK`. If false, envelope changes
  become breaking and the additive-only rule binds harder.

### Out of scope

- The six-plugin hooks/skills split (Q4).
- Any change to a PreToolUse hook; that lane belongs to `claude/pretool-validation-hooks-84d7ka`.
- The cross-cutting registry for machine-read comment markers. A real gap with no owner, but above
  this lane.

### Deferred questions

- **Q16. File granularity**, one shared append-only log versus per-session files. Arbiter: round 4.
- **Q17. Concurrent-append safety** under parallel hook dispatch. Arbiter: round 4.
- **Q18. Retention and rotation.** Arbiter: round 4.
- **Q6a. Ownership of the kill-switch hoist**, roughly 44 sites spanning two lanes. Split by plugin
  directory is agreed by both lanes. Arbiter: USER-RESERVED, it allocates work across sessions.
- **Q7b. Does `docs/conventions/hook-observability` name the `# silent-skip-ok:` marker
  explicitly?** Raised because the operator reported not knowing what it meant, which is a defect in
  the convention. Arbiter: this lane.

## Plan

Not started. `/planning:plan` fills this section once the Brief is complete.
