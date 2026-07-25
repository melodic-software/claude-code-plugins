# autonomy-ignition — PLAN (#778)

Sub-topic of `docs/topics/ladder-climb-roadmap/PLAN.md` Phase I (on `main` since PR #794).
Design record: interview rulings (ledger committed in the roadmap topic) +
`design/design-resolution.md`.

## Brief

Ignite the 2→3 loop: the first standing routine (C2 drain — hourly at ignition, re-bound
2026-07-22 to a **15-min slot grid**; Phase 4 re-bind ratification below) + C2-promotion
evidence drain on `kyle-sexton/autonomy-demo-scratch` (binding-ratified surfaces
`label-kick` + `hourly-drain`, execution surface `demo-local-session`). Purpose: accumulate
the evidence stream whose predicate (≥20 autonomous C2 completions / **≥7-day span under a
48h merge-maturity guard** — values org-rebound 2026-07-22, scratch#43, from the suggested
defaults in `plugins/autonomy/reference/guardrails/work-classes.md` / 100%
deterministic-gate pass / 0 human-reverted merges) makes the C2 auto-merge cell ELIGIBLE.
Promotion flips stay human-ratified.

**Merge policy during the accumulation window (stress-test ruling, 2026-07-21):** runs open
PRs and STOP. The human merges — that IS the un-promoted C2 policy (`guardrails.md`: C2
auto-merge ELIGIBLE only after promotion; ships human-gated). Autonomous merging before the
flip would be a step-skip and would make the evidence circular. Human merges still produce
the merge/revert events the predicate needs; "autonomous completion" = claim→implement→PR
with no human help, not autonomous merge.

### Operator decisions (resolved 2026-07-21, approval round)

| Decision | Ruling |
|---|---|
| Auth path | Subscription app-session auth (native Desktop task = signed-in session; no API key). CLI fallback uses logged-in CLI subscription auth. |
| Model per run | Sonnet 5, pinned explicitly on the task AND on the inner dispatch invocation (Max `default` resolves to Opus — never leave unpinned; current `dispatch-item.sh` hardcodes `--model opus` and MUST change). Escalation via native seams; no routing build now. Revisit trigger: drain-PR failure rate exceeding weekly triage. |
| Schedule | Hourly preset (superseded 2026-07-22: re-bound to a 15-min slot grid — Phase 4 re-bind ratification) + Desktop **Keep computer awake** ON (Settings → Desktop app → General). Lid-close still sleeps (accepted). |
| Failure handling | Reconcile-first, no auto-retry. Failure path files a durable human-gated tracker item (desktop notification is garnish — toasts evaporate during an unattended week). |
| Budget bound | Native task + plan-window backstop at the session level, PLUS a mechanical per-run bound on the inner invocation (`--max-budget-usd` + wrapper timeout kill; `--max-turns` absent from the installed CLI — verified 2026-07-21) — a number in a doc bounds nothing (roadmap requirement). |

### Constraints (inherited + build-time)

- Concept/implementation separation: agnostic routine content stays in contracts/templates;
  machine/repo specifics bind in the proving-ground binding and task definition only.
- Adapter obligations (SIX — `trigger-dispatch.md:45`).
- `signal.work_class` stamped from a governance surface the run CANNOT write: the drain
  claims ONLY items already carrying the C2 class label (applied by the operator/governed
  process); label→class rules live in the plugins repo, read-only to the run. No model
  inference of class; unlabeled = skip. `.claude/autonomy/**` and label mutation are
  excluded from the run's allowlist.
- #440 outward-write posture: report-only-compatible evidence.
- **Scheduler ruling (operator, 2026-07-21):** primary = Claude Code Desktop scheduled task
  (per the native-first amendment on #778); fallback = OS scheduler + `claude -p` headless
  (the amendment's "can't be easily managed" exit clause — a legitimate flip if running the
  Desktop app continuously proves burdensome); excluded = session-scoped CLI scheduling
  (`/loop` / cron tools), unfit for a standing unattended routine per its own documentation.
  The WHY lives upstream, not here — surface properties, comparison table, and expiry
  semantics are owned by the living docs:
  <https://code.claude.com/docs/en/desktop-scheduled-tasks> and
  <https://code.claude.com/docs/en/scheduled-tasks> (verified 2026-07-21). This ruling is
  expected to be overtaken — a durable CLI-native surface may ship; the standing
  recheck-against-upstream trigger (re-verify the scheduling landscape at every build
  touchpoint) is the mechanism that catches it. Trust the fetched docs at each touchpoint,
  never this note's recollection of them.
- STANDING ORCHESTRATION CONTRACT: builders in worktrees, agents never touch git, main
  thread verifies empirically before every commit.

### Known build gaps (scouted + stress-tested 2026-07-21)

- No CI in the scratch repo — the deterministic gate must be BUILT (Actions check on PRs);
  gate outcomes must be read from GitHub's check-run API (independent surface), never from
  agent-appended files.
- `dispatch-item.sh`: `--model opus` hardcode; close-only path; no `--session-id`; no
  work_class stamp; 24h lease TTL vs hourly cadence.
- `hourly-drain` binding surface entry stale (`scheduler_class: ci-cron` vs actual Desktop
  scheduler); no `routines.enabled` ratification entry (nonconformant temporal signal =
  fail-closed unclassified).
- Evidence (`.artifacts/`, OTel store) local-only, unversioned, no backup.

## Plan

### Phase 1: Scratch-repo drain + evidence upgrade [DONE]

> **Status note (2026-07-21, final):** MERGED — `autonomy-demo-scratch#5` (main `2ce16e8`).
> Sanity checks all PASS: dry-run (no-work before seeding; claims C2 seed scratch#6 after;
> unlabeled items skipped), model/bound greps, deterministic-gate real and GREEN (operator
> made the repo public, clearing the Actions-billing startup failure), predicate stub
> returns the four inputs (correctly zero, eligibility false). Dated deviation stands:
> `--max-turns` absent from the installed CLI (verified `claude --help`) — mechanical
> per-run bound is `--max-budget-usd` (placeholder $5.00, operator ratifies at Phase 2) +
> `timeout 3300` wrapper kill. Deferred to Phase 3 smoke: full item run through human merge
> into the four-way join; nested `claude -p` under a scheduled session; run-worktree nesting
> under the Desktop worktree toggle (one isolation layer may be disabled).

Repo: `kyle-sexton/autonomy-demo-scratch` (Opus builder in worktree; main thread commits).
Work items:

1. **Deterministic gate as real CI**: GitHub Actions workflow running the repo's
   deterministic checks on every PR. Gate outcome consumed from the check-run API keyed by
   PR/`autonomy.work_item.url` — the agent never writes its own gate result. (Branch
   protection requiring the check: verify plan entitlement on the private personal repo at
   build; with human-merge policy the human is the merge gate meanwhile.)
2. **`drain-next.sh`** hourly entrypoint: reconcile preamble (orphaned worktrees, leases
   from dead runs only — cross-check run identity, never break a live session's lease;
   branches without PRs; PRs without evidence rows), then claim next item CARRYING the C2
   label (skip everything else, including unlabeled), dispatch, exit clean on empty queue
   (no-work run = valid fire). Failure path files a human-gated tracker item.
3. **`dispatch-item.sh` rework**: PR-flow WITHOUT merge (open PR, stop); `--model sonnet
   --max-budget-usd <USD>` + wrapper timeout kill (per-run mechanical bound); per-run
   `--session-id`; drain-lease TTL ~2h; merge SHA recorded later by the join from GitHub
   events (human merge), not by the run.
4. **Evidence sources into the join**: work_class stamp (from the label, governance-sourced)
   and scheduled-fire run identity on every row; gate outcome from check-run API; merge/revert
   from GitHub PR events. `verify-join.sh` grows accordingly (append-only jsonl, DuckDB
   reads on demand). Completeness keys on distinct (item URL, run id) — not raw row count.
5. **`predicate-c2.sql`** stub: completion count, window span, gate pass rate,
   human-revert count — FILTERED to scheduled-fire identity rows (manual assists never
   count as autonomous).
6. **Evidence backup**: nightly deterministic copy of `.artifacts/` + OTel store snapshot to
   a second location (plain scheduled script, zero agent tokens).
7. **Binding conformance**: correct `hourly-drain` surface entry (local Desktop scheduler,
   push), add `routines.enabled` entry (identity, `file:` run-link namespace — contract
   permits for local schedulers), record the attestation level the Desktop surface offers;
   any gap = named dated deviation in this plan, not silence.

**Sanity Check:**

- `bash tools/autonomy-demo/drain-next.sh --dry-run` exits 0, prints claimed C2-labeled item
  URL or `no-work`; unlabeled test item is skipped.
- Test item run: PR opened, run STOPS (no merge); after human merge, `verify-join.sh <n>`
  row carries work_class + check-run gate outcome + merge SHA + scheduled-fire identity.
- `gh api repos/kyle-sexton/autonomy-demo-scratch/commits/<sha>/check-runs` returns the gate
  check for a test PR (gate is real, independent).
- Inner invocation greps: `--model sonnet` present, `--max-budget-usd` present (supersedes
  `--max-turns` — absent from the installed CLI, see status note), `--model opus` absent
  from the drain path.
- Predicate stub runs and returns the four inputs filtered to scheduled-run rows.

### Phase 2: Native task + machine posture [DONE]

> **Status (2026-07-21):** task `autonomy-demo-hourly-drain` live (hourly, worktree toggle
> ON, Sonnet pinned, trusted folder); keep-awake + autostart set; warm-up covered happy path
> AND failure vocabulary with zero stalls; budget kill proven under subscription auth
> (1-cent cap killed a live run — the `--max-budget-usd` estimate-kill is real on this
> billing mode). Missed-fire detector wiring deferred to Phase 4 (native run history +
> failure tracker items are the interim signal).

Main thread + operator (machine-local surfaces):

1. Desktop **Keep computer awake** ON + **app autostart at login** (operator toggles).
2. Create the scheduled task (Routines → Local): `autonomy-demo-hourly-drain`, hourly,
   folder = scratch checkout, **worktree toggle ON** (each run in its own isolated worktree
   — never the live checkout; verify at smoke what the worktree branches from), model
   pinned Sonnet 5, permission mode + allow rules derived STATICALLY from the scripts' full
   command surface (all branches incl. failure vocabulary: label ops, pr close, lease PATCH),
   instructions = run `drain-next.sh` under the reconcile-first contract with a stale-time
   guardrail for catch-up fires.
3. Warm-up: **Run now** through the happy path AND one forced-failure item so the failure
   vocabulary gets its always-allows too; repeat until a prompt-free pass of each path.
4. **Missed-fire detector**: deterministic script (OS scheduler, zero tokens) comparing run
   history timestamps against the hourly cadence; files a tracker item on gap — the
   post-reboot/Windows-Update detector the freeze week needs. (Cadence spec superseded by
   the 2026-07-22 re-bind: the detector must track the bound cadence, now the 15-min slot
   grid — scratch#66, see the Phase 4 re-bind note.)
5. Visibility: native run history + notifications; PRs are the GitHub artifacts; scoreboard =
   verify-join; failure/missed-fire tracker items are the durable signal.

**Sanity Check:**

- `ls ~/.claude/scheduled-tasks/` lists `autonomy-demo-hourly-drain/`; its `SKILL.md` body
  names `drain-next.sh`.
- One happy-path AND one forced-failure **Run now** complete with zero permission stalls;
  the failure run filed its tracker item.
- Missed-fire detector dry-run: seeded gap produces the tracker item.

### Phase 3: Smoke + first scheduled fire [DONE]

> **Status (2026-07-21): 7/26 DEMONSTRABLE BAR MET.** Genuine scheduled fire
> `scheduled-20260721T080540Z-41a51d66` (zero manual kick) claimed scratch#12, opened PR
> #13, stopped unmerged; gate SUCCESS via check-run API; live checkout clean; evidence row
> joined on the durable path. First complete four-way row: scratch#6 (human merge
> 213a8b63). Warm-up rows excluded from the accumulation window, which starts at
> 41a51d66. Residual minor checks carried to Phase 4: model-in-telemetry confirmation,
> stray `\r` in the claimed-line `item_url` (dispatched-line key is clean; trim at writer
> on next touch).

Main thread empirical verification (no builder):

1. Confirm a SCHEDULED (non-manual) fire past the next hour boundary.
2. Verify the run executed in an isolated worktree (live checkout untouched — `git status`
   clean before/after), on Sonnet (session telemetry model check), within the bound.
2b. Verify `--max-budget-usd` actually enforces under subscription auth (alignment audit
   2026-07-21): warm-up run with `DRAIN_INNER_MAX_BUDGET_USD=0.01` must be KILLED by the
   flag; if it is a no-op under subscription billing, the timeout is the only per-run bound
   — record that at the bound site and revisit the budget ruling.
3. Evidence completeness: distinct (item URL, run id) rows match fired runs; row carries all
   sources; PR open awaiting human merge; after merge, merge SHA appears in the join.
4. Record the 7/26 demonstrable bar: ≥1 scheduled fire + ≥1 complete evidence row.

**Sanity Check:** run history shows ≥1 scheduled entry; join returns the complete row; model
in telemetry = Sonnet; live checkout clean; any fire-without-row = Phase 1 defect, reopen.

### Phase 4: Accumulation watch [DOING — standing]

> **Status note (2026-07-21, day 0-1):** Both DEADLINE items LANDED well before day 14 —
> scratch#14 (merge `c12e172`): gate substance (deterministic behavioural test step, 15
> assertions, shared production filter under test) and revert detection (`reverted` from
> origin/main revert-commit scan, fail-closed at three layers — undeterminable status
> aborts loud, never reads as clean). Same PR: accumulation-window lower bound codified
> (`DRAIN_WINDOW_START_UTC = 2026-07-21T08:05:40Z`, first genuine scheduled fire 41a51d66;
> warm-up/manual rows never count — predicate corrected 2→1 completions), claimed-line
> `\r` fixed at the writer, idempotent merged-but-open reconcile guard added. Residual
> Phase-3 check DONE: inner drain run 41a51d66 ran `claude-sonnet-5` (session transcript).
> Incident (recorded for audit honesty): operator paused the task 09:30–16:31Z (8 hourly
> fires missed while paused). Post-re-enable fires, from run history/state at the time of
> this note: catch-up 16:31:26Z (one, per the documented missed-run semantics), then
> scheduled 17:05Z and 18:05:23Z — cadence recovered. Consequence split: the C2 PREDICATE
> window (span-based evidence accumulation) continues from 08:05:40Z, but the roadmap
> ACCEPTANCE check ("fires on schedule with zero manual kicks for ≥1 week") cannot count
> a stretch containing a scheduler outage — that ≥1-week clock restarts at the 16:31Z
> re-enable. Hook gap evidence posted on #811 (scheduled sessions run all node hooks as
> no-ops — `node: command not found` on SessionStart AND Stop).
>
> **Known gap — fire-kind self-stamp:** the task SKILL.md hardcodes
> `--fire-kind scheduled`, so a manual **Run now** records as a scheduled fire in
> evidence (how the 07:36Z warm-up row got its stamp). Fences: the window-start bound
> excludes historic warm-up; operator discipline — no Run-now during the accumulation
> window. Mechanical fix filed as kyle-sexton/autonomy-demo-scratch#15 (fire-origin
> attestation from the inner session transcript's scheduled-task enqueue marker,
> fail-closed) — land before any eligibility claim relies on the zero-manual-kicks
> input.
>
> **Status note (2026-07-22): fire-kind gap CLOSED — attestation LANDED** —
> scratch#22 (merge `12098d7`, closes scratch#15). Empirical finding that reshaped the
> design: a Run-now's enqueue record is byte-shape IDENTICAL to a scheduled one (verified
> against the 07:36Z warm-up transcript), so #15's proposed marker cannot distinguish
> origins alone; the landed mechanism is the originating-transcript join (run_id
> containment + enqueue within 0–900s before run start, measured against EVERY task-tagged
> enqueue per transcript) plus cron-slot alignment (≤600s past top-of-hour; genuine fires
> land +320–332s, warm-up +2187s). Fail-closed exclusion; positives materialized to
> `.artifacts/fire-attestations.jsonl` so once-attested runs survive transcript GC.
> Predicate no longer trusts the `fire_kind` stamp (`fire_attested = true` filter).
> Independent review found 1 CRITICAL pre-merge (multi-enqueue transcripts misattributed
> origin to the file's first enqueue — fixed + regression-covered; latent today, all 11
> real transcripts single-enqueue). Documented residual: a manual kick enqueued within
> 600s of the slot attests falsely — threat model is accidental kicks, not an adversarial
> operator. Live predicate at note time: completions=3 (runs 080540Z/190608Z/000552Z,
> attested), span 1d, gate 100%, reverts 0, eligible=false; warm-up 073658Z mechanically
> excluded (off-schedule, 2187s). Same day: C2 queue reseeded (scratch#17–#20) after #10
> drained; drain PRs #16 (#10) and #21 (#17, fully autonomous seed-to-merge cycle) merged;
> #811 root-caused (fnm shell-init-only PATH — GUI-launched sessions never get node;
> operator one-liner + Desktop restart posted on #811, pending).
>
> **Acceleration ruling (operator, 2026-07-22):** move as fast as the predicate's intent
> allows; the calendar gates (14-day span, ≥1-week zero-manual-kicks acceptance) stay
> binding — shortening them would gut the evidence's meaning. Three sanctioned levers:
> (1) **front-load the completion count** — seed the C2 queue as fast as GENUINE mechanical
> items exist (drain claims one per hourly fire; the ~1.5/day cadence was shape preference,
> not a rule; fabricated busywork seeds are forbidden — they weaken the evidence);
> (2) **ignite Phase IV in parallel** with this watch (its gate — Phase I demonstrable — was
> met 2026-07-21; each item still gets its own plan);
> (3) **pre-build the Phase III flip machinery** (promotion PR draft citing the evidence
> window) so the earliest eligibility date (~2026-08-04) is ratify-and-merge, not a build
> day. Same day: drain PRs #23/#24/#26 merged (one linkage defect — `Refs` vs `Closes` —
> caught and fixed pre-merge on #24), Dependabot's first PR #25 merged (SHA verified against
> the upstream v7.0.1 tag; Dependabot PRs never count as drain evidence), queue reseeded
> with five verified seeds (scratch#27–#31); predicate at completions=6, gate 100%,
> reverts 0.
>
> **Re-bind ratification (operator, 2026-07-22, supersedes the calendar-gate line of the
> acceleration ruling above):** the predicate's threshold VALUES are org-bindable per
> `work-classes.md` ("suggested defaults the org binds"); the operator re-bound them in a
> reviewed change (scratch#43, merge `cd89f4a`, independently reviewed, 62-test suite):
> span ≥14d → **≥7d**, compensated by a **48h merge-maturity guard** — both the ≥20 count
> AND the span measure use only completions merged ≥48h before evaluation, so a
> burst-then-straggler shape stays ineligible and the revert signal cannot be outrun.
> Simulation of evidence was proposed and REJECTED (synthetic evidence corrupts the base).
> Earliest eligibility moves ~2026-08-04 → **~2026-07-30/31**: the ≥7d mature-completion
> span closes ~2026-07-28 (first mature merge 2026-07-21T18:30Z + 7d), and the closing
> completion must itself be merged ≥48h before evaluation — the maturity guard lags the
> closing edge by ~2 days on top of the span. Preconditions before any
> flip: the mechanical demotion watcher (scratch#41) replaces ad-hoc verification.
> Same change: fire cadence hourly → **15-min grid** (slot attestation generalized,
> tolerance 480s; quantified residual — accidental Run-now attests within ~53% of the hour
> vs ~17% before, accepted against the accidental-kick threat model + transcript-join
> primacy + watcher; historic negative re-classification under the new grid is inert
> today — the only manual runs are pre-window or failed); lease TTL 1h stopgap
> (TODO plugins#1034 sub-hour protocol); label-kick event-driven dispatch filed
> (scratch#42) to retire polling waste. Desktop task schedule flip is the operator's
> single remaining action, gated on the merged attestation code (done). The Phase 2
> missed-fire detector is still specced against the hourly cadence (its wiring was already
> deferred to Phase 4) — re-spec + revalidation against the 15-min slot grid filed as
> scratch#66; until it lands, individual missed 15-min slots have no automated signal
> beyond failure tracker items and run history. Same consequence split as the 2026-07-21
> pause incident: the C2 PREDICATE window is unaffected by the cadence flip (its span
> measures mature completions, not slot coverage), but the roadmap ACCEPTANCE clock
> ("fires on schedule with zero manual kicks for ≥1 week") RESTARTS at the timestamp the
> Desktop task's schedule actually flips to the 15-min grid — the prior hourly stretch
> misses three of every four slots under the new grid and cannot count toward a week of
> on-schedule 15-min operation.
>
> **Delegated-merge amendment (recorded 2026-07-22):** during accumulation the de facto
> merge path has been operator-DELEGATED main-session merges — the interactive main
> session (distinct model + context from the drain runs) empirically verifies gate via
> check-run API, diff-vs-seed, and linkage before each squash-merge, under the operator's
> standing watch directive. This is a fresh-context verification tier, not human review
> per merge, and not run self-merge; recorded so the evidence base describes what actually
> happened. The predicate's "autonomous completion" definition (claim→implement→PR, no
> help) is unaffected — and it applies to the runs counted: a run whose PR needed a
> delegated pre-merge correction (scratch#24's `Refs` → `Closes` linkage fix by the
> verifying session) produced its valid PR WITH help and is not an autonomous completion.
> Corrected runs are excluded from the predicate's INPUT SET — every aggregate (completion
> count, span, gate pass rate, revert count) computes over genuinely autonomous completions
> only, so a repaired run can neither be counted nor anchor the ≥7-day span's earliest or
> latest mature completion. Applied by hand (raw rows minus corrected runs; currently
> exactly one, scratch#24, which is not a span edge — the ~2026-07-30/31 eligibility figure
> is unaffected) until the mechanical exclusion lands in the predicate filter (scratch#60,
> re-scoped to the input set). Dispatch's `Closes` guard (scratch#47) prevents the defect
> class recurring.
>
> **Forward policy (external review, 2026-07-23):** this record is a disclosed caveat on
> the rows already merged that way, not standing authorization. From this note forward,
> pre-promotion drain-PR merges are human-gated — each merge is a per-PR human action (or
> an explicit per-PR human instruction naming the PR); no standing directive lets a
> session merge counted evidence on its own schedule. Rationale: a session-initiated
> merge before the flip would already exercise the C2 auto-merge cell the accumulation is
> meant to earn, making the evidence circular.

Standing lane: missed-fire detector + failure tracker items are the automated signal; human
merges the day's drain PRs (this is the pre-promotion policy, not a kick); weekly usage
review (budget revisit trigger); predicate inputs accumulate toward the re-bound
7-day/20-mature-completion thresholds (scratch#43).
Demotion events fire fail-closed per work-classes.

Two DEADLINE work items (alignment audit 2026-07-21 — both must land BEFORE day 14 of the
accumulation window or the first eligibility claim is hollow and the window re-accumulates):

1. **Gate substance**: extend `gate.yml` beyond shellcheck+JSON validity so it exercises the
   changed surface of drain PRs (minimal test step at least) — a near-vacuous gate makes
   "100% deterministic-gate pass" weak promotion evidence (Boris 1→2: "a self-verification
   loop you trust").
2. **Revert detection**: `human_revert_count` is currently 0 by construction
   (`TODO(#778)` in verify-join) — the predicate's "0 human-reverted merges" input cannot
   fail until this lands.

**Sanity Check:** at day 7: predicate stub shows ≥1 week of scheduled fires with zero manual
INITIATIONS (run history: no manual entries post-warm-up; human merges expected and fine);
gaps named as dated scope notes in the roadmap PLAN.

## Blast radius

MEDIUM (was MEDIUM-HIGH before rework): unattended runs now open PRs only (no autonomous
merge), execute in disposable worktrees, on a mechanically bounded inner invocation, with
classification read-only to the run. Contained to the scratch repo. Remaining live risks:
prompt-injection via demo-item content (mitigated: C2-label-only claims, no label mutation,
no binding write), quota exhaustion (plan-window backstop + Sonnet pin), Desktop-surface
behavior assumptions (worktree branch point, nested `claude -p` auth) verified at smoke.

## Stress-test summary

Devils-advocate pass 2026-07-21 (fresh-context): 4 CRITICAL / 4 HIGH / 5 MEDIUM / 2 LOW —
all folded. Load-bearing reversals: human-merge during accumulation (kills evidence
circularity + step-skip), real CI gate with API-read outcomes (kills self-reported pass),
native worktree toggle (kills live-checkout collision), governance-sourced C2 label as the
only claim key (kills agent-writable classification), Sonnet + max-budget-usd on the inner
invocation (kills the Opus hardcode leak + unbounded runs), availability trio restored
(autostart, missed-fire detector, reboot survival), durable tracker-item failure signal,
nightly evidence backup, per-run session-id + 2h drain lease TTL, predicate filtered to
scheduled-fire identity. One noted non-finding: subscription-auth-on-scheduled-tasks stays
an assumption until the smoke run (roadmap-flagged).

## Execution shape

| Phase | Surface | Basis |
|---|---|---|
| 1 | Opus builder in worktree on autonomy-demo-scratch; main thread reviews + commits | Mechanical script/CI work, file-disjoint from plugins repo |
| 2 | Main thread + operator | Machine-local GUI surfaces; warm-up needs the human |
| 3 | Main thread | Empirical verification only |
| 4 | Standing lane (babysit cadence) | Watch, not build |

Sequential 1→2→3; 4 standing.

## Handoff to implementation

### User-approval gates

- This reworked plan (stress-test reversals — notably human-merge-during-accumulation).
- Keep-awake + autostart toggles, permission always-allows (operator-only actions).
- Any scope growth beyond the scratch repo.

### Mechanical work

- Builder scope-fence: ALLOWED `<scratch-repo-root>/tools/**`,
  `.github/workflows/**` (new gate), `.claude/autonomy/binding.json` (build-time conformance
  edit only — excluded from the RUN's allowlist); FORBIDDEN: git commands, this PLAN.md,
  anything in claude-code-plugins.
- Main thread verifies each Phase 1 item empirically before commit; scratch-repo commit
  conventions apply.
- This PLAN.md commits on `feat/autonomy-ignition`; phase tags advance as phases complete.
