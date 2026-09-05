# hook-logging-pipeline

## Brief

### TLDR

Design the logging and telemetry pipeline for the marketplace's hooks, and settle the upstream
decisions that determine what it instruments. Evidence base is [FINDINGS.md](FINDINGS.md), a
measured read-only audit of the 26 wired `PostToolUse` rows plus a doc-alignment pass, reproducible
via [harness/measure-posttooluse.sh](harness/measure-posttooluse.sh). Interview complete: five
rounds, 21 questions, 19 answered and 2 deferred with named arbiters. Register gate clean.

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

**Round 4.**

- **Q16. One file per session**, `.observability/claude/sessions/<session_id>.jsonl`. Removes the
  concurrency question by construction rather than capping around it, makes the analysis unit match
  the natural question, makes retention a directory listing, and lets `SessionEnd` finalize exactly
  one file inside its 1.5 s budget. Subagent fires land in the parent session's file, distinguished
  by `agent_id`.
- **Q17. Concurrent-append safety, resolved as a measured fact.** With 33 parallel appenders, a
  shared file under plain `>>` showed zero corruption at 64 B, 512 B and 4 KB lines, and 376 of 990
  lines corrupt plus 10 duplicates at 16 KB. Host `PIPE_BUF` is 4096. Per-session files never
  corrupt. Windows/Git Bash is unmeasured and is a recheck item, since it is the binding host.
- **Q18. Retention: keep the newer of the last 30 sessions or the last 14 days**, enforced at
  `SessionEnd`, both knobs configurable through the same option surface as every other toggle. The
  cost is a directory listing plus a few unlinks, inside the 1.5 s budget. Volume at this shape is
  roughly 200 B per spine line, so a busy 500-fire session is about 100 KB and 30 of them about 3 MB.

**Round 5.**

- **Q19. Prune means delete, with one extensibility point.** No built-in archive tier. The retention
  step invokes an optional consumer-configured pre-prune command with the list of files about to go,
  run detached so a slow consumer command cannot exhaust the `SessionEnd` budget. A consumer with a
  longer-retention or compliance need points that at their own archiver.
- **Q20. Extend `claude-ops:observability` rather than build a second reader.** Per-session files
  become its primary source and it gains a per-session scope. It is also the surface that reports
  what is toggled, what retention is in effect, and where the files are, which is how the operator's
  "Claude configures it for them" requirement is met without a new component.
- **Q21. Handoffs and observability stay separate.** No coupling in either direction. A handoff
  already carries `session_id`; so does every log line; the join is free. Deeper integration, if ever
  wanted, is a `session-flow` change and belongs to that lane.

### Acceptance criteria

- With the plugin disabled, per-event cost is at or below the bare spawn floor plus one stdin read
  (measured reference: 2.54 ms gate-first-disabled against a 1.71 ms floor).
- No logging hook sources `lib/hook-utils.sh`.
- Every event-registry entry carries a basis and a recheck trigger; no upstream fact is restated
  without one; the registry is generated, never hand-maintained.
- The ignore rule is present before the first write, verified rather than assumed.
- Every log line carries the full spine; a line is never written without `session_id` and
  `hook_event_name`.
- One file per session; no two Claude Code processes ever append to the same file.
- Retention runs at `SessionEnd` and completes inside the default 1.5 s budget with the default
  30-session / 14-day policy on a directory of 100 session files.
- The pre-prune command, when configured, is invoked detached and its failure or slowness never
  delays or blocks the prune.
- `claude-ops:observability` can answer, for a named session: which hooks fired, which blocked,
  which rewrote, and how long each took.
- Turning the plugin off and back on leaves no partial state and requires no cleanup.

### Captured assumptions

- The consuming repo owns sink configuration and retention policy.
- No consumer outside this machine has wired `HOOK_TELEMETRY_SINK`. If false, envelope changes
  become breaking and the additive-only rule binds harder.
- The 4 KB atomic-append boundary measured on Linux holds or is irrelevant on the Windows reference
  host. Irrelevant is the expected case, since per-session files remove the shared-write path
  entirely; the recheck is owed regardless.
- Version coordination on `plugins/claude-ops`: a sibling lane (`claude/code-quality-metrics-plugins-p99tkz`,
  commit `b92f6ead`) holds 0.41.13 with a CHANGELOG entry at the head. Any bump from this lane takes
  0.41.14 and places its entry above theirs, so whichever merges first the other rebases cleanly.

### Out of scope

- The six-plugin hooks/skills split (Q4).
- Any change to a PreToolUse hook; that lane belongs to `claude/pretool-validation-hooks-84d7ka`.
- The cross-cutting registry for machine-read comment markers. A real gap with no owner, but above
  this lane.
- A built-in archive tier (Q19). The extensibility point is shipped; the archiver is not.
- Handoff integration beyond the shared `session_id` (Q21).

**Confirmed after the interview closed (2026-09-05).**

- **Q8. Kill-switch hoist ownership: split by plugin directory, confirmed by the operator.** This
  lane takes the PostToolUse formatters, normalizers and verifiers; the PreToolUse lane
  (`claude/pretool-validation-hooks-84d7ka`) takes its 17 guard scripts. Neither touches
  `lib/hook-utils.sh` or its copies. Shape: a raw
  `[[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0` hoisted above the
  `source` line, existing `hook::check_enabled` left in place below. Measured recovery 55% of the
  disabled cost (2.54 ms vs 5.66 ms). 40 call-sites fleet-wide, 40 of 40 currently after the source
  line. `sync-hook-utils.sh` does not cover entry scripts, so a `scripts/check-killswitch-hoist.sh`
  CI gate ships with this lane's PR covering both directory sets, or it drifts back.
- **Verifier-lane performance fix, routed to this lane by the operator via the prompt-hooks
  session and confirmed here.** The three PostToolUse verifiers on a markdown write citing a skill
  and CLI commands cost about 825 ms (peer measurement, corroborated here at 601 to 622 ms for the
  dominant guard alone). Four patch shapes, each measured by the prompt-hooks lane and to be
  re-measured here before landing:
  1. `skill-reference-verify.sh:200-213`, one batched `jq` over all manifests keyed by
     `input_filename` in place of 2 `jq` + 2 `tr` per manifest. Independently measured here: 547.7 ms
     to 5.7 ms.
  2. `cli-flag-verify.sh` pre-gate: pure-bash substring test against `$BINS` in place of the
     `*-*` glob that ordinary prose defeats. Peer: 41.5 ms to 8.7 ms on prose-only.
  3. `cli-flag-verify.sh` loop: read the cache in-parent, spawn `verify-cli-flag.sh` only on a miss.
  4. `plugins/guardrails/lib/verification/verify-cli-flag.sh` cache-hit path: `[[ -d ]]` before
     `mkdir -p` (line 103), bash mtime compare in place of `find -mmin -1440 | grep -q .` (line 115),
     `[[ =~ ]]` in place of `printf | grep -E` (line 163). Peer A/B: 68.4 to 51.1 ms, identical rc
     on 11 cases. Line numbers verified here.
  Also peer-reported and unverified here: a cold-cache first run of `cli-flag-verify` at 11,391 ms
  (24 h TTL, so cold keys recur daily), and 126 failed `execve` PATH searches per warm run from 73
  plugin `bin/` directories prepended to `PATH` (count verified here). Read ADR-0003 before touching
  any of the three; it was written about exactly these guards.

### Deferred questions

- **Q9. Does `docs/conventions/hook-observability` name the `# silent-skip-ok:` marker
  explicitly?** Raised because the operator reported not knowing what the marker meant, which is a
  defect in the convention doc rather than in any consumer of it. Arbiter: `/planning:plan`, this
  lane, as a small documentation task alongside the pipeline work.

## Plan

Drafted 2026-09-05 by `/planning:plan` against the Brief above, the verified exploration
(`EXPLORE.md` in the topic's memory slice, VERIFIED-WITH-NOTES), and the doc-alignment pass in
[FINDINGS.md](FINDINGS.md). Design gate: Tier B early-exit, recorded at
[design/design-resolution.md](design/design-resolution.md).

### Goal

**What.** Land the three confirmed work allocations as three draft PRs in order: the verifier-lane
performance fix in `guardrails`, this lane's half of the kill-switch hoist with the CI gate widened
to PostToolUse, and the per-session hook-logging pipeline in `claude-ops` (producer, sink routing,
retention, generated event registry, setup guard, reader extension).

**Why.** Hook behavior is a black box today: no record carries a session id, the most expensive
PostToolUse hook spends 548 ms of a 622 ms run in a loop one batched `jq` replaces, and a disabled
hook still parses a 2,766-line library before learning it is off. The Brief's acceptance criteria
are the contract; this plan is the sequence that meets them.

### Standards grounding

No `docs/standards/` index and no `.claude/standards.yaml` exist at the resolution root, and the
session is non-interactive, so the standards ladder takes its last rung: this repository's own
`docs/conventions/**` is the inferred standards root (the Brief and every plugin README cite it),
and the assumption is surfaced here rather than persisted. Sections loaded for the surfaces this
plan touches, all read this session:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/conventions/hook-precision/README.md` | The discipline (repro-first stay-quiet case in the co-located `*.test.sh`) | team |
| `docs/conventions/hook-budget/README.md`, `.claude/rules/hook-budget.md` | rules 1 to 3; always-on cost must state its measured share in the README | team |
| `docs/conventions/hook-config-delivery/README.md` | channel B (`CLAUDE_PLUGIN_OPTION_*` mirror with in-script default), never `${user_config.*}` in `hooks.json` | team |
| `docs/conventions/hook-telemetry/README.md` | envelope 1.0 additive-only; sink parses JSON, never crashes, never writes stdout | team |
| `docs/conventions/hook-observability/README.md` | `statusMessage` on every handler; visible skips; `# silent-skip-ok:` annotation for a jq-free quiet exit (Q9 names it) | team |
| `docs/conventions/config-cascade/README.md` | line 121: no plugin writes the consumer's `.gitignore`; declared exceptions in the Implementers table | team |
| `docs/conventions/topic-docs/README.md` | 589-608: the self-ignoring `*` guard at a resolved root, announced on creation | team |
| `docs/conventions/retired-conventions/README.md` | manifest grammar and fields; the two fixed setup lines; helper copy synced | team |
| `docs/conventions/upstream-drift/README.md` | four-part record (claim, basis, as-of, recheck); observability bar for triggers; raw fetch route | team |
| `docs/conventions/native-references/README.md` | presence-gated phrasing for every native surface | team |
| `docs/PLUGIN-PHILOSOPHY.md` | 396-600: setup contract; narrow-write `apply`; no no-op `apply`; retirement declaration mandatory | team |
| `docs/adr/0003-*.md` | measure before shipping; report the number in the PR | team |
| `.claude/rules/pr-body-contract.md`, `AGENTS.md` | draft-first PRs; closing-keyword line plus the four sections; `affected-tests.sh --run` | team |

No personal overlay (`docs/standards/*.local.md`, `~/.claude/standards/`) exists on this host.

### Approach

Three PRs, in the order the handoff fixed. PR A and PR B are independent of the pipeline and were
confirmed separately by the operator; PR C is the pipeline. Every PR opens as a draft and flips to
ready once its phases' sanity checks are green.

| PR | Phases | Branch | Plugins bumped |
|---|---|---|---|
| A | 0, 1 | `claude/posttool-hooks-review-ji6rl5` (this branch) | guardrails 0.31.6 |
| B | 2 | `claude/posttool-killswitch-hoist-<suffix>` cut from `origin/main` after A opens | guardrails, actionlint, bash-format, biome-format, eol-normalizer, go-format, instruction-placement, markdown-format, powershell-format, ruff-format, typos-format, source-control (patch each), claude-ops 0.41.14 |
| C | 3 to 8 | `claude/hook-logging-pipeline-<suffix>` cut from `origin/main` after B opens | claude-ops 0.41.15 |

Each later branch merges `origin/main` before opening its PR; the topic docs ride PR A, and PR C
carries the final topic-doc updates and the harness prune.

### Files affected (whole plan)

| File | Action | What changes |
|---|---|---|
| `plugins/guardrails/hooks/skill-reference-verify.sh` | Modify | `build_plugin_index` becomes one batched `jq` keyed on `input_filename` |
| `plugins/guardrails/hooks/cli-flag-verify.sh` | Modify | pure-bash pre-gate against `$BINS`; in-parent cache read, verifier spawned only on a miss |
| `plugins/guardrails/lib/verification/verify-cli-flag.sh` | Modify | `[[ -d ]]` before `mkdir -p`; bash mtime compare; `[[ =~ ]]` match |
| `plugins/guardrails/hooks/{skill-reference-verify,cli-flag-verify}.test.sh`, `plugins/guardrails/lib/verification/verify-cli-flag.test.sh` | Modify | repro-first timing and equivalence cases |
| `scripts/check-killswitch-hoist.sh`, `scripts/check-killswitch-hoist.test.sh` | Modify | discovery widened to PostToolUse; PostToolUse fixture |
| 15 PostToolUse-registered hook scripts (listed in Phase 2) | Modify | inlined kill switch above the `source` line; `hook::check_enabled` call removed |
| `plugins/claude-ops/hooks/session-event-log.sh` (+ `.test.sh`) | Create | the per-event producer; sources nothing |
| `plugins/claude-ops/hooks/session-retention.sh` (+ `.test.sh`) | Create | SessionEnd retention with detached pre-prune |
| `plugins/claude-ops/hooks/hook-telemetry-sink.sh` (+ `.test.sh`), `.claude/hooks/hook-telemetry-sink.sh` (+ `.test.sh`) | Modify | new root; guard check before write; per-session route when the envelope carries `session_id` |
| `plugins/claude-ops/hooks/hooks.json` | Modify | top-level `description`; generated producer rows on every registry event; `SessionEnd` retention row |
| `plugins/claude-ops/hooks/hook-events.registry.json` | Create | generated registry, four-part stamped |
| `scripts/gen-hook-event-registry.sh` (+ `.test.sh`) | Create | fetch, parse, stamp, regenerate rows; `--check` offline |
| `plugins/claude-ops/.claude-plugin/plugin.json` | Modify | seven `userConfig` keys; version; description sentence for the pipeline |
| `plugins/claude-ops/README.md` | Modify | options table regenerated; storage, retention, cost paragraph |
| `plugins/claude-ops/retirements.yaml`, `plugins/claude-ops/lib/check-retirements.sh` | Create | record for `.claude/observability/hook-events.jsonl`; synced helper copy |
| `plugins/claude-ops/skills/setup/SKILL.md`, `evals/evals.json` | Modify | `check \| apply`; guard probe and narrow write; retirement lines; new evals |
| `plugins/claude-ops/skills/observability/{SKILL.md,context/data-sources.md,context/output-format.md,context/read-routing.md,context/privacy.md,scripts/probe-observability-state.sh,scripts/clean.sh}` (+ tests) | Modify | per-session scope; queries over `sessions/*.jsonl`; toggles-and-retention INFO section; new root |
| `docs/conventions/hook-observability/README.md` | Modify | names `# silent-skip-ok: <reason>` explicitly (Q9) |
| `docs/conventions/hook-telemetry/README.md` | Modify | sink routing note: envelopes carrying `session_id` land per session |
| `.gitignore` (this repo) | Modify | `.observability/` line beside the existing `.claude/observability/` line |
| `docs/topics/hook-logging-pipeline/harness/` | Delete | pruned in PR C per topic-docs |

### Phases

#### Phase 0: Baseline measurements [TODO]

Re-measure before touching anything (ADR-0003 rule 1; the Brief's "each re-measured"). PR #3732
changed the library's startup path after the handoff figures were taken, so every number is
re-captured, not reused.

- [ ] `bash docs/topics/hook-logging-pipeline/harness/measure-posttooluse.sh 15` in this
  checkout; keep the raw table under the topic's memory slice `baselines/` (never committed).
- [ ] Cold cache for `cli-flag-verify`: clear `${XDG_CACHE_HOME:-$HOME/.cache}/guardrails/cli-flag-cache`,
  run the hook once on a markdown payload citing four `DEFAULT_BINS` commands, time it.
- [ ] PATH tax: `strace -f -e trace=execve -c bash plugins/guardrails/hooks/cli-flag-verify.sh < <payload>`
  on a warm cache; record failed `execve` count. If `strace` is absent, record "unmeasured" and
  the reason; do not estimate.
- [ ] Record the distilled figures (not the capture path) in FINDINGS.md under a dated
  "Re-measurement 2026-09-05" heading.
- **Sanity Check:** `grep -c 'Re-measurement 2026-09-05' docs/topics/hook-logging-pipeline/FINDINGS.md` is 1; the memory slice holds `baselines/posttooluse-<date>.txt`.

#### Phase 1: Verifier-lane fix (PR A) [TODO]

Review: code-design

The four patch shapes in the Brief, each with a repro-first test per `hook-precision`. Order is by
measured payoff.

- [ ] **1a** `skill-reference-verify.sh` `build_plugin_index` (lines 200-213): replace the
  per-manifest `jq` + `tr` loop with one `jq -r` over all manifests emitting
  `input_filename \t name \t skills-joined` and one `while read` fill of the two maps. Test:
  a fixture tree with three manifests (one with `skills` array, one with a string, one with
  neither) asserts identical `PLUGIN_DIR` / `PLUGIN_SKILL_PATHS` contents before and after, and a
  timing case asserts the index builds under 50 ms on the real tree.
- [ ] **1b** `cli-flag-verify.sh` pre-gate: before `emit_fragments`, exit 0 unless
  `$SCAN_CONTENT` contains one of the `$BINS` tokens as a whole word (pure bash loop over
  `$BINS` with `[[ "$SCAN_CONTENT" == *"$bin"* ]]`, then the existing extraction decides). Test:
  prose-only markdown mentioning no binary stays quiet in under 15 ms; markdown citing `gh` still
  fires the MUST-fire case.
- [ ] **1c** `cli-flag-verify.sh` loop: compute the cache key in the parent, `[[ -s cache ]]` and
  the 24 h mtime compare in bash, and only spawn `verify-cli-flag.sh` on a miss. On a hit, do the
  `[[ =~ ]]` flag match in the parent. Test: with a warm cache the hook makes zero
  `verify-cli-flag.sh` spawns (assert via a PATH-shimmed counter) and reports the same findings.
- [ ] **1d** `verify-cli-flag.sh` lines 103, 115, 163 per the Brief. Test: the existing 11-case
  suite passes unchanged; a new case pins `[[ =~ ]]` against the `--save-dev` / `--save-developer`
  prefix trap.
- [ ] Re-measure with the harness; record before/after in FINDINGS.md and in the CHANGELOG entry
  (ADR-0003 rule 2).
- [ ] `plugins/guardrails` 0.31.5 to 0.31.6; CHANGELOG entry at the head.
- [ ] `scripts/affected-tests.sh --run`; shellcheck; open PR A as draft with the body contract.
- **Sanity Check:** harness "with refs" row for `skill-reference-verify` under 100 ms; `bash plugins/guardrails/hooks/skill-reference-verify.test.sh` and the two other suites exit 0; `scripts/affected-tests.sh --run` exit 0; `jq -r .version plugins/guardrails/.claude-plugin/plugin.json` prints `0.31.6`.

#### Phase 2: PostToolUse kill-switch hoist (PR B) [TODO]

Extend, never recreate: `scripts/check-killswitch-hoist.sh` is on `main` (PR #3727, `5f5665ee`).

- [ ] Cut the branch from `origin/main`.
- [ ] Widen discovery: the `jq` at the `for hooks_json` loop reads
  `.hooks.PreToolUse[]?, .hooks.PostToolUse[]?` (a launcher's arguments still resolve as today);
  the "no guards found" refusal and the final count line say "PreToolUse and PostToolUse".
  Header comment and the NOT SCANNED wording updated to match.
- [ ] Add a PostToolUse fixture pair to `scripts/check-killswitch-hoist.test.sh`: a hoisted
  PostToolUse hook passes; a reversed one fails with "BELOW the source". The `hooks_json` helper
  gains an event parameter defaulting to `PreToolUse`.
- [ ] Hoist the 15 PostToolUse-registered scripts, one line each, verbatim shape
  `[[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0` above the first
  `source`, and delete the `hook::check_enabled "<NAME>"` line (the gate rejects both forms
  coexisting): `actionlint-check`, `bash-format`, `biome-format`, `eol-normalizer`, `go-format`,
  `index-drift`, `markdown-format`, `powershell-format`, `ruff-format`, `typos-format`,
  `cli-flag-verify`, `skill-reference-verify`, `stale-path-verify`, `worktree-add-claim-gate`,
  `skill-usage-audit`. `<NAME>` is the argument each script passes to `hook::check_enabled` today.
- [ ] Each touched plugin: patch bump plus a CHANGELOG entry stating the measured disabled-cost
  recovery for its shape (standalone recovers the library; the three guardrails verifiers run
  under `run-guards.sh` and recover almost nothing, said plainly). `claude-ops` takes 0.41.14 with
  its entry at the head; the sibling lane's 0.41.13 entry, when it lands, sits below it.
- [ ] Measure one standalone formatter disabled, before and after, with the harness method;
  record in FINDINGS.md.
- **Sanity Check:** `scripts/check-killswitch-hoist.sh` exit 0 and its count line reports 15 more guards than on `main`; `bash scripts/check-killswitch-hoist.test.sh` exit 0 with the two new cases; `grep -L 'hook::check_enabled' <the 15 scripts>` lists all 15; `scripts/affected-tests.sh --run` exit 0; `scripts/check-changelog-parity.sh` exit 0.

#### Phase 3: Per-session producer, sink routing, ignore guard (PR C core) [TODO]

Review: code-design

The integration slice: one event in, one line in the right file, or nothing at all when off.

- [ ] **Pre-flight (contract migration):** `git grep -n 'hook-events.jsonl\|\.claude/observability'`
  across the repo; list every parse path (sink, repo-local sink copy, probe, clean, data-sources,
  read-routing, privacy, README, plugin.json, three tests, root `.gitignore`). Each becomes a
  checkbox in Phase 7's inventory.
- [ ] `plugins/claude-ops/hooks/session-event-log.sh`, sourcing nothing. Line 1 after the shebang
  and `set -uo pipefail`: `[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED:-false}" == "true" ]] || exit 0`
  (default **false**: the gate admits `:-false`). Then: `EPOCHREALTIME` start; bounded stdin
  read (`read -r -t "${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}" -N 65536` loop); bash-regex
  extraction of `session_id`, `hook_event_name`, `prompt_id`, `tool_use_id`, `agent_id`,
  `tool_name`, `tool_input.file_path`, `reason`, `model`; category filter from
  `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES` (default all); exit 0 without writing when
  `session_id` or `hook_event_name` is empty; root from
  `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR` (default `.observability/claude`, containment
  validated like `skill_usage_dir`) under `CLAUDE_PROJECT_DIR`, else the payload `cwd`; refuse
  to write unless `<root>/.gitignore` exists and its first non-comment line is `*` (file test plus
  one `read`, no spawn); `mkdir -p <root>/sessions` only on the first write; one
  `printf '%s\n' >> <root>/sessions/<session_id>.jsonl`. Values are JSON-escaped by a 12-line
  bash escaper for `"`, `\`, and control characters; ids are further constrained to
  `[A-Za-z0-9._-]` and a line is dropped when they are not.
- [ ] Sink (`hook-telemetry-sink.sh` and the repo-local copy): root moves to the same resolver;
  the same guard check precedes the write; when the envelope carries a non-empty `session_id`
  the line goes to `sessions/<session_id>.jsonl` with the spine field names and `source:
  "envelope"`, otherwise to `<root>/hook-events.jsonl` as today (the flock path stays for that
  file only).
- [ ] `hooks.json`: top-level `description`; producer rows come from Phase 5's generator, so this
  phase registers the producer by hand on `PostToolUse`, `PostToolUseFailure`, `PreToolUse`,
  `SessionStart`, `SessionEnd`, `PermissionDenied`, `PreModelSwitch`, `PostModelSwitch`,
  `SubagentStart`, `SubagentStop` (the decision-carrying set) with `statusMessage` and
  `timeout: 5`, and Phase 5 replaces those rows wholesale.
- [ ] `plugin.json` `userConfig`: `session_event_log_enabled` (boolean, default false),
  `session_event_log_dir`, `session_event_log_categories`, `session_log_keep_sessions` (number,
  30), `session_log_keep_days` (number, 14), `session_log_pre_prune_command` (string, unset),
  `hook_telemetry_dir` is NOT added (the sink shares `session_event_log_dir`). README options
  table regenerated with `python3 scripts/sync-plugin-options-docs.py`.
- [ ] Tests: `session-event-log.test.sh` drives the script black-box (`env -u ... bash "$HOOK" <<<"$INPUT"`)
  for: disabled exits 0 and writes nothing; enabled with no guard writes nothing and exits 0;
  enabled with guard writes one line carrying the full spine (`jq -e 'has("session_id") and has("hook_event_name")'`);
  a payload without `session_id` writes nothing; category filter drops a non-listed event; a
  hostile `session_id` (`../x`) writes nothing; two sessions produce two files; 33 parallel
  invocations for one session produce 33 intact lines. Sink suite extended for the two routes and
  the guard refusal. `check-silent-skips.sh` passes because the script has no `command -v` gate
  (no jq anywhere in it).
- [ ] Measure: disabled cost with the harness method (target: within 1.5 S of the floor), enabled
  cost, and the sink's cost; record in FINDINGS.md and the README budget paragraph.
- **Sanity Check:** `grep -L 'hook-utils.sh' plugins/claude-ops/hooks/session-event-log.sh` prints the path; `bash plugins/claude-ops/hooks/session-event-log.test.sh` exit 0; harness disabled row for the producer at or below 1.5 S; `python3 scripts/sync-plugin-options-docs.py --check` exit 0; `scripts/check-silent-skips.sh` exit 0.

#### Phase 4: SessionEnd retention with detached pre-prune [TODO]

- [ ] `plugins/claude-ops/hooks/session-retention.sh`, sourcing nothing, same kill switch as the
  producer (retention is meaningless when logging is off), registered on `SessionEnd` with
  `timeout: 1` (the plugin timeout cannot raise the 1.5 s budget; the value documents intent).
  Reads `reason` and `session_id` from stdin; appends nothing itself (the producer already logged
  `SessionEnd`).
- [ ] Policy: list `sessions/*.jsonl` newest-first by mtime (`ls -t`, one spawn; a pure-bash
  fallback is not attempted). A file is kept when it is among the newest `keep_sessions` OR its
  mtime is within `keep_days`; everything else is doomed. Tolerate an empty directory.
- [ ] Prune: with no `session_log_pre_prune_command`, `rm -f` the doomed files. With one, `mv`
  them into `<root>/prune-pending/<epoch>/` (one rename each, atomic on one filesystem), spawn
  `(<command> "<root>/prune-pending/<epoch>" >/dev/null 2>&1 &)` fully detached, and delete any
  `prune-pending/*` directory older than 24 h at the start of the next run. The command is a
  consumer-supplied string executed through `bash -c`; the README says so and names the input
  contract (one directory argument).
- [ ] Tests: 100 fixture files with staged mtimes; assert the kept set equals the union rule;
  timed run under 1.5 s (assert under 1000 ms to leave headroom); a `sleep 30` pre-prune command
  does not delay exit beyond 1000 ms; a failing command leaves `prune-pending/` intact and the
  next run sweeps it after the age threshold; disabled exits 0 touching nothing.
- [ ] `clean.sh` gains a `sessions/` branch applying the same rule for manual runs (dry-run first,
  as today), so the two retention surfaces share one policy.
- **Sanity Check:** `bash plugins/claude-ops/hooks/session-retention.test.sh` exit 0 including the timing case; `jq '.hooks.SessionEnd[0].hooks[0].command' plugins/claude-ops/hooks/hooks.json` names `session-retention.sh`.

#### Phase 5: Generated event registry and hooks.json rows [TODO]

- [ ] `scripts/gen-hook-event-registry.sh`: `curl -sS -L https://code.claude.com/docs/en/hooks.md`,
  parse the lifecycle table (rows between the `| Event` header and the next blank line; the name
  is the first backticked cell, the "when" text the second cell), map each name to a category by a
  table in the script (unknown names get `other` and a WARN on stderr), stamp each entry with the
  four parts (claim, basis URL with anchor, as-of date, recheck trigger), and write
  `plugins/claude-ops/hooks/hook-events.registry.json` sorted by name. A run whose table parses to
  fewer than 25 rows exits 2 without writing (the page shape changed; a silent empty registry is
  the failure this guards).
- [ ] Same script regenerates the producer rows in `hooks.json`: one `SessionEnd` row is
  preserved for retention; for every registry event one row registering `session-event-log.sh`
  (no matcher, `statusMessage`, `timeout: 5`); the nine existing audit handlers and their order
  are preserved via `jq` merge, not rewritten. `--check` re-derives the rows from the committed
  registry and diffs against `hooks.json` offline (no network), exit 1 on drift; CI runs
  `--check`. `--fetch` is the operator path.
- [ ] Every entry's phrasing follows `native-references`: the registry states what the reference
  documented on the as-of date, never that an event exists in the running binary; the producer
  itself is presence-gated by construction (a row on an event the binary does not fire costs
  nothing).
- [ ] Tests: parser against a saved fixture copy of the table (committed under
  `scripts/fixtures/`), the under-25-rows refusal, `--check` clean and drifted, and the merge
  preserving the nine handlers byte-for-byte.
- **Sanity Check:** `jq '[.[] | select(has("recheck") and has("basis") and has("as_of"))] | length == length' plugins/claude-ops/hooks/hook-events.registry.json` prints true and `jq length` prints at least 30; `scripts/gen-hook-event-registry.sh --check` exit 0; `bash scripts/gen-hook-event-registry.test.sh` exit 0; `jq -r .description plugins/claude-ops/hooks/hooks.json` is non-empty.

#### Phase 6: Setup guard and retirement record [TODO]

- [ ] `plugins/claude-ops/skills/setup/SKILL.md` leaves the check-only carve-out: `argument-hint`
  becomes `check | apply`; the description's "Check-only" sentence is rewritten; `check` gains probe
  5 (guard present at `<session_event_log_dir>/.gitignore` with `*` as its first non-comment line;
  INFO when logging is off, FAIL with the `apply` remediation when on and absent; FAIL, never
  written, when the resolved dir is the repo root); `apply` is bounded to creating that one file
  (announced, idempotent, "already configured" on re-run) and nothing adjacent, then the
  tracked-vs-ignored pair (`git check-ignore -v` matches, `git ls-files --error-unmatch` fails)
  is reported as evidence. Rationale text cites config-cascade line 121 and the topic-docs guard
  precedent, so the choice reads as the sanctioned shape and not an exception.
- [ ] `plugins/claude-ops/retirements.yaml`, first record `claude-ops-r001`: `kind: file`,
  `path: .claude/observability/hook-events.jsonl`, `action: migrate`, successor prose pointing at
  the new root; `plugins/claude-ops/lib/check-retirements.sh` synced from the fleet copy; the two
  fixed setup lines added verbatim; one eval for the record. The `.claude/observability/` directory
  and its ignore line are not retired (the skill-usage store and the OTEL store still use them).
- [ ] Evals: add "writes only the guard", "refuses a root-equivalent dir", and "reports the
  retirement" cases.
- **Sanity Check:** `bash plugins/claude-ops/lib/check-retirements.sh --manifest plugins/claude-ops/retirements.yaml` exit 0 in a clean fixture and exit 1 in one carrying the old file; `grep -c 'check-retirements.sh' plugins/claude-ops/skills/setup/SKILL.md` is at least 2; `bash scripts/check-changed-skills.sh <base>` exit 0; the CI retirement-wiring check passes both directions.

#### Phase 7: Reader extension and path migration [TODO]

- [ ] `data-sources.md`: `HOOK_ROOT` from the same option (documented as a flag the skill takes,
  never read from `CLAUDE_PLUGIN_DATA`); every `jq -s "$HOOK_LOG"` becomes
  `jq -s "$HOOK_ROOT"/sessions/*.jsonl "$HOOK_ROOT"/hook-events.jsonl` with the `.ts` window
  unchanged; a new "Per-session report" section: which hooks fired (`source == "envelope"` rows
  grouped by `hook`), blocked (`status == "blocked"`), rewrote (`changed == true`, empty until a
  producer emits it), duration per hook, and the session's event timeline from
  `source == "event-log"` rows; a "Toggles and retention in effect" section rendering the six
  options and the guard state from a `probe-observability-state.sh --pipeline` line.
- [ ] `SKILL.md`: `session` scope resolves to the newest `sessions/*.jsonl` by mtime, and
  `session:<id>` names one; the data-sources table row names the new root; the gotcha about
  `session_id` drift is rewritten to say the join is exact for pipeline rows and time-proximity
  only for legacy rows. `output-format.md` drops "Per-session detail" from the intentional
  omissions and adds the per-session template. `read-routing.md`, `privacy.md`, the README, and
  `plugin.json`'s description follow the path.
- [ ] `probe-observability-state.sh`: `--hook-events` counts lines across the new root's files;
  `--pipeline` prints the toggle and guard summary. The byte-for-byte ORIG fixtures in its test are
  regenerated for the new path (the suite's design is kept).
- [ ] File inventory (ticked in the PR):
  `[ ] hook-telemetry-sink.sh` MODIFY, `[ ] .claude/hooks/hook-telemetry-sink.sh` MODIFY,
  `[ ] hook-telemetry-sink.test.sh` (both) MODIFY, `[ ] probe-observability-state.sh` MODIFY,
  `[ ] probe-observability-state.test.sh` MODIFY, `[ ] clean.sh` MODIFY, `[ ] data-sources.md`
  MODIFY, `[ ] claude-observability.test.sh` MODIFY, `[ ] read-routing.md` MODIFY,
  `[ ] privacy.md` MODIFY, `[ ] output-format.md` MODIFY, `[ ] SKILL.md` MODIFY,
  `[ ] plugins/claude-ops/README.md` MODIFY, `[ ] plugin.json` MODIFY, `[ ] .gitignore` MODIFY,
  `[ ] skill-usage-audit.sh` KEEP (its store stays), `[ ] claude-ops-paths.sh` KEEP,
  `[ ] otel/*` KEEP.
- **Sanity Check:** `git grep -n '\.claude/observability/hook-events' -- ':!docs/topics' ':!**/CHANGELOG.md' ':!plugins/claude-ops/retirements.yaml'` returns nothing; `bash plugins/claude-ops/skills/observability/claude-observability.test.sh` exit 0 with a new multi-file fixture and a `session:<id>` case; `bash .../probe-observability-state.test.sh` exit 0; invoking the per-session queries against a sample session file lists fired, blocked and per-hook duration rows.

#### Phase 8: Docs, versions, prune, PR C [TODO]

- [ ] `docs/conventions/hook-observability/README.md`: one paragraph naming
  `# silent-skip-ok: <reason>` as the annotation, where it goes (the line above the quiet exit),
  and that `check-silent-skips.sh` reads it (Q9).
- [ ] `docs/conventions/hook-telemetry/README.md`: a sink-routing note under the sink contract
  (envelopes carrying `session_id` route per session; 1.0 envelopes route to the shared file) and
  a pointer to the envelope 1.1 follow-up (see Open questions).
- [ ] `plugins/claude-ops` 0.41.15 with the CHANGELOG entry at the head (above 0.41.14 from PR B
  and above the sibling's 0.41.13 wherever it lands); `plugin.json` description gains one sentence
  for the pipeline (the "Twelve skills" count is unchanged; `check-skill-count-claims.sh` stays
  green).
- [ ] FINDINGS.md gains the pipeline measurements; `harness/` is deleted (topic-docs contract tier
  is pruned before merge) with FINDINGS.md's method section carrying enough to reproduce.
- [ ] Toggle cycle: enable, fire ten events, disable, fire ten, enable, fire ten; `ls -R
  .observability/claude/` shows only `.gitignore`, `sessions/<id>.jsonl`, and (when configured)
  `prune-pending/`.
- [ ] `scripts/affected-tests.sh --run`; `/review:code-review` on the diff; PR C as draft with the
  body contract; flip to ready when green.
- **Sanity Check:** `grep -c 'silent-skip-ok' docs/conventions/hook-observability/README.md` is at least 3; `test ! -d docs/topics/hook-logging-pipeline/harness`; `scripts/check-changelog-parity.sh` exit 0; `scripts/affected-tests.sh --run` exit 0; the toggle-cycle listing matches.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Add `session_id` to the telemetry envelope now (edit `hook::emit_telemetry`) so every fleet producer's rows land per session | `lib/hook-utils.sh` and its 17 copies are off-limits to this lane (handoff constraint); the bump is #930's deferred change | The operator releases `hook-utils.sh` to this lane, or #930 lands first: then the sink's per-session route serves every producer with no further change here |
| One producer script per event (33 scripts) | 33 files to keep in sync for one behavior; the registry generator already parameterizes by event name | A per-event payload grows beyond what one `case` block reads cleanly |
| Session-tag envelope rows at write time by "newest active session in this repo" | Wrong under concurrent sessions in one repo, and a wrong `session_id` violates the spine criterion worse than an absent one | The reader proves concurrent same-repo sessions never occur for this consumer (it cannot) |
| Registry `--check` fetches live in CI | Network flake fails CI for a doc change upstream nobody made | CI gains a cached, retried fetch step the repo already trusts for another gate |
| Inline delete with the pre-prune command run inline | A slow archiver exhausts the 1.5 s budget and the prune never happens (Brief Q19) | `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` becomes the documented consumer default |
| Appended root `.gitignore` line (work-items shape) | Needs a declared exception, a config-cascade row and the two-probe verification; the self-ignoring guard needs none and the sink can verify it without a spawn | The operator wants `.observability/` covered by one root line for every tool at once |
| Split PR C into producer/retention and reader/setup halves | The off-then-on and per-session-report criteria are end-to-end; a half-landed pipeline has partial state by definition | PR C exceeds review appetite (say 40 files); then split at the Phase 5/6 boundary |

### Test strategy

Which test type each file needs follows the `testing` plugin's classification where it is
installed (`/testing:plan`); the repo's own rule is simpler and binding: every new `.sh` ships a
co-located `<stem>.test.sh` or `affected-tests.sh` errors. TDD throughout, repro-first for the
verifier fixes (`hook-precision`): each timing or stay-quiet case is written to fail against the
unmodified hook, then the fix is applied.

Test boundaries the tests drive (existing unless marked new):

- `plugins/guardrails/hooks/skill-reference-verify.sh` stdin-to-stdout contract, with
  `build_plugin_index` exercised through a fixture tree (existing).
- `plugins/guardrails/hooks/cli-flag-verify.sh` stdin-to-stdout contract plus a PATH shim counting
  `verify-cli-flag.sh` spawns (existing contract, new shim).
- `plugins/guardrails/lib/verification/verify-cli-flag.sh` CLI (existing).
- `scripts/check-killswitch-hoist.sh` fixture-tree contract (existing).
- `plugins/claude-ops/hooks/session-event-log.sh` stdin-to-file contract (**new**).
- `plugins/claude-ops/hooks/session-retention.sh` directory-to-directory contract (**new**).
- `plugins/claude-ops/hooks/hook-telemetry-sink.sh` envelope-to-file contract (existing, new route).
- `scripts/gen-hook-event-registry.sh` fixture-table-to-JSON and `--check` (**new**).
- The `data-sources.md` jq text copied into `claude-observability.test.sh` (existing; the
  copy-by-hand discipline stays).
- Setup skill behavior through `evals/evals.json` (existing; no shell suite, the write is a
  markdown instruction, not a script).

Edge cases named above per phase; the ones that decide correctness are: hostile `session_id`,
missing `session_id`, guard absent, root-equivalent dir, 33 parallel appenders, the under-25-rows
registry refusal, and the 1.5 s retention bound on 100 files.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Per-hook duration for a session stays unavailable until the envelope carries `session_id` | High (certain until #930) | Med | The reader labels envelope rows as legacy when they lack a session; the acceptance criterion is met for pipeline rows and reported as partial for legacy rows in the PR; follow-up filed |
| A producer row on every event doubles the per-event spawn count for consumers who turn it on | Med | Med | Default off; measured on-cost stated in the README; category filter drops noise; `PostToolBatch` left available |
| Widening the hoist gate to PostToolUse fails on a script this plan did not list | Low | Low | The 15-script list came from a jq survey of every `hooks.json`; the gate run in Phase 2 is the check |
| The sibling's 0.41.13 CHANGELOG entry merges between PR B and PR C | Med | Low | Entries are placed at the head; parity gate only requires newest-first, so a merge conflict is textual, not semantic |
| `ls -t` mtime ordering differs on Windows Git Bash | Low | Low | Retention keys on mtime through `ls -t` on both; a recheck item under the Windows probe already owed |
| The hooks reference table changes shape and the generator parses zero rows | Low | Med | Exit 2 under 25 rows; the committed registry stays authoritative until a human re-runs |
| `check-silent-skips.sh` flags the jq-free producer's quiet exits | Low | Low | The producer has no `command -v` gate; its data-driven exits are not the shapes the gate inspects; verified in Phase 3's sanity check |

### Execution-shape analysis [EXEC-SHAPE]

File-overlap matrix: Phase 1 (guardrails verifiers) and Phase 2 (the same three verifiers plus
12 others) overlap on `cli-flag-verify.sh` and `skill-reference-verify.sh`; Phases 3 to 8 share
`hooks.json`, `plugin.json`, the sink, and the README. Phase 5 depends on Phase 3's producer;
Phase 6 and 7 depend on Phase 3's option names; Phase 8 depends on everything.

Dependency graph: 0 → 1 → 2 (branch cut after A opens) → 3 → {4, 5} → {6, 7} → 8. Phases 4 and 5
are file-disjoint (retention script and test vs generator, registry, hooks.json rows) but Phase 4
adds a `SessionEnd` row to `hooks.json` that Phase 5's merge must preserve, so they run in order.

Recommended shape: **fully sequential**, main session. Parallel dispatch would save under 100 LOC
of independent work (Phase 4 vs 5) and every phase edits `hooks.json` or the CHANGELOG. Cost note:
one session, no multiplier.

| Phase | Surface | Basis |
|---|---|---|
| 0 | main-session | timing runs need a quiet host; a sub-agent's reads add noise |
| 1 | main-session | judgment per patch shape; measurements interleave with edits |
| 2 | main-session | 15 one-line edits plus version bumps; mechanical but fleet-wide, better reviewed inline |
| 3 | main-session | the integration slice; contracts settle here |
| 4, 5 | main-session | small, sequential by the `hooks.json` dependency |
| 6, 7 | main-session | markdown-heavy edits under the skill-quality gate |
| 8 | main-session | PR assembly and the toggle-cycle probe |

Sequential fallback: not applicable, already sequential.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Ignore guard is a self-ignoring `.gitignore` containing `*` inside the observability root, written by setup `apply`, verified by the sink with a file test `[FALLBACK — confirm or override]` | Phase 3's refusal check; Phase 6's `apply` scope; no config-cascade exception row | `docs/conventions/config-cascade/README.md:121` forbids editing the consumer root; `topic-docs/README.md:589-608` is the sanctioned guard shape this repo's own `.work/.gitignore` already uses |
| The guard sits at `.observability/claude/`, not `.observability/` `[FALLBACK — confirm or override]` | Phase 6 probe path; the README's "one rule covers the tree" claim narrows to this plugin's subtree | A shared parent root belongs to no plugin; the setup contract bounds `apply` to plugin-owned artifacts (`PLUGIN-PHILOSOPHY.md:535-539`) |
| Only `hook-events.jsonl` migrates; `skill-usage.jsonl` and the OTEL store stay under `.claude/observability/` `[EXEC-SHAPE]` | Phase 6 retirement record is `kind: file`; Phase 7 inventory keeps `skill-usage-audit.sh` and `otel/*` | The Brief names only hook events; the other two stores have their own retention and readers |
| Envelope rows without `session_id` keep landing in the shared file; only rows carrying one route per session `[FALLBACK — confirm or override]` | Phase 3 sink routing; the per-session report labels legacy rows | Hooks receive no session id in their environment (hooks reference, common input fields and handler fields, fetched 2026-09-05); the envelope change is #930's and touches the off-limits library |
| Pre-prune hands the archiver a moved-aside directory and the physical delete is deferred to the next run `[FALLBACK — confirm or override]` | Phase 4 prune mechanics | Brief Q19 requires detached execution; a detached command racing an immediate unlink loses files, so the rename is what makes both true |
| The producer's default is `false` and the retention hook shares its switch `[EXEC-SHAPE]` | Phase 3 kill switch spelling `:-false`; Phase 4 gate | Brief Q6 "plugin default-OFF"; the hoist gate admits the `:-false` shape (`check-killswitch-hoist.sh` SWITCH_RE) |
| Three PRs, each cutting from `origin/main` after the previous opens; claude-ops takes 0.41.14 in PR B and 0.41.15 in PR C `[EXEC-SHAPE]` | Approach table; Phase 2 and 8 version lines | PR #3727 bumped every touched plugin (`git show --stat 5f5665ee`); the Brief reserves 0.41.14 above the sibling's 0.41.13 |
| Registry `--check` is offline; the fetch is the operator path `[EXEC-SHAPE]` | Phase 5 CI wiring | Network in CI is a flake source the repo avoids elsewhere (no live fetch in any existing gate under `.github/workflows/ci.yml`) |
| The "rewrote" signal is a defined payload key (`changed`) that no producer emits yet `[FALLBACK — confirm or override]` | Phase 7 query exists and returns empty; a follow-up is named in Open questions | Formatter producers emit `data.findings` only (exploration, current-state section 2); formatter-side emission widens this lane into files it touches only for the hoist |

## Blast radius

**HIGH.** Hooks are infrastructure (a trigger on its own); the pipeline is a cross-cutting
observability concern; Phase 2 touches 15 scripts across 13 plugins; a new CI gate scope and a new
generated registry constrain future work. Reversible by revert, and every phase sits behind a
mechanically verifiable sanity check, which is what keeps this below CRITICAL.

Stress-test needed: Yes. `/planning:devils-advocate` in a fresh-context sub-agent after the
plan-reviewer pass.

## Stress-test summary

Pending: the plan-reviewer sub-agent (Step 3) and the devils-advocate pass (Step 4) run after this
draft is persisted; their verified findings are folded in here.

## Execution shape

Fully sequential, main session; see "Execution-shape analysis" above for the matrix, dependency
graph, and routing table.

## Open questions

- **Envelope 1.1 (`session_id`, `prompt_id`, `tool_use_id`, `agent_id` on the envelope).** The
  one change that makes per-hook duration available per session for every fleet producer. It
  edits `lib/hook-utils.sh`, which this lane may not touch. Default: file it as a follow-up citing
  #930 and this plan; the sink's per-session route is already forward-compatible. Escape hatch:
  the operator releases the library to this lane, and Phase 3 adds the four fields to
  `hook::emit_telemetry` (additive, 1.0 to 1.1) with the sync script run.
- **Formatter-side `changed` emission.** The "rewrote" answer is empty until formatters emit it.
  Default: follow-up issue after PR C. Escape hatch: add `changed: true` to the ten formatters'
  `data` in PR B, since that PR already edits each of them.
- **Windows/Git Bash recheck** for the atomic-append boundary and `ls -t` ordering: owed, not
  blocking (per-session files remove the shared-write path).

## Handoff to implementation

### User-approval gates

Every `[FALLBACK — confirm or override]` row in "Decisions made" is presented with a one-line
flip in the approval message; absent an override, implementation proceeds on the defaults. A
mid-flight change to an acceptance criterion stops and reports before continuing.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, main session, three draft PRs in the order A, B, C; the per-phase sanity checks above
are the phase boundaries; no sub-topic promotion (Phases 1 and 2 meet the independent-commit
criterion but are already sequenced by the handoff as their own PRs).

### Mechanical work

Commit per phase on the owning branch with the phase's plan-tag flip in the same commit; validate
with `scripts/affected-tests.sh --run` (a zero-suite file is an error), shellcheck, and the named
gates before each push; announce branch, PR title, and file list to every live peer before each
PR; draft first, flip to ready when green; prune `harness/` in PR C.
