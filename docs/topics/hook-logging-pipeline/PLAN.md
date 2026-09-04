# hook-logging-pipeline

## Brief

### TLDR

Design the logging and telemetry pipeline for the marketplace's hooks, and settle the upstream
decisions that determine what it instruments. Evidence base is
[FINDINGS.md](FINDINGS.md), a measured read-only audit of the 26 wired `PostToolUse` rows plus a
same-day doc-alignment pass. Interview in progress: round 1 resolved, round 2 not started.

### Goal

A logging pipeline that answers questions the fleet currently cannot answer, without adding cost to
a per-tool-call surface that already exceeds its own stated budget.

### Constraints

Established by measurement or by a raw fetch of the official reference, not assumed:

- Hooks run in parallel with no ordering control. Order is reconstructable only.
- `OTEL_*` is stripped from hook subprocesses; `TRACEPARENT` is passed through.
- Claude Code configures no retention. The pipeline owns it entirely.
- The existing envelope (`docs/conventions/hook-telemetry`) has about 35 producers, is additive-only,
  and no-ops when `HOOK_TELEMETRY_SINK` is unset. Emission measured free.
- `classifierContext` is PostToolUse-only, capped at 2,000 characters shared across every hook on a
  call, ignored for background hooks, discarded on read-only lookups.
- `docs/MIGRATION-PLAYBOOK.md` "Organization": "a hooks plugin bundles many hooks of one concern.
  One-unit-per-plugin is not the norm; do not ship a plugin per hook." Selectivity comes from a
  `userConfig` toggle, a `matcher`, or an `if` guard.

### Decisions locked (round 1)

- **Q1. Primary consumer of the log is guard-precision measurement**, latency attribution second,
  prerequisite-skip visibility as a field rather than a purpose. Rationale: ADR-0003 requires a guard
  to earn default-on by measured firing rate and precision, and the only mechanism available today is
  a manual one-off corpus sweep. A standing log turns that into a capability. The schema must
  therefore record non-fires, not only fires: a guard that never fires has undefined precision, not
  zero.
- **Q2. The formatter family does not move to `async: true`.** Prefer `PostToolBatch`. Async breaks
  the context-versus-disk contract, because an async hook rewrites the file after Claude has moved on
  and cannot use `updatedToolOutput` to correct context. Async also suppresses `classifierContext`
  outright. And because the parallel wall is max-of-set, asyncing a non-slowest hook frees nothing.
- **Q3. Telemetry hooks stay in `claude-ops`**, with a group-level toggle rather than an extraction.
  The playbook forbids plugin-per-hook; the claude-ops hooks produce what its own `observability`
  skill consumes, so they are one concern; and `${CLAUDE_PLUGIN_DATA}` is keyed to plugin id, so a
  split would fork the state directory across 4 hook files and 18 skill files.
- **Q4. The six-plugin hooks/skills split is out of scope**, and no playbook amendment is proposed.
  The premise was also largely false: 14 of the 20 hook-bearing plugins ship only a `setup` skill,
  which is the hook's own installer, so they are already hooks-only. Splitting a gate from the skill
  whose invariant it enforces is an active hazard: `worktree-add-containment-gate` enforces the
  nesting invariant `source-control:worktree` depends on.

Q3 and Q4 were recommended in the opposite direction earlier in the session and withdrawn on
discovery of the written policy. That reversal is recorded rather than erased.

### Acceptance criteria

Not yet established. Rounds 2 and beyond cover capture scope, storage location and isolation,
concurrent-append safety, rotation, retention, filtering and levels, scopes, envelope versioning, and
correlation keys.

### Captured assumptions

- The consuming repo, not the marketplace, owns sink configuration and retention policy. Carried
  forward from the existing envelope contract, not re-litigated.
- No consumer outside this machine has wired `HOOK_TELEMETRY_SINK`. If false, any envelope change
  becomes a breaking change and the additive-only rule binds harder.

### Out of scope

- The six-plugin hooks/skills split (Q4).
- Any change to a PreToolUse hook. That lane belongs to `claude/pretool-validation-hooks-84d7ka`.
- The cross-cutting registry for machine-read comment markers. Real gap, roughly 15 families with two
  competing suffix idioms and no owner, but above any single hook lane and an operator call.

### Deferred questions

- **Q5. Capture scope.** Opt-in producers only, or add the native `--include-hook-events` stream and
  the `claude_code.hook` span to cover third-party hooks that never opt in? Arbiter: round 2.
- **Q6. Ownership of the kill-switch hoist**, roughly 44 sites spanning two lanes. Proposed split is
  strictly by plugin directory. Arbiter: USER-RESERVED, because it allocates work across sessions.
- **Q7. Does `docs/conventions/hook-observability` need to name the `# silent-skip-ok:` marker
  explicitly?** Raised because the operator reported not knowing what it meant, which is a defect in
  the convention rather than in any consumer of it. Arbiter: this lane.

## Plan

Not started. `/planning:plan` fills this section once the Brief is complete.
