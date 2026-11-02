# Lane audit against the outage pause-and-resume posture

This audit checks each of the 14 lanes in `.github/actions/resolve-config/lane-rules.json` against
the six elements of the outage posture (#9205, owner decision Q677). It is slice 3 of #9205,
and issue #12291 is part 1 of 2 of #12283. Every `path:line` points into commit `222d8023`. Line numbers
drift as the files change, so re-read a cited line before relying on it. This page assumes you
know the lanes and their terms (the hub, the kill switch, the reconciler) from
[the pr-pipeline convention](conventions/pr-pipeline/README.md).

Each lane's table has one row per element, with one of three verdicts:

- **met**: a cited line shows the element holds.
- **gap**: the element is missing or only partly there.
- **not applicable**: the lane has no such behavior here, such as no cron or no workflow in this
  repository.

## The six elements

1. **Retries.** Scripts retry and the model never does. Each call gets at most 3 attempts. A
   script waits for `retry-after` when the header is present. For a primary rate limit it waits
   until `x-ratelimit-reset`, and for a secondary limit at least 60 s. Otherwise it uses capped
   exponential backoff with full jitter. A wait longer than a small per-step budget counts as
   unknown under element 2 instead of a sleep. Non-idempotent writes are never retried.
2. **Unknown holds.** A failed read, or a 200 whose completeness check fails, makes the verdict
   unknown. The lane then holds, files nothing, merges nothing, and exits green with a notice.
3. **Next tick probes.** The next existing cron tick is the probe. There is no stored breaker, no
   re-arm and no status-page trigger.
4. **Positive evidence.** A lane demotes or files a failure only on positive evidence from a
   complete read. When a later complete read contradicts a record the lane filed, the lane closes
   it.
5. **Status page.** The GitHub status page never gates, opens or closes anything. A hold notice may
   quote it as context.
6. **No extra load.** Reads are serial and repeated polls send conditional requests (`etag`).
   Scheduled lanes keep the default single-pending concurrency. Optional work is skipped while the
   state is unknown, and other lanes stay off minute 0.

Shared code shows up in many rows. `createGitHub` and `budgetedFetch`
(`.github/scripts/pr-unblock/request-budget.mjs:33`) use the retry at
`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:145`, which sends a read up to 4
times, after waits of 2, 4 and 8 s with equal jitter. The rate guard refuses a call during a
rate-limit stop instead of waiting it out (`.github/actions/log-api-budget/rate-guard.mjs:447`). The listing helper `.github/scripts/pr-merge/retry-call.bash:39` meets
element 1, but only pr-merge uses it.

## work-resolve-issue

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/work-resolve-issue/retry-fetch.mjs:13`, `.github/scripts/work-resolve-issue/report-outcome.mjs:2348` | A 403 or 429 returns at once without waiting for `retry-after` or the reset, and a PR create can go out a second time after a network error. |
| 2 | gap | `.github/scripts/work-resolve-issue/report-outcome.mjs:1824`, `.github/workflows/work-resolve-issue.yml:185` | `--find-prior` goes red on a failed read, and a failed WIP-cap read lets the run start anyway. |
| 3 | gap | `.github/workflows/work-resolve-issue.yml:160` | When the live WIP read fails, a cached "last known pause" decides. That is a stored breaker. |
| 4 | gap | `.github/scripts/work-resolve-issue/report-outcome.mjs:2205`, `.github/scripts/work-resolve-issue/stop-routes.json:25` | A failed labeler read holds the PR for a person, and `retry-spent` fails the issue even when every retry was a fault. |
| 5 | gap | `.github/workflows/work-resolve-issue.yml:66`, `.github/workflows/work-resolve-issue.yml:129` | The status-page result (`degraded`) gates the admit job's `proceed` output. |
| 6 | gap | `.github/workflows/work-resolve-issue.yml:327`, `.github/scripts/lib/handoff-evidence.sh:105` | Three jobs run the repeated job-listing poll with no `etag`. One pending run per issue (`:40`) and the slot cap (`:150`) are fine. |

## intake-triage

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/intake-triage/apply-verdict.mjs:824`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:145` | The shared client sends up to 4 attempts with equal jitter, and the rate guard stops without waiting. |
| 2 | gap | `.github/scripts/intake-triage/apply-verdict.mjs:882`, `.github/scripts/intake-triage/apply-verdict.mjs:890` | An admission or read error sets `exitCode = 1` instead of holding green with a notice. |
| 3 | not applicable | `.github/workflows/intake-triage.yml:33` | The lane triggers only on `issues` and `workflow_dispatch`, with no cron and no stored breaker. |
| 4 | gap | `.github/scripts/intake-triage/admit.mjs:2166` | A failed visibility read treats the repository as private, which tightens the cost checks without evidence. It does lift its own holds (`.github/workflows/intake-triage.yml:312`). |
| 5 | gap | `.github/workflows/intake-triage.yml:210`, `.github/workflows/intake-triage.yml:248` | `upstream-degraded` blocks the triage job. |
| 6 | met | `.github/workflows/intake-triage.yml:255`, `.github/workflows/intake-triage.yml:595` | There is one pending run per issue, the optional refine step runs only after apply-verdict succeeds, and reads are sequential. |

## work-unblock

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/work-unblock/label-unblocked.mjs:2204`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:145` | The shared client sends up to 4 attempts with equal jitter, and a rate limit fails the step without waiting for the reset. |
| 2 | gap | `.github/scripts/work-unblock/label-unblocked.mjs:2245`, `.github/scripts/work-unblock/label-unblocked.mjs:2255` | A failed listing increments `failed`, and the run exits 1. |
| 3 | gap | `.github/workflows/work-unblock.yml:30`, `.github/scripts/work-unblock/label-unblocked.mjs:168` | A marker-issue sweep-kick re-arms the sweep after the rate-limit breaker clears, and breaker-trip records are stored for each issue. |
| 4 | met | `.github/scripts/work-unblock/label-unblocked.mjs:194`, `.github/scripts/work-unblock/label-unblocked.mjs:82` | The lane lifts its own refs-hold `needs-human` once the PR merges or closes, and infrastructure re-fires never file `needs-human`. |
| 5 | met | `.github/workflows/work-unblock.yml:170` | The kill switch is the only pre-gate. No status-page step runs. |
| 6 | gap | `.github/workflows/work-unblock.yml:146` | `queue: max` keeps every pending run instead of one, and the hourly sweep sends no `etag`. The cron at minute 47 is fine. |

## pr-refine

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/lib/handoff-evidence.sh:58`, `.github/workflows/pr-refine.yml:141` | `handoff-evidence` makes up to 6 reads on fixed delays with no jitter, and the head-SHA read is never retried. |
| 2 | gap | `.github/workflows/pr-refine.yml:142`, `.github/scripts/lib/handoff-evidence.sh:127` | A failed read exits 1 instead of holding green. |
| 3 | gap | `.github/scripts/pr-unblock/fix-docs-dispatch.mjs:178`, `.github/scripts/pr-unblock/fix-docs-dispatch.mjs:258` | The dispatcher counts any completed run, including a red outage run, as done, so the next tick never re-dispatches it. |
| 4 | gap | `.github/actions/report-check-run/decide.mjs:104`, `.github/workflows/pr-run-activity-read.yml:3661` | A run with no verdict, such as an outage-caused broker failure, posts a `failure` check, and nothing closes it later. |
| 5 | gap | `.github/workflows/pr-unblock-dispatch.yml:109`, `.github/workflows/pr-unblock-dispatch.yml:184` | The lane's only automatic starter skips the whole dispatch while the status page lists an outage. |
| 6 | gap | `.github/scripts/lib/handoff-evidence.sh:105` | The repeated job-listing poll sends no `etag`. Concurrency (`.github/workflows/pr-refine.yml:47`) is fine. |

## pr-run-checks

The lane has no workflow or script in this repository. It is declared at
`.github/actions/resolve-config/lane-rules.json:22`, and `.github/standards/runner-policy/policy.json:273`
points at a reusable in `melodic-software/ci-workflows`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | `.github/actions/resolve-config/lane-rules.json:22` | Nothing in this repository makes calls for the lane. |
| 2 | not applicable | `.github/actions/resolve-config/lane-rules.json:22` | Nothing reads. |
| 3 | not applicable | `docs/conventions/pr-pipeline/README.md:150` | The lane has no cron and starts only by dispatch. |
| 4 | not applicable | `.github/actions/resolve-config/lane-rules.json:22` | Nothing files. |
| 5 | not applicable | `.github/standards/runner-policy/policy.json:273` | Only an external reusable is referenced. |
| 6 | not applicable | `.github/standards/runner-policy/policy.json:273` | There is no concurrency or cron block here. |

## pr-review

The lane runs from `.github/workflows/pr-review-hosted.yml`, a caller of the external
`pr-review-cli.yml`, and the `claude-review` row of `.github/workflows/pr-review-main.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:145`, `.github/workflows/pr-review-main.yml:194` | The shared client sends up to 4 attempts with equal jitter, and the file-list read is never retried. |
| 2 | gap | `.github/workflows/pr-review-main.yml:194`, `.github/workflows/pr-review-main.yml:1007` | A failed read fails the step, and "no verdict" exits 1. |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:79`, `.github/workflows/pr-review-hosted.yml:183` | Recovery is a recorded one-time re-run by the reconciler, gated on the status page. That is a re-arm and a status-page trigger. |
| 4 | gap | `.github/workflows/pr-review-main.yml:2656` | A later clean review never clears a CRITICAL check run. |
| 5 | gap | `.github/workflows/pr-review-hosted.yml:168`, `.github/workflows/pr-review-main.yml:287` | `check-upstream-status` stops the review with exit 1. |
| 6 | gap | `.github/workflows/pr-review-main.yml:222`, `.github/workflows/pr-review-main.yml:503` | Matrix legs run in parallel and repeat the same PR reads with no `etag`. Concurrency per PR is fine. |

## pr-review-security

The lane runs from `.github/workflows/pr-review-security-hosted.yml` and the
`claude-security-review` row of `.github/workflows/pr-review-main.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:145`, `.github/workflows/pr-review-main.yml:194` | It shares pr-review's code, so it has the same gap. |
| 2 | gap | `.github/workflows/pr-review-main.yml:194`, `.github/workflows/pr-review-main.yml:1007` | A failed read or "no verdict" makes the run red. |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:79`, `.github/workflows/pr-review-security-hosted.yml:188` | Resume depends on the reconciler's status-gated re-run. |
| 4 | gap | `.github/workflows/pr-review-main.yml:2656` | A later complete read never closes a filed CRITICAL count. |
| 5 | gap | `.github/workflows/pr-review-security-hosted.yml:173`, `.github/workflows/pr-review-security-hosted.yml:193` | The status page gates the run and turns it red. |
| 6 | gap | `.github/workflows/pr-review-main.yml:222`, `.github/workflows/pr-review-main.yml:503` | Matrix legs run in parallel and repeat the same reads with no `etag`. |

## pr-verify

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:145`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:139` | The shared client sends up to 4 attempts with equal jitter, and the rate latch refuses without waiting. Writes go out once. |
| 2 | gap | `.github/scripts/pr-verify/resolve-pr.mjs:586`, `.github/scripts/pr-verify/resolve-pr.mjs:1062` | Completeness checks throw, but the throw sets `exitCode = 1`, so the run goes red. |
| 3 | gap | `.github/workflows/pr-verify.yml:130`, `.github/workflows/maintenance-reconcile-lost-runs.yml:9` | A stopped run fails on purpose so the reconciler re-runs it once, from an attempt record. That is a re-arm. |
| 4 | met | `.github/workflows/pr-verify.yml:51`, `.github/scripts/pr-verify/resolve-pr.mjs:46` | A FAIL needs a complete judgment, and a later pass supersedes it. |
| 5 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:128` | The only resume path does nothing unless the status page shows Actions operational. |
| 6 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:1024` | The re-run record is polled again without `etag`. Concurrency (`.github/workflows/pr-verify.yml:82`) and serial reads are fine. |

## pr-explain

The lane has no workflow or script in this repository. It is declared at
`.github/actions/resolve-config/lane-rules.json:42`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | `.github/actions/resolve-config/lane-rules.json:42` | The lane makes no calls. |
| 2 | not applicable | `.github/actions/resolve-config/lane-rules.json:42` | The lane makes no reads. |
| 3 | not applicable | `docs/conventions/pr-pipeline/README.md:153` | The lane has no cron. |
| 4 | not applicable | `.github/actions/resolve-config/lane-rules.json:45` | The lane files nothing and may not gate. |
| 5 | not applicable | `.github/actions/resolve-config/lane-rules.json:42` | No code here consults a status page. |
| 6 | not applicable | `docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml:146` | There is no workflow. |

## pr-require-checks

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/workflows/pr-require-checks.yml:4826`, `.github/workflows/pr-require-checks.yml:4679` | Callers loop 3 times with linear sleeps around a `gh_read` that can send twice, so a read can go out 6 times. A guessed secondary limit fails at once. Status writes are retried (`:4033`). |
| 2 | gap | `.github/workflows/pr-require-checks.yml:4681`, `.github/workflows/pr-require-checks.yml:4830` | A read failure fails the check red on purpose instead of holding green. |
| 3 | gap | `.github/workflows/pr-require-checks.yml:4685` | A held result recovers only through another lane's re-run, a person or the reconciler. The cron at `:29` is not the probe. |
| 4 | gap | `.github/workflows/pr-require-checks.yml:7079` | A missing review run sets `failed=1`, which fails on absent evidence. |
| 5 | gap | `.github/workflows/pr-require-checks.yml:7084`, `.github/workflows/pr-require-checks.yml:7140` | A review the status-page gate stopped becomes a red `ci-status`. |
| 6 | gap | `.github/workflows/pr-require-checks.yml:89`, `.github/workflows/pr-require-checks.yml:109` | Scheduled runs each get their own `run_id` group, so the lane is not single-pending, and it sends no `etag`. The cron (`17 9,16`) is off minute 0. |

## pr-unblock

The lane runs from `.github/workflows/pr-unblock.yml`, with the dispatchers
`.github/workflows/pr-unblock-dispatch.yml` and `.github/workflows/pr-feedback-dispatch.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/pr-unblock/report-escalation.sh:314`, `.github/scripts/pr-unblock/request-budget.mjs:39` | A comment POST, a write, is retried 3 times on fixed sleeps, and rate-limit waits can total 6 minutes. |
| 2 | gap | `.github/scripts/pr-unblock/dispatch.mjs:254`, `.github/scripts/pr-unblock/dispatch.mjs:835` | A non-5xx read failure counts as `failed` and exits 1. |
| 3 | gap | `.github/scripts/pr-unblock/dispatch.mjs:229`, `.github/scripts/pr-unblock/limit-stop.mjs:21` | Failed runs, outage failures included, use up a cap for each head that blocks re-dispatch until a new push. That is a stored breaker. |
| 4 | gap | `.github/scripts/pr-unblock/escalation-routes.json:27`, `.github/scripts/pr-unblock/report-escalation.sh:106` | A job fault, such as a lane token that was not obtained, files a fail route, and an unlisted reason holds the PR for a person. Its `clear` mode (`:74`) does clear its own status. |
| 5 | gap | `.github/workflows/pr-unblock-dispatch.yml:109`, `.github/workflows/pr-feedback-dispatch.yml:381` | `degraded` gates the dispatch steps. |
| 6 | gap | `.github/scripts/pr-unblock/gate-source.mjs:447`, `.github/workflows/pr-feedback-dispatch.yml:118` | `Promise.all` reads in parallel, and the sweep group uses `queue: max`. The `etag` use (`request-budget.mjs:86`) and the cron at minutes 9 and 39 are fine. |

## pr-merge

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/pr-merge/retry-call.bash:39`, `.github/scripts/pr-merge/enable-auto-merge.mjs:357` | The listing's `retry_call` meets the element. The shared client still sends a read up to 4 times, `withRetry` stacks on top of it, and `.github/actions/request-lane-token/action.yml:287` can sleep up to 480 s. |
| 2 | gap | `.github/workflows/pr-merge.yml:1187`, `.github/workflows/pr-merge.yml:1193` | A failed listing holds green. A listing at the limit and the rate-limit stops (`:290`, `:349`, `:899`, `:1399`, `:1705`) end red, and a failed cover read dispatches with no cap (`:351`). |
| 3 | gap | `.github/workflows/pr-merge.yml:1075` | The lane's own hold waits for the next tick. But the hub's lane breaker sets the stored kill switch, which pr-merge stops on, and a person must clear it. |
| 4 | gap | `.github/workflows/pr-merge.yml:1419`, `.github/workflows/pr-merge.yml:1413` | The lane files only on a judged failure and skips filing on a held listing. Only a person closes the demotion record (`plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py:3416`). |
| 5 | met | `.github/workflows/pr-merge.yml:1187` | The hold notice reads no status page, and nothing in the lane reads githubstatus. |
| 6 | gap | `.github/workflows/pr-merge.yml:852`, `.github/workflows/pr-merge.yml:98` | The cron (minutes 11, 26, 41, 56) is off minute 0 and the gate loop is serial. But the jobs use `queue: max` (also `:2186`, `:2910`), and nothing sends `etag`. |

### How pr-merge surfaces a permanent fault (element 2)

- **A bad `GITHUB_TOKEN` on the listing.** `retry_call` tries 3 times, then the job prints only
  `::notice title=Merge lane hold::` and ends green (`.github/workflows/pr-merge.yml:1187`). The
  sweep summary records `listing_held` (`.github/workflows/pr-merge.yml:1911`). After 4 held sweeps
  in a row, `maintenance-monitor-signals` updates a rolling issue
  (`.github/scripts/maintenance-monitor-signals/signals.mjs:385`). That issue is how a person
  hears about it.
- **A bad lane token.** A broker refusal or an unreachable broker prints `::error::` and turns the
  job red (`.github/actions/request-lane-token/action.yml:179`, `:337`, `:398`). In
  enable-auto-merge it prints `::error title=enable-auto-merge::` and turns red
  (`.github/scripts/pr-merge/enable-auto-merge.mjs:2366`).
- **1000 or more open pull requests.** The job prints `::error::` and ends red
  (`.github/workflows/pr-merge.yml:1193`). It files no issue and writes no held summary
  (`.github/workflows/pr-merge.yml:1901`), so the signal never counts it. enable-auto-merge
  throws (`.github/scripts/pr-merge/enable-auto-merge.mjs:1635`) and also ends red.
- **A rate limit during a green hold.** The shared `api_budget_stop` still prints `::error::`
  (`.github/actions/log-api-budget/api-budget.bash:388`). `retry_call` passes that stderr through
  (`.github/scripts/pr-merge/retry-call.bash:28`), and the step then ends green with the notice.

This audit did not verify whether GitHub can return a short listing and a short `totalCount`
together.

## post-merge-verify

The lane has no workflow or script in this repository. It is declared at
`.github/actions/resolve-config/lane-rules.json:68`. Only the example config lists it
(`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml:171`).

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | `.github/actions/resolve-config/lane-rules.json:68` | Nothing in this repository makes calls for the lane. |
| 2 | not applicable | `docs/conventions/pr-pipeline/README.md:158` | The trigger is documented, but no workflow implements it. |
| 3 | not applicable | `docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml:171` | `docs/conventions/pr-pipeline.yaml` has no such lane, so there is no cron. |
| 4 | not applicable | `.github/actions/resolve-config/lane-rules.json:68` | Nothing files. |
| 5 | not applicable | `.github/actions/resolve-config/lane-rules.json:68` | There is no code to check. |
| 6 | not applicable | `.github/actions/resolve-config/lane-rules.json:68` | There is no workflow. |

## post-merge-sweep-comments

The lane has no workflow or script in this repository. It is declared at
`.github/actions/resolve-config/lane-rules.json:73`. The example config lists it with
`enabled: false` (`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml:175`).

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | `.github/actions/resolve-config/lane-rules.json:73` | Nothing in this repository makes calls for the lane. |
| 2 | not applicable | `docs/conventions/pr-pipeline/README.md:159` | The trigger is documented, but no workflow implements it. |
| 3 | not applicable | `docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml:175` | The lane has no cron. |
| 4 | not applicable | `.github/actions/resolve-config/lane-rules.json:73` | Nothing files. |
| 5 | not applicable | `.github/actions/resolve-config/lane-rules.json:73` | There is no code to check. |
| 6 | not applicable | `.github/actions/resolve-config/lane-rules.json:73` | There is no workflow. |

## Remaining

This change fixes no gap. The **workflow** gaps below need a workflow-file change, which this lane
cannot push. The **script** gaps are part 2 of #12283, which fixes them with a test for each
element. #12282 builds element 4's self-close.

| Lane | Element | Kind | File to change |
|---|---|---|---|
| shared | 1 | script | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs` (`SERVER_RETRY_DELAYS_MS`, full jitter, wait on the rate latch) |
| shared | 1, 2 | script | `.github/actions/log-api-budget/rate-guard.mjs` (wait out a short reset; hold instead of failing) |
| shared | 2 | script | `.github/actions/log-api-budget/api-budget.bash` (a notice instead of `::error::` when the caller holds) |
| work-resolve-issue | 1, 2, 4 | script | `.github/scripts/work-resolve-issue/retry-fetch.mjs`, `report-outcome.mjs`, `stop-routes.json` |
| work-resolve-issue, pr-refine | 6 | script | `.github/scripts/lib/handoff-evidence.sh` (`etag` on the repeated job-listing poll) |
| work-resolve-issue | 2, 3, 5 | workflow | `.github/workflows/work-resolve-issue.yml` (WIP check fails open, cached pause, status gate) |
| intake-triage | 2, 4 | script | `.github/scripts/intake-triage/apply-verdict.mjs`, `admit.mjs` |
| intake-triage | 5 | workflow | `.github/workflows/intake-triage.yml` |
| work-unblock | 2, 3, 6 | script | `.github/scripts/work-unblock/label-unblocked.mjs` |
| work-unblock | 3, 6 | workflow | `.github/workflows/work-unblock.yml` (sweep-kick, `queue: max`) |
| pr-refine | 1, 2, 3, 4 | script | `.github/scripts/lib/handoff-evidence.sh`, `.github/scripts/pr-unblock/fix-docs-dispatch.mjs`, `.github/actions/report-check-run/decide.mjs` |
| pr-refine | 1, 2, 4, 5 | workflow | `.github/workflows/pr-refine.yml`, `pr-run-activity-read.yml`, `pr-unblock-dispatch.yml` |
| pr-review, pr-review-security, pr-verify | 3, 5 | script | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs` |
| pr-review, pr-review-security | 4 | larger | `plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py` (outside `.github/`) |
| pr-review, pr-review-security | 1, 2, 3, 4, 5, 6 | workflow | `.github/workflows/pr-review-main.yml`, `pr-review-hosted.yml`, `pr-review-security-hosted.yml` |
| pr-verify | 2, 6 | script | `.github/scripts/pr-verify/resolve-pr.mjs`, `check-trusted-trigger.mjs` |
| pr-verify | 2, 3 | workflow | `.github/workflows/pr-verify.yml` |
| pr-require-checks | 1, 2, 3, 4, 5, 6 | workflow | `.github/workflows/pr-require-checks.yml` |
| pr-unblock | 1, 2, 3, 4, 6 | script | `.github/scripts/pr-unblock/report-escalation.sh`, `request-budget.mjs`, `dispatch.mjs`, `limit-stop.mjs`, `escalation-routes.json`, `gate-source.mjs` |
| pr-unblock | 5, 6 | workflow | `.github/workflows/pr-unblock-dispatch.yml`, `pr-feedback-dispatch.yml` |
| pr-merge | 1, 2 | script | `.github/scripts/pr-merge/enable-auto-merge.mjs`, `.github/actions/request-lane-token/action.yml` |
| pr-merge | 2, 6 | workflow | `.github/workflows/pr-merge.yml` (listing-full and rate-limit exits, cover-read dispatch, `queue: max`) |
| pr-merge | 2 | workflow | `.github/workflows/pr-merge.yml:1192`: hold green on a full listing and count it toward the monitor signal, so 1000 or more open pull requests reaches a person the way a held listing does |
| pr-merge | 3 | larger | the hub's lane breaker and kill switch, outside this repository |
| pr-merge | 4 | larger | `plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py` plus a `.github/workflows/pr-merge.yml` step (#12282) |
