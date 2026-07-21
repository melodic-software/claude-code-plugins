# autonomy-ignition — PLAN (#778)

Sub-topic of `docs/topics/ladder-climb-roadmap/PLAN.md` Phase I (on `main` since PR #794).
Design record: interview rulings (ledger committed in the roadmap topic) +
`design/design-resolution.md`.

## Brief

Ignite the 2→3 loop: the first standing routine (hourly C2 drain) + C2-promotion evidence
drain on `kyle-sexton/autonomy-demo-scratch` (binding-ratified surfaces `label-kick` +
`hourly-drain`, execution surface `demo-local-session`). Purpose: accumulate the evidence
stream whose predicate (≥20 autonomous C2 completions / ≥14 days / 100% deterministic-gate
pass / 0 human-reverted merges — `plugins/autonomy/reference/guardrails/work-classes.md`)
makes the C2 auto-merge cell ELIGIBLE. Promotion flips stay human-ratified.

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
| Schedule | Hourly preset + Desktop **Keep computer awake** ON (Settings → Desktop app → General). Lid-close still sleeps (accepted). |
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
- Upstream recheck standing trigger (done 2026-07-21: desktop-scheduled-tasks doc — native
  overlap-skip, single catch-up, worktree toggle, per-task model + permission pickers).
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

### Phase 2: Native task + machine posture [TODO]

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
   post-reboot/Windows-Update detector the freeze week needs.
5. Visibility: native run history + notifications; PRs are the GitHub artifacts; scoreboard =
   verify-join; failure/missed-fire tracker items are the durable signal.

**Sanity Check:**

- `ls ~/.claude/scheduled-tasks/` lists `autonomy-demo-hourly-drain/`; its `SKILL.md` body
  names `drain-next.sh`.
- One happy-path AND one forced-failure **Run now** complete with zero permission stalls;
  the failure run filed its tracker item.
- Missed-fire detector dry-run: seeded gap produces the tracker item.

### Phase 3: Smoke + first scheduled fire [TODO]

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

### Phase 4: Accumulation watch [TODO — standing]

Standing lane: missed-fire detector + failure tracker items are the automated signal; human
merges the day's drain PRs (this is the pre-promotion policy, not a kick); weekly usage
review (budget revisit trigger); predicate inputs accumulate toward 14-day/20-completion.
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
