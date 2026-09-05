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

### Brief corrections (2026-09-05, plan stage)

Recorded here rather than by editing the locked text above. Each was found by the fresh-context
plan review or the devils-advocate pass and verified against the file named.

- **Q6 "every documented event" needs an exclusion set.** The hooks reference states that a
  configured `WorktreeCreate` hook "replaces that default git behavior" and that a hook producing
  no path fails worktree creation; `MessageDisplay` "holds each batch until your hook returns";
  `FileChanged` uses its `matcher` to build the watch list, so a matcherless row watches nothing.
  A blanket producer row on those three would break `--worktree`, stall rendering, or register
  nothing. The registry therefore carries a per-event `producer` field (`observe` or
  `exclude: <reason>`), unknown event names default to excluded, and the generator never emits a
  row for an excluded event.
- **Q8 "existing `hook::check_enabled` left in place below" is superseded by the shipped gate.**
  `scripts/check-killswitch-hoist.sh` on `main` (PR #3727) reports a `hook::check_enabled` call as
  a violation before any other check, so the hoist deletes the call. Same outcome, one form.
- **Q13 "the sink refuses to log until the rule is present" becomes heal-on-first-write.** The
  guard lives inside the ignored tree, so a fresh clone or a `--worktree` session never carries it
  and a refusing producer logs nothing with no signal. The producer and sink create
  `<root>/.gitignore` containing `*` before their first line (announced through the observability
  report; `SessionStart` carries a one-time `systemMessage` only when healing is impossible), the
  `setup` skill's `apply` writes the same file idempotently and `check` reports it. The invariant
  Q13 protects, no unexplained untracked file, holds by construction either way; this is the
  topic-docs precedent (`docs/conventions/topic-docs/README.md:589-596`) applied.
- **"Captured assumptions" sibling-version paragraph has expired.** `origin/main` already carries
  claude-ops 0.41.13 and 0.41.14 (and is at 0.42.2), guardrails is at 0.32.1. Every bump in this
  plan is "next patch above `origin/main` at cut time"; no literal number below is a promise.
- **Acceptance criterion "how long each [hook] took" is scoped.** The envelope carries no
  `session_id` and the library that builds it is off-limits to this lane, so per-hook duration
  joins a session only for producers that put `session_id` into their envelope `data` (an
  additive key, allowed by `hook-telemetry` rule 1). This plan does that for the nine `claude-ops`
  audit hooks; the other fleet producers join by the same one-line addition, filed as a follow-up.
  The criterion "no logging hook sources `lib/hook-utils.sh`" applies to the three new pipeline
  scripts, not to those nine pre-existing envelope producers.

## Plan

Drafted 2026-09-05 by `/planning:plan` against the Brief, the verified exploration (`EXPLORE.md`
in the topic's memory slice, VERIFIED-WITH-NOTES), the doc-alignment pass in
[FINDINGS.md](FINDINGS.md), one fresh-context plan review (20 findings, all verified before
applying) and one `/planning:devils-advocate` pass (20 findings, same). Design gate: Tier B
early-exit at [design/design-resolution.md](design/design-resolution.md). Branch has merged
`origin/main` at `3ea592bb`.

### Goal

**What.** Land the three confirmed work allocations as three draft PRs in order: the verifier-lane
performance fix in `guardrails`, this lane's half of the kill-switch hoist with the CI gate widened
to PostToolUse, and the per-session hook-logging pipeline in `claude-ops` (producer, sink routing,
retention, generated event registry, setup guard, reader extension).

**Why.** Hook behavior is a black box today: no record carries a session id, the most expensive
PostToolUse hook spends 548 ms of a 622 ms run in a loop one batched `jq` replaces, and a disabled
hook still parses a 2,766-line library before learning it is off. The Brief's acceptance criteria,
as corrected above, are the contract.

### Standards grounding

No `docs/standards/` index and no `.claude/standards.yaml` exist at the resolution root, and the
session is non-interactive, so the standards ladder takes its last rung: this repository's own
`docs/conventions/**` is the inferred standards root, surfaced here and not persisted. Sections
loaded for the surfaces this plan touches, all read this session:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/conventions/hook-precision/README.md` | the discipline: repro-first stay-quiet case in the co-located `*.test.sh` | team |
| `docs/conventions/hook-budget/README.md`, `.claude/rules/hook-budget.md` | rules 1 to 3; always-on cost states its measured share in the README | team |
| `docs/conventions/hook-config-delivery/README.md` | channel B (`CLAUDE_PLUGIN_OPTION_*` with an in-script default), channel E (`${user_config.*}` in skill bodies); never `${user_config.*}` in `hooks.json` | team |
| `docs/conventions/hook-telemetry/README.md` | envelope additive-only (`data` keys may be added); sink parses JSON, never crashes, never writes stdout | team |
| `docs/conventions/hook-observability/README.md` | `statusMessage` on every handler; visible skips; `# silent-skip-ok:` (Q9) | team |
| `docs/conventions/config-cascade/README.md` | line 121: no plugin writes the consumer's `.gitignore` | team |
| `docs/conventions/topic-docs/README.md` | 60-66: contract slice committed on the branch only, pruned before merge; 589-608: the self-ignoring `*` guard | team |
| `docs/conventions/retired-conventions/README.md` | manifest grammar and fields; the two fixed setup lines; `scripts/sync-check-retirements.sh` carrier list | team |
| `docs/conventions/upstream-drift/README.md` | four-part record; observability bar (a recurring occasion qualifies); raw fetch route | team |
| `docs/conventions/native-references/README.md` | presence-gated phrasing for every native surface | team |
| `docs/PLUGIN-PHILOSOPHY.md` | 396-600: setup contract; narrow-write `apply`; no no-op `apply`; retirement declaration mandatory | team |
| `docs/adr/0003-*.md` | measure before shipping; report the number in the PR | team |
| `.claude/rules/pr-body-contract.md`, `AGENTS.md` | draft-first; closing-keyword line and four sections; `affected-tests.sh --run` | team |
| `lib/hook-utils.sh:1298-1350, 1450-1560` (read, never sourced) | the slice-and-`}`-tail bounded stdin read that survives a Win32 late-EOF pipe; `hook::read_supports_nchars` for the Bash 3.2 floor | team |

No personal overlay exists on this host.

### Approach

Three draft PRs. PR A and PR B are independent of the pipeline and were confirmed separately by
the operator; PR C is the pipeline. Each branch is cut from the previous PR's head so work never
waits, but a PR opens only after the previous one has **merged** and the branch has merged
`origin/main`, because A and B both edit the guardrails manifest, CHANGELOG head and two verifier
scripts, and B and C both bump `claude-ops`.

| PR | Phases | Branch | Bumps (rule: next patch above `origin/main` at cut time; expected today in parentheses) |
|---|---|---|---|
| A | 0, 1 | `claude/posttool-hooks-review-ji6rl5` (this branch) | guardrails (0.32.2) |
| B | 2 | `claude/posttool-killswitch-hoist-<suffix>`, cut from A's head | guardrails, actionlint, bash-format, biome-format, eol-normalizer, go-format, instruction-placement, markdown-format, powershell-format, ruff-format, typos-format, source-control, claude-ops (one patch each) |
| C | 3 to 8 | `claude/hook-logging-pipeline-<suffix>`, cut from B's head | claude-ops (one patch) |

Topic-docs lifecycle: this slice is contract tier, "committed on the task branch only; pruned
before merge". PR A's body carries the Brief and Plan in a `<details>` block and its last commit
before ready deletes `docs/topics/hook-logging-pipeline/`; B and C cherry-pick the slice back
onto their branches at cut time (so their PLAN tags advance on-branch) and prune it the same way
before their own ready flip. FINDINGS.md's numbers survive in the three PR bodies and the
CHANGELOG entries; nothing meets the ADR admission test (every choice here is revertible).

### Phases

#### Phase 0: Baseline measurements [DONE]

Re-measure before touching anything (ADR-0003 rule 1). PR #3732 changed the library's startup
path after the handoff figures were taken, so every number is re-captured.

- [ ] `bash docs/topics/hook-logging-pipeline/harness/measure-posttooluse.sh 15`; raw table to
  the topic's memory slice `baselines/` (never committed).
- [ ] Cold cache for `cli-flag-verify`: clear `${XDG_CACHE_HOME:-$HOME/.cache}/guardrails/cli-flag-cache`,
  run once on a markdown payload citing four `DEFAULT_BINS` commands, time it.
- [ ] PATH tax: `strace -f -e trace=execve -c bash plugins/guardrails/hooks/cli-flag-verify.sh < <payload>`
  warm; record the failed-`execve` count, or "unmeasured: strace absent". No estimates.
- [ ] Distilled figures into FINDINGS.md under "Re-measurement 2026-09-05".
- **Sanity Check:** `grep -c 'Re-measurement 2026-09-05' docs/topics/hook-logging-pipeline/FINDINGS.md` prints 1; `ls .work/hook-logging-pipeline/baselines/` lists one file.

#### Phase 1: Verifier-lane fix (PR A) [DOING]

PR A is [#3747](https://github.com/melodic-software/claude-code-plugins/pull/3747), opened as a
draft 2026-09-05 from `0a1237c1`; a fresh-context review of the first cut produced six findings,
all reproduced and fixed (one shared `lib/verification/cli-flag-cache.sh` for the cache rules;
raw non-whitespace separators in the batched read). PR B's branch is cut from the pre-prune head
so it carries this slice; A's prune commit follows.

Review: code-design

Four patch shapes, each with a repro-first test per `hook-precision`. Timing assertions live in
the harness rows recorded in FINDINGS.md; the suites assert structure (spawn counts, equivalence),
which is stable on shared CI runners.

- [ ] **1a** `skill-reference-verify.sh` `build_plugin_index` (lines 200-213): one `jq -r` over
  all manifests emitting `input_filename`, name, and joined skill paths, one `while read` filling
  the two maps. Test: fixture tree of three manifests (array `skills`, string `skills`, none);
  assert identical map contents before and after; assert exactly one `jq` invocation via a PATH
  shim counter (fails on the unmodified hook, which makes 148).
- [ ] **1b** `cli-flag-verify.sh` pre-gate: before `emit_fragments`, exit 0 unless `$SCAN_CONTENT`
  contains a `$BINS` token (pure bash loop, `[[ == *"$bin"* ]]`; the existing extraction still
  decides). Test: prose-only markdown makes zero `grep`/`sed`/`awk` spawns (shim counter); the
  `gh` MUST-fire case still fires.
- [ ] **1c** `cli-flag-verify.sh` loop: cache key computed in the parent; `[[ -s ]]` plus a
  portable freshness test (`find "$f" -mmin -1440` is what the verifier uses today; the parent uses
  the same one call for the whole batch, or a `touch -t` reference file and `[[ -nt ]]`, whichever
  `check-shell-portability.sh` accepts; `stat -c` and `date -d` are not options); spawn
  `verify-cli-flag.sh` only on a miss; on a hit, `[[ =~ ]]` in the parent. Test: warm cache makes
  zero verifier spawns (shim counter) and reports identical findings.
- [ ] **1d** `verify-cli-flag.sh` lines 103, 115, 163: `[[ -d ]]` before `mkdir -p`; the same
  portable freshness test in place of `find | grep -q .`; `[[ =~ ]]` in place of `printf | grep -E`.
  Test: the 11-case suite unchanged; a new case pins `--save-dev` vs `--save-developer`.
- [ ] Harness re-run; before/after in FINDINGS.md and the CHANGELOG entry (ADR-0003 rule 2).
- [ ] guardrails patch bump above `origin/main`; CHANGELOG entry at the head.
- [ ] `scripts/affected-tests.sh --run`; shellcheck; PR A as draft with the body contract; slice
  pasted into the body; prune commit before the ready flip.
- **Sanity Check:** harness "with refs" row for `skill-reference-verify` under 100 ms; the three guardrails suites exit 0 with the shim-counter cases; `scripts/affected-tests.sh --run` exit 0; `scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.

#### Phase 2: PostToolUse kill-switch hoist (PR B) [DOING]

Extend, never recreate: `scripts/check-killswitch-hoist.sh` is on `main`.

- [ ] Cut the branch from A's head; merge `origin/main` once A has merged.
- [ ] Widen discovery: the `jq` in the `for hooks_json` loop reads
  `.hooks.PreToolUse[]?, .hooks.PostToolUse[]?`; the refusal and count lines say "PreToolUse and
  PostToolUse"; header and NOT SCANNED wording follow. The existing test "a PostToolUse guard is
  out of scope" (`check-killswitch-hoist.test.sh:245-259`) inverts into "a reversed PostToolUse
  guard FAILS"; a hoisted PostToolUse fixture passes; the `hooks_json` helper takes an event
  argument defaulting to `PreToolUse`.
- [ ] Hoist the 15 PostToolUse-registered scripts, one line each, verbatim
  `[[ "${CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED:-true}" == "true" ]] || exit 0` above the first
  `source`, deleting the `hook::check_enabled "<NAME>"` line: `actionlint-check`, `bash-format`,
  `biome-format`, `eol-normalizer`, `go-format`, `index-drift`, `markdown-format`,
  `powershell-format`, `ruff-format`, `typos-format`, `cli-flag-verify`, `skill-reference-verify`,
  `stale-path-verify`, `worktree-add-claim-gate`, `skill-usage-audit`. `<NAME>` is the argument
  each passes to `hook::check_enabled` today (all 15 default `true` in their manifests).
- [ ] Each touched plugin: patch bump above `origin/main` plus a CHANGELOG entry stating the
  measured disabled-cost recovery for its shape (standalone recovers the library parse; the three
  guardrails verifiers run under `run-guards.sh` and recover almost nothing, said plainly).
- [ ] Measure one standalone formatter disabled, before and after, harness method; FINDINGS.md.
- **Sanity Check:** `scripts/check-killswitch-hoist.sh` exit 0 with a count 15 higher than `main`'s; `bash scripts/check-killswitch-hoist.test.sh` exit 0; for each of the 15 scripts `grep -cE '^\[\[ "\$\{CLAUDE_PLUGIN_OPTION_[A-Z0-9_]+_ENABLED' <script>` prints 1 and `grep -c 'hook::check_enabled' <script>` prints 0; `scripts/affected-tests.sh --run` exit 0; `scripts/check-changelog-parity.sh --check-bump origin/main` exit 0.

#### Phase 3: Per-session producer, sink routing, ignore guard (PR C core) [DOING]

Review: code-design

The integration slice: one event in, one line in the right file, or nothing at all when off.

- [ ] **Pre-flight (contract migration):** `git grep -n 'hook-events.jsonl\|\.claude/observability'`;
  list every parse path (sink, repo-local sink copy, probe, clean, data-sources, read-routing,
  privacy, README, plugin.json, three tests, root `.gitignore`); each becomes a checkbox in
  Phase 7's inventory.
- [ ] `plugins/claude-ops/hooks/session-event-log.sh`, sourcing nothing. Order of operations:
  1. `[[ "${CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED:-false}" == "true" ]] || exit 0`
     (default **false**; the gate admits `:-false`).
  2. `start=${EPOCHREALTIME:-}`.
  3. Bounded stdin read mirroring `hook::buffer_stdin`'s shape without sourcing it: slices via
     `read -r -t "$idle" -N "$slice"` when `hook::read_supports_nchars`'s `BASH_VERSINFO` test
     passes, `read -r -t "$idle" -d ''` otherwise; the loop stops on a `}` tail so a Win32 pipe
     that never closes costs one idle window past the payload, not the whole timeout per slice;
     idle bound from `CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT` (default 2 s, the existing option).
     Only the first slice is scanned for the spine ids; `tool_use_id`, `file_path`, `reason`,
     `model` are optional and dropped when they fall past it.
  4. Bash-regex extraction of `session_id`, `hook_event_name`, `prompt_id`, `tool_use_id`,
     `agent_id`, `tool_name`, `tool_input.file_path`, `reason`, `model`; first match wins and the
     residual (a key name appearing inside content before the real key) is documented.
  5. Exit 0 without writing when `session_id` or `hook_event_name` is empty, or when either
     fails `[A-Za-z0-9._-]+`.
  6. Category filter from `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_CATEGORIES` (default: every
     category the registry marks `observe`).
  7. Root from `CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_DIR` (default `.observability/claude`,
     containment-validated like `skill_usage_dir`) under `CLAUDE_PROJECT_DIR`, else the payload
     `cwd`; exit 0 when the root is the project root itself (a `*` guard there would ignore the
     repo).
  8. Heal the guard: when `<root>/.gitignore` is absent, `mkdir -p <root>/sessions` and write
     `*` into it (one `printf`), only when a governing checkout is detected (`[[ -d
     "$project/.git" || -f "$project/.git" ]]`; no `git` spawn). Absent a checkout, exit 0.
  9. One `printf '%s\n' >> <root>/sessions/<session_id>.jsonl` with the spine (`ts` from
     `printf '%(%FT%TZ)T' -1` with `TZ=UTC`, falling back to `date -u` on Bash under 4.2;
     `duration_ms` from `EPOCHREALTIME` or `null` on Bash under 5), `source: "event-log"`, and the
     event's payload keys. Values pass a 12-line bash escaper for `"`, `\`, control characters.
- [ ] Sink (`hook-telemetry-sink.sh` and the repo-local copy): same root resolver and guard
  healing; when the envelope's `data.session_id` is present and well-formed, the line goes to
  `sessions/<session_id>.jsonl` with the spine field names, `hook`, `exit_code`, `subject`,
  `changed` (when present) and `source: "envelope"`; otherwise to `<root>/hook-events.jsonl` as
  today (the flock path stays for that file only).
- [ ] The nine `claude-ops` audit hooks add `session_id` (bash regex over their buffered
  `$INPUT`, no new spawn) as `--arg` to the `jq -nc` that builds their `data`; each hook's
  `docs/conventions/hook-telemetry/data/<hook>.schema.json` gains the optional key. The overlap
  policy, written into the README: audit hooks keep their stores and payloads; event-log rows carry
  the spine only; the reader joins on `session_id` where present.
- [ ] `plugin.json` `userConfig`: `session_event_log_enabled` (boolean, false),
  `session_event_log_dir` (string), `session_event_log_categories` (string),
  `session_log_keep_sessions` (number, 30), `session_log_keep_days` (number, 14),
  `session_log_pre_prune_command` (string, unset; its README row states it is executed through
  `bash -c` and that project and local `pluginConfigs` are ignored on current releases, with that
  boundary as the row's recheck trigger). README options table regenerated by
  `python3 scripts/sync-plugin-options-docs.py`. `hooks.json` description rewritten (it exists
  on `main` and says "nine events").
- [ ] Empirical probe, recorded in FINDINGS.md: does a subagent hook payload carry the parent's
  `session_id`? (`agent_id` is documented; equality is not.) The reader groups by `agent_id`
  either way.
- [ ] Tests, black-box (`env -u ... bash "$HOOK" <<<"$INPUT"`): disabled writes nothing; enabled
  with no guard heals it and writes one full-spine line (`jq -e 'has("session_id") and
  has("hook_event_name")'`); no `session_id` writes nothing; hostile `session_id` (`../x`) writes
  nothing; category filter drops a non-listed event; two sessions produce two files; 33 parallel
  invocations for one session produce 33 intact lines; a held-open pipe (a `sleep 5 | hook` shape
  after the payload) returns inside `idle + 200 ms`; a 512 KB `tool_response` payload still
  yields the spine; the Bash-under-4.1 read path forced the way the library's test forces it.
  Sink suite: both routes, the healed guard, the malformed `data.session_id`.
- [ ] Measure: disabled cost (target: at or below 1.5 times the spawn floor S; reference 2.54 ms
  against S = 1.71 ms), enabled cost at 2 KB and 512 KB payloads, sink cost; FINDINGS.md and the
  README budget paragraph including the per-event spawn count a consumer pays when on.
- **Sanity Check:** `grep -L 'hook-utils.sh' plugins/claude-ops/hooks/session-event-log.sh` prints the path; `bash plugins/claude-ops/hooks/session-event-log.test.sh` exit 0; harness disabled row at or below 1.5 S; `python3 scripts/sync-plugin-options-docs.py --check` exit 0; `scripts/check-silent-skips.sh` exit 0; for each of the nine audit hooks `grep -c 'session_id' <hook>` is at least 1.

#### Phase 4: Generated event registry and hooks.json rows [DONE]

Runs before retention so every producer row, including the one `session-retention.sh` needs on
`SessionEnd`, comes from one generator.

- [ ] `scripts/gen-hook-event-registry.sh --fetch`: `curl -sS -L https://code.claude.com/docs/en/hooks.md`,
  parse the lifecycle table (rows after the `| Event | When it fires |` header until the first
  blank line; name from the first backticked cell, "when" from the second), classify by a name
  table in the script into `category` and `producer` (`observe`, or `exclude: <reason>` for
  `WorktreeCreate` "replaces default git worktree creation", `MessageDisplay` "holds each streamed
  batch until the hook returns", `FileChanged` "matcher builds the watch list; a matcherless row
  watches nothing"; an unknown name is `exclude: unclassified` with a WARN), stamp the four parts
  (claim, basis URL with anchor, as-of date, recheck trigger: "each `/claude-ops:changelog` ingest
  of a Claude Code release whose notes touch hooks re-runs `--fetch --check`; a read-time re-fetch
  finding the table changed also fires"), and write
  `plugins/claude-ops/hooks/hook-events.registry.json` sorted by name. Fewer than 25 parsed rows
  exits 2 without writing.
- [ ] Same script regenerates `hooks.json` producer rows: for every `observe` event one row for
  `session-event-log.sh` (no matcher, `statusMessage`, `timeout: 5`); the `SessionEnd` retention
  row (no `timeout` field, which would only lower the cap); the nine audit handlers preserved by
  `jq` merge in their existing order. `--check` re-derives from the committed registry offline and
  compares with `jq -S`; exit 1 on drift; CI runs `--check`.
- [ ] Phrasing per `native-references`: the registry states what the reference documented on the
  as-of date, never that the binary fires an event.
- [ ] Tests: parser on a committed fixture copy of the table (`scripts/fixtures/hooks-lifecycle-table.md`);
  the under-25 refusal; excluded events reach no `hooks.json` row (asserted by name for the three);
  `--check` clean and drifted; the nine handlers survive the merge byte-for-byte under `jq -S`.
- **Sanity Check:** `jq '[.[] | select(has("recheck") and has("basis") and has("as_of") and has("producer"))] | length == length' <registry>` prints true and `jq length` at least 30; `jq -r '.hooks | keys[]' plugins/claude-ops/hooks/hooks.json | grep -c -E '^(WorktreeCreate|MessageDisplay|FileChanged)$'` prints 0; `scripts/gen-hook-event-registry.sh --check` exit 0; `bash scripts/gen-hook-event-registry.test.sh` exit 0.

#### Phase 5: SessionEnd retention with detached pre-prune [DOING]

- [ ] `plugins/claude-ops/hooks/session-retention.sh`, sourcing nothing, same kill switch as the
  producer, **reads no stdin** (the late-EOF stall would spend the whole 1.5 s budget before any
  prune; the producer already logged the `SessionEnd` line).
- [ ] Policy in four spawns: `ls -t sessions/*.jsonl` (recency order), `find sessions -name
  '*.jsonl' -mtime +<keep_days>` (age set), then one `mv -- "${doomed[@]}" <dir>` or one `rm -f --
  "${doomed[@]}"`. Kept = newest `keep_sessions` OR younger than `keep_days`. A live idle session's
  own file is protected by `keep_sessions` in practice and recreated on its next event otherwise.
- [ ] Pre-prune: with no command, `rm -f`. With one, move doomed files to
  `<root>/prune-pending/<epoch>-<session_id>/` (collision-free across sessions ending in the same
  second), spawn `(nohup bash -c "$cmd" "$dir" </dev/null >/dev/null 2>&1 &)` (stdin closed so a
  Windows child cannot hold the hook's process tree), and at the start of every run delete any
  `prune-pending/*` older than 24 h. `clean.sh`'s new `sessions/` branch sweeps `prune-pending/`
  regardless of the switch, so disabling the plugin leaves no orphan; `probe --pipeline` WARNs on a
  pending directory older than 24 h (a broken archiver is visible, not silent).
- [ ] Tests: 100 fixture files with staged mtimes; kept set equals the union rule; spawn count
  equals four (PATH shim); a `sleep 30` command does not delay exit (assert the hook returns
  before a 1 s `timeout` wrapper fires); failing command leaves `prune-pending/` and the next run
  sweeps it after the age threshold; disabled touches nothing; wall time recorded in FINDINGS, not
  asserted in the suite.
- **Sanity Check:** `bash plugins/claude-ops/hooks/session-retention.test.sh` exit 0; `jq '.hooks.SessionEnd[].hooks[].command' plugins/claude-ops/hooks/hooks.json | grep -c session-retention` prints 1; `grep -c 'read ' plugins/claude-ops/hooks/session-retention.sh` prints 0.

#### Phase 6: Setup guard and retirement record [DONE]

- [x] `plugins/claude-ops/skills/setup/SKILL.md` leaves the check-only carve-out: `argument-hint`
  `check | apply`; the "Check-only" sentence rewritten; `check` probe 5 reads
  `${user_config.session_event_log_dir}` (channel E) and reports the guard (`<dir>/.gitignore`
  first non-comment line `*`): INFO when logging is off, FAIL with the `apply` remediation when on
  and absent, FAIL never written when the dir resolves to the project root; `apply` is bounded to
  creating that one file (announced, idempotent, "already configured" on re-run), then reports the
  tracked-vs-ignored pair (`git check-ignore -v` matches, `git ls-files --error-unmatch` fails).
  Rationale cites config-cascade line 121 and the topic-docs guard precedent.
- [ ] `plugins/claude-ops/retirements.yaml`, `claude-ops-r001`: `kind: file`,
  `path: .claude/observability/hook-events.jsonl`, `action: migrate`, successor prose naming the
  new root; helper copied from `plugins/claude-config/lib/check-retirements.sh` and enrolled in
  `scripts/sync-check-retirements.sh`'s `copies=(` list; the two fixed setup lines verbatim; one
  eval for the record. `.claude/observability/` and its ignore line stay (skill-usage and OTEL
  stores still live there).
- [ ] Evals: "writes only the guard", "refuses a root-equivalent dir", "reports the retirement".
- **Sanity Check:** `bash plugins/claude-ops/lib/check-retirements.sh --manifest plugins/claude-ops/retirements.yaml --root <clean fixture>` exit 0 and exit 1 against a fixture carrying the old file; `scripts/sync-check-retirements.sh --check` exit 0; `grep -c 'check-retirements.sh' plugins/claude-ops/skills/setup/SKILL.md` at least 2; `bash scripts/check-changed-skills.sh origin/main` exit 0.

#### Phase 7: Reader extension and path migration [TODO]

- [ ] `data-sources.md`: `HOOK_ROOT` from `${user_config.session_event_log_dir}` (channel E)
  with a flag override, never from `CLAUDE_PLUGIN_DATA`; every `jq -s "$HOOK_LOG"` becomes
  `jq -s "$HOOK_ROOT"/sessions/*.jsonl "$HOOK_ROOT"/hook-events.jsonl` with the `.ts` window
  unchanged; a "Per-session report" section: hooks fired (`source == "envelope"` grouped by
  `hook`), blocked (`status == "blocked"`), rewrote (`changed == true`; empty until a formatter
  emits it), duration per hook, the event timeline from `source == "event-log"` rows, and a line
  naming legacy rows (shared file, no session) as time-proximity only; a "Toggles and retention in
  effect" section rendering the six options and guard state from `probe-observability-state.sh
  --pipeline`.
- [ ] `SKILL.md`: `session` resolves to the newest `sessions/*.jsonl` by mtime, `session:<id>`
  names one; the data-sources row names the new root; the `session_id` gotcha is rewritten;
  `output-format.md` drops "Per-session detail" from the omissions and adds the template;
  `read-routing.md`, `privacy.md`, README, `plugin.json` description follow the path.
- [ ] `probe-observability-state.sh`: `--hook-events` counts across the root; `--pipeline` prints
  toggles, guard state, and pending-prune age; ORIG fixtures regenerated for the new path.
- [ ] File inventory: `[ ] hook-telemetry-sink.sh` MODIFY, `[ ] .claude/hooks/hook-telemetry-sink.sh`
  MODIFY, `[ ] hook-telemetry-sink.test.sh` (both) MODIFY, `[ ] probe-observability-state.sh`
  MODIFY, `[ ] probe-observability-state.test.sh` MODIFY, `[ ] clean.sh` MODIFY,
  `[ ] data-sources.md` MODIFY, `[ ] claude-observability.test.sh` MODIFY, `[ ] read-routing.md`
  MODIFY, `[ ] privacy.md` MODIFY, `[ ] output-format.md` MODIFY, `[ ] SKILL.md` MODIFY,
  `[ ] plugins/claude-ops/README.md` MODIFY, `[ ] plugin.json` MODIFY, `[ ] .gitignore` MODIFY
  (`.observability/` beside `.claude/observability/`), `[ ] skill-usage-audit.sh` KEEP (store
  stays), `[ ] claude-ops-paths.sh` KEEP, `[ ] otel/*` KEEP.
- **Sanity Check:** `git grep -n '\.claude/observability/hook-events' -- ':!docs/topics' ':!**/CHANGELOG.md' ':!plugins/claude-ops/retirements.yaml'` prints nothing; `bash plugins/claude-ops/skills/observability/claude-observability.test.sh` exit 0 with a multi-file fixture and a `session:<id>` case; `bash .../probe-observability-state.test.sh` exit 0; the per-session queries against a sample session file list fired, blocked, and per-hook duration rows.

#### Phase 8: Docs, versions, prune, PR C [TODO]

- [ ] `docs/conventions/hook-observability/README.md`: a paragraph naming
  `# silent-skip-ok: <reason>` as the annotation, where it goes, and that
  `check-silent-skips.sh` reads it (Q9).
- [ ] `docs/conventions/hook-telemetry/README.md`: sink-routing note (a `data.session_id` routes
  per session; envelopes without one route to the shared file) and the follow-up pointer for the
  fleet-wide `data.session_id` addition and the envelope 1.1 bump (#930).
- [ ] claude-ops patch bump above `origin/main` with the CHANGELOG entry at the head; the
  `plugin.json` description gains one sentence (skill count unchanged).
- [ ] Toggle cycle: enable, fire ten events, disable, fire ten, enable, fire ten;
  `ls -R .observability/claude/` shows only `.gitignore`, `sessions/<id>.jsonl`, and (when
  configured) `prune-pending/`.
- [ ] Windows recheck owed (atomic append, `ls -t`, late-EOF timing) recorded in FINDINGS as
  unmeasured on this host.
- [ ] `scripts/affected-tests.sh --run`; `/review:code-review`; PR C as draft with the body
  contract and the slice in a `<details>` block; prune commit deleting
  `docs/topics/hook-logging-pipeline/` before the ready flip.
- **Sanity Check:** `grep -c 'silent-skip-ok' docs/conventions/hook-observability/README.md` at least 3; `scripts/check-changelog-parity.sh --check-bump origin/main` exit 0; `scripts/affected-tests.sh --run` exit 0; the toggle-cycle listing matches; on the ready-flip commit `test ! -d docs/topics/hook-logging-pipeline`.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Add `session_id` to the envelope spine in `hook::emit_telemetry` now | `lib/hook-utils.sh` and its 17 copies are off-limits to this lane; #930 owns the bump | The operator releases the library to this lane, or #930 lands: then `data.session_id` becomes redundant and the sink reads the spine key first |
| One producer script per event | 33 files for one behavior; the generator already parameterizes by event | A per-event payload outgrows one `case` block |
| Session-tag legacy envelope rows at write time by "newest active session" | Wrong under concurrent same-repo sessions; a wrong `session_id` is worse than none | Concurrent same-repo sessions are proven impossible for this consumer (they are not) |
| Registry `--check` fetches live in CI | Network flake fails CI on nobody's change | A cached, retried fetch step the repo already trusts elsewhere |
| Inline pre-prune command | A slow archiver exhausts the 1.5 s budget (Brief Q19) | `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` becomes the documented consumer default |
| Refuse-to-write until `setup apply` runs (Brief Q13 as locked) | Fresh clones and worktrees never carry the guard, so logging silently does nothing there | The operator prefers refusal plus the `SessionStart` notice; then step 8 in Phase 3 becomes "exit 0 and notify" |
| Appended root `.gitignore` line (work-items shape) | Needs a declared exception, a config-cascade row and two-probe verification | The operator wants `.observability/` covered by one root line for every tool |
| Stack B on A and C on B as open PRs | A and B collide on the guardrails manifest and CHANGELOG head; squash merges make stacked diffs misleading | Reviews stall for days; then open B against A's branch and retarget on merge |
| Split PR C | The off-then-on and per-session-report criteria are end-to-end | PR C exceeds 40 files; split at the Phase 5/6 boundary |
| Weekly `--fetch --check` workflow for the registry | A new scheduled workflow is its own review lane (zizmor, runner policy); the recurring-occasion trigger already satisfies the observability bar | A hooks-reference change slips past two changelog ingests |

### Test strategy

Every new `.sh` ships a co-located `<stem>.test.sh` or `affected-tests.sh` errors. TDD throughout;
repro-first for the guardrails fixes (`hook-precision`): each structural assertion is written to
fail against the unmodified hook. Suites assert structure (spawn counts through a PATH shim, jq
invocation counts, file sets, line shapes); wall-clock figures live in the harness rows in
FINDINGS.md and the PR bodies, never as suite assertions.

Test boundaries the tests drive (existing unless marked new):

- `skill-reference-verify.sh`, `cli-flag-verify.sh` stdin-to-stdout contracts, with a PATH shim
  counting spawns (existing contract, new shim).
- `verify-cli-flag.sh` CLI (existing).
- `scripts/check-killswitch-hoist.sh` fixture-tree contract (existing; one case inverts).
- `session-event-log.sh` stdin-to-file contract (**new**).
- `session-retention.sh` directory-to-directory contract, stdin-free (**new**).
- `hook-telemetry-sink.sh` envelope-to-file contract (existing, new route).
- `scripts/gen-hook-event-registry.sh` fixture-table-to-JSON and `--check` (**new**).
- The nine audit hooks' data shape (existing suites gain a `session_id` assertion).
- `data-sources.md` jq text copied into `claude-observability.test.sh` (existing; copy-by-hand
  discipline stays).
- Setup through `evals/evals.json` (existing; the write is a markdown instruction).

Deciding edge cases: hostile or missing `session_id`, guard absent in a fresh worktree,
root-equivalent dir, 33 parallel appenders, held-open pipe, 512 KB payload, Bash-under-4.1 read
path, under-25-rows registry refusal, excluded events reaching no row, four-spawn retention on 100
files, `prune-pending` collision and sweep.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Per-hook duration per session covers only producers emitting `data.session_id` (nine in PR C) | High | Med | Reader labels legacy rows; follow-up filed for the fleet one-liner; the envelope 1.1 bump is the terminal fix |
| A producer row on 30 events doubles per-event spawns for consumers who enable it | Med | Med | Default off; measured on-cost and spawn count in the README; category filter; three high-frequency or behavior-replacing events excluded by the registry |
| Windows late-EOF makes every fire wait out the idle window | Med | High | Slice-and-`}`-tail read mirrored from the library; retention reads no stdin; held-open-pipe test; Windows figure owed before PR C flips to ready |
| Version collisions across A, B, C and a third lane | Med | Low | "Next patch above `origin/main` at cut time"; each PR opens only after the previous merged; parity gate is the check |
| Hooks reference table changes shape; generator parses zero rows | Low | Med | Exit 2 under 25 rows; committed registry stays authoritative |
| `check-silent-skips.sh` flags the jq-free producer | Low | Low | No `command -v` gate in it; verified in Phase 3's sanity check |
| Subagent payloads carry a different `session_id` than the parent | Low | Low | Phase 3 probe; reader groups by `agent_id` either way |

### Execution-shape analysis [EXEC-SHAPE]

File-overlap: Phases 1 and 2 overlap on two verifier scripts and the guardrails manifest; Phases
3 to 8 share `hooks.json`, `plugin.json`, the sink, and the README. Dependency graph:
0 → 1 → 2 → 3 → 4 → 5 → {6, 7} → 8; 4 precedes 5 because retention's `SessionEnd` row is
generated. Recommended shape: **fully sequential, main session**; the only file-disjoint pair
(6 and 7) saves under 100 LOC of independent work. Cost note: one session, no multiplier.
Sequential fallback: not applicable.

| Phase | Surface | Basis |
|---|---|---|
| 0, 1 | main-session | timing runs need a quiet host; judgment per patch shape |
| 2 | main-session | 15 one-line edits plus 13 version bumps; fleet-wide, reviewed inline |
| 3, 4, 5 | main-session | the integration slice and its two dependents; contracts settle here |
| 6, 7 | main-session | markdown-heavy under the skill-quality gate |
| 8 | main-session | PR assembly, toggle-cycle probe, prune commit |

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| Heal-on-first-write guard (`*` `.gitignore` inside the observability root) instead of refuse-until-present `[FALLBACK — confirm or override]` | Phase 3 step 8; Phase 6 `apply` stays the idempotent writer; Brief correction recorded | Guard lives in the ignored tree so clones and worktrees never carry it (both reviewers); `topic-docs/README.md:589-596` heals on first write, announced |
| Guard at `.observability/claude/`, not `.observability/` `[FALLBACK — confirm or override]` | Phase 6 probe path | A shared parent root belongs to no plugin; `apply` is bounded to plugin-owned artifacts (`PLUGIN-PHILOSOPHY.md:535-539`) |
| Registry `producer` field excludes `WorktreeCreate`, `MessageDisplay`, `FileChanged`; unknown names excluded `[EXEC-SHAPE]` | Phase 4 generator and its test; Brief Q6 correction | hooks reference `### WorktreeCreate` ("replaces that default git behavior"), `### MessageDisplay` ("holds each batch"), `### FileChanged` (matcher builds the watch list), fetched 2026-09-05 |
| `data.session_id` on the nine audit hooks' envelopes; fleet-wide addition and envelope 1.1 are follow-ups `[FALLBACK — confirm or override]` | Phase 3 audit-hook item; the acceptance-criterion scoping in the Brief corrections | Hooks receive no session id in their environment (hooks reference, common input fields); `hook-telemetry` rule 1 allows additive `data` keys; the library is off-limits |
| Only `hook-events.jsonl` migrates; skill-usage and OTEL stores stay `[EXEC-SHAPE]` | Phase 6 retirement record is `kind: file`; Phase 7 KEEP rows | The Brief names only hook events; the other stores have their own readers and retention |
| Pre-prune hands the archiver a moved-aside `<epoch>-<session_id>` directory; physical delete deferred 24 h; `clean` sweeps it regardless of the switch `[FALLBACK — confirm or override]` | Phase 5 mechanics; Phase 7 `clean.sh` | Brief Q19 detached execution; a detached command racing an unlink loses files; two sessions can end in one second |
| Retention reads no stdin and uses four spawns total; no `timeout` on its row `[EXEC-SHAPE]` | Phase 5 | `lib/hook-utils.sh:1298-1350` documents the late-EOF stall; hooks reference: plugin timeouts cannot raise the 1.5 s budget and `timeout` only lowers it |
| Producer default `false`; retention shares its switch `[EXEC-SHAPE]` | Phase 3 step 1; Phase 5 | Brief Q6 default-OFF; the hoist gate admits `:-false` |
| Sequential PRs, each opened after the previous merged; bumps are "next patch above `origin/main`" `[EXEC-SHAPE]` | Approach table; every version line | `origin/main` at claude-ops 0.42.2 / guardrails 0.32.1 with 0.41.13 and 0.41.14 taken; PR #3727 bumped every touched plugin; A and B share two files |
| Topic slice pruned before each PR's ready flip; carried by cherry-pick onto B and C `[EXEC-SHAPE]` | Approach; Phases 1 and 8 | `topic-docs/README.md:60-66`: contract tier committed on the branch only, pruned before merge |
| Registry `--check` offline; recheck trigger is each changelog ingest touching hooks `[EXEC-SHAPE]` | Phase 4 CI wiring and stamp text | No live fetch in any existing CI gate; `upstream-drift` accepts a recurring occasion as an observable trigger |
| Suites assert structure, harness records wall time `[EXEC-SHAPE]` | Test strategy; Phases 1, 3, 5 | Wall-clock assertions are flaky on shared runners (both reviewers); the PATH-shim counter is the repo's existing spawn-assertion idiom |
| "Rewrote" is a defined `changed` key no producer emits yet `[FALLBACK — confirm or override]` | Phase 7 query returns empty; follow-up | Formatters emit `data.findings` only (exploration, current-state section 2) |

## Blast radius

**HIGH.** Hooks are infrastructure; the pipeline is a cross-cutting observability concern; Phase 2
touches 15 scripts across 13 plugins; a widened CI gate and a generated registry constrain future
work. Reversible by revert, and every phase sits behind a mechanically verifiable sanity check,
which keeps it below CRITICAL.

Stress-test needed: Yes; run.

## Stress-test summary

Two fresh-context passes on the first draft (`7f1a9edc`), findings verified against the files
before applying:

- **Plan review:** 3 CRITICAL, 8 IMPORTANT, 9 SUGGESTION. Criticals: stale versions against
  `origin/main`; `WorktreeCreate` row replaces git worktree creation; the per-hook-duration
  criterion unmet as written. All folded in (Approach, Phase 4, Brief corrections). Importants
  folded in: Q8 correction; guard invisible to worktrees (heal-on-write); `MessageDisplay`
  excluded; Bash 3.2 floor fallbacks; topic-docs prune lifecycle; retirements sync enrollment;
  hand-registered rows dropped in favor of the generator; existing `hooks.json` description and
  the audit-hook overlap policy. Suggestions folded in: stdin-closed detached spawn; structural
  test assertions; "1.5 S" spelled out; the "no two processes" wording softened to the per-session
  line-size bound; 512 KB payload measurement; `clean` sweeps `prune-pending`; channel E for the
  reader's root; per-script switch count in Phase 2; the `pre_prune_command` boundary note.
- **Devils-advocate** (`DEVILS-ADVOCATE.md` in the memory slice): 3 CRITICAL, 4 HIGH, 7 MEDIUM,
  6 LOW. Criticals matched the review's plus the Windows late-EOF stall, folded in as the
  slice-and-`}`-tail read, the stdin-free retention hook, and the held-open-pipe test. Highs:
  `MessageDisplay`, batched prune spawns and no `timeout` on the row, `SessionStart` notice when
  healing is impossible, A/B collision (sequential-after-merge). Mediums: `prune-pending` naming,
  stale-pending WARN, portable freshness tests, large-payload measurement, registry trigger
  observability, upgrade path (the retirement record plus healing), subagent `session_id` probe.
  Lows: the inverting gate test, `cwd` fallback on Windows, `jq -S` comparison, live-session
  prune, all folded in.

Verdict after the fold: no CRITICAL or HIGH finding remains open; the residuals are the Windows
figures owed before PR C flips to ready and the fleet-wide `data.session_id` follow-up.

## Execution shape

Fully sequential, main session; see "Execution-shape analysis" above.

## Open questions

- **Envelope 1.1** (`session_id`, `prompt_id`, `tool_use_id`, `agent_id` on the envelope spine).
  Default: follow-up citing #930; the sink already routes on `data.session_id`. Escape hatch: the
  operator releases `lib/hook-utils.sh` to this lane and Phase 3 adds the four fields to
  `hook::emit_telemetry` with the sync script run.
- **Fleet-wide `data.session_id`** on the other ~25 envelope producers. Default: follow-up issue
  after PR C. Escape hatch: add it in PR B, which already edits 15 of them.
- **Formatter-side `changed` emission.** Default: follow-up. Escape hatch: same PR B.
- **Windows/Git Bash recheck** (atomic append, `ls -t`, late-EOF timing): owed before PR C flips
  to ready; not blocking A or B.

## Handoff to implementation

### User-approval gates

Every `[FALLBACK — confirm or override]` row is presented with a one-line flip in the approval
message; absent an override, implementation proceeds on the defaults. A change to an acceptance
criterion beyond the corrections recorded above stops and reports before continuing.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, main session, three draft PRs in the order A, B, C, each opened after the previous
merged; per-phase sanity checks are the phase boundaries; no sub-topic promotion.

### Mechanical work

Commit per phase with the phase-tag flip in the same commit; validate with
`scripts/affected-tests.sh --run` (a zero-suite file is an error), shellcheck, and the named gates
before each push; announce branch, PR title, and file list to every live peer before each PR;
draft first, prune the slice, flip to ready when green.
