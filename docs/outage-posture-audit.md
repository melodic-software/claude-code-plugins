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
   re-arm and no status-page trigger (element 5).
4. **Positive evidence.** A lane demotes or files a failure only on positive evidence from a
   complete read. When a later complete read contradicts a record the lane filed, the lane closes
   it.
5. **Status page.** The GitHub status page may stop work but never starts it. A lane may idle while
   the page lists an Actions outage, and it resumes only when the page is green and its own reads
   succeed. The page never opens or closes a record, and a hold notice may quote it as context
   (owner decision, #12292).
6. **No extra load.** Reads are serial and repeated polls send conditional requests (`etag`).
   Scheduled lanes keep the default single-pending concurrency. Optional work is skipped while the
   state is unknown, and other lanes stay off minute 0.

Shared code shows up in many rows. `createGitHub` and `budgetedFetch`
(`.github/scripts/pr-unblock/request-budget.mjs:36`) use the retry at
`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201`, which sends a read up to 3
times, after waits of up to 2 and 4 s with full jitter. The rate guard waits out a rate-limit stop
that resets within 60 s (`.github/actions/log-api-budget/rate-guard.mjs:580`) and refuses a call
past that (`.github/actions/log-api-budget/rate-guard.mjs:590`), with a notice instead of an error
under `API_BUDGET_HOLD=1`.
Part 2 changed both (see Remaining). The listing helper `.github/scripts/pr-merge/retry-call.bash:39` meets
element 1, but only pr-merge uses it.

## work-resolve-issue

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/work-resolve-issue/retry-fetch.mjs:13`, `.github/scripts/work-resolve-issue/report-outcome.mjs:2348` | A 403 or 429 returns at once without waiting for `retry-after` or the reset, and a PR create can go out a second time after a network error. |
| 2 | met | `.github/scripts/work-resolve-issue/report-outcome.mjs:2190`, `.github/actions/check-wip-cap/check-wip-cap.mjs:399`, `.github/workflows/work-resolve-issue.yml:292` | `--find-prior` holds green on a failed read (see Remaining). A WIP-cap read the pause depends on that fails or answers incomplete sets `capped` `true` with a `WIP cap hold` notice (`check-wip-cap.mjs:405`), and resolve-issue starts only on `capped` `false`, so a check that sets nothing holds too, with pick-slot's notice (`work-resolve-issue.yml:246`). A rate limit past the guard's budget still prints the guard's `::error::` on the green job, since the check is a gate and sets no `API_BUDGET_HOLD`. |
| 3 | met | `.github/actions/check-wip-cap/action.yml:64`, `.github/workflows/work-unblock.yml:105` | No cache is restored or saved, so no earlier pause decides. A held run reads as a WIP cap skip, and work-unblock's sweep (cron and `workflow_run`) re-fires it, whose run reads again. |
| 4 | gap | `.github/scripts/work-resolve-issue/report-outcome.mjs:2205`, `.github/scripts/work-resolve-issue/stop-routes.json:25` | A failed labeler read holds the PR for a person, and `retry-spent` fails the issue even when every retry was a fault. |
| 5 | met | `.github/workflows/work-resolve-issue.yml:66`, `.github/workflows/work-resolve-issue.yml:129` | The status-page result (`degraded`) gates the admit job's `proceed` output. That is a stop, and the page starts nothing. |
| 6 | gap | `.github/workflows/work-resolve-issue.yml:327`, `.github/scripts/lib/handoff-evidence.sh:105` | Three jobs run the repeated job-listing poll with no `etag`. One pending run per issue (`:40`) and the slot cap (`:150`) are fine. |

## intake-triage

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/intake-triage/apply-verdict.mjs:824`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201` | The shared client sends up to 3 attempts with full jitter, and the rate guard waits out a reset within 60 s, then refuses (a notice under the hold opt-in). |
| 2 | gap | `.github/scripts/intake-triage/apply-verdict.mjs:882`, `.github/scripts/intake-triage/apply-verdict.mjs:890` | An admission or read error sets `exitCode = 1` instead of holding green with a notice. |
| 3 | not applicable | `.github/workflows/intake-triage.yml:33` | The lane triggers only on `issues` and `workflow_dispatch`, with no cron and no stored breaker. |
| 4 | gap | `.github/scripts/intake-triage/admit.mjs:2166` | A failed visibility read treats the repository as private, which tightens the cost checks without evidence. It does lift its own holds (`.github/workflows/intake-triage.yml:312`). |
| 5 | met | `.github/workflows/intake-triage.yml:210`, `.github/workflows/intake-triage.yml:248` | `upstream-degraded` blocks the triage job. That is a stop, and the page starts nothing. |
| 6 | met | `.github/workflows/intake-triage.yml:255`, `.github/workflows/intake-triage.yml:595` | There is one pending run per issue, the optional refine step runs only after apply-verdict succeeds, and reads are sequential. |

## work-unblock

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/work-unblock/label-unblocked.mjs:2204`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201` | The shared client sends up to 3 attempts with full jitter, and a rate limit within 60 s is waited out, while a longer one fails the step (a notice under the hold opt-in). |
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
| 5 | met | `.github/workflows/pr-unblock-dispatch.yml:109`, `.github/workflows/pr-unblock-dispatch.yml:184` | The lane's only automatic starter skips the whole dispatch while the status page lists an outage. That is a stop, and the page starts nothing. |
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
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201`, `.github/workflows/pr-review-main.yml:307` | The shared client sends up to 3 attempts with full jitter, and the file-list read is never retried. |
| 2 | gap | `.github/workflows/pr-review-main.yml:307`, `.github/workflows/pr-review-main.yml:1139` | A failed read fails the step, and "no verdict" exits 1. |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:79`, `.github/workflows/pr-review-hosted.yml:183` | Recovery is a recorded one-time re-run by the reconciler, which idles while the status page lists an outage (element 5 allows that stop). The one-time record is a re-arm the owner kept: it is the trust proof for an attempt 2 (`check-trusted-trigger.mjs` `verifyRecordedRerun`). |
| 4 | gap | `.github/workflows/pr-review-main.yml:2874` | A later clean review never clears a CRITICAL check run. |
| 5 | met | `.github/workflows/pr-review-hosted.yml:168`, `.github/workflows/pr-review-main.yml:426` | `check-upstream-status` stops the review with exit 1. That is a stop, and the page starts nothing; the red exit is element 2's concern. |
| 6 | gap | `.github/workflows/pr-review-main.yml:340`, `.github/workflows/pr-review-main.yml:457` | Matrix legs run in parallel and repeat the same PR reads with no `etag`. Concurrency per PR is fine. |

## pr-review-security

The lane runs from `.github/workflows/pr-review-security-hosted.yml` and the
`claude-security-review` row of `.github/workflows/pr-review-main.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201`, `.github/workflows/pr-review-main.yml:307` | It shares pr-review's code, so it has the same gap. |
| 2 | gap | `.github/workflows/pr-review-main.yml:307`, `.github/workflows/pr-review-main.yml:1139` | A failed read or "no verdict" makes the run red. |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:79`, `.github/workflows/pr-review-security-hosted.yml:188` | Resume depends on the reconciler's one-time recorded re-run, a re-arm the owner kept as attempt 2's trust proof, as for pr-review. |
| 4 | gap | `.github/workflows/pr-review-main.yml:2874` | A later complete read never closes a filed CRITICAL count. |
| 5 | met | `.github/workflows/pr-review-security-hosted.yml:173`, `.github/workflows/pr-review-security-hosted.yml:193` | The status page gates the run and turns it red. That is a stop, and the page starts nothing; the red is element 2's concern. |
| 6 | gap | `.github/workflows/pr-review-main.yml:340`, `.github/workflows/pr-review-main.yml:457` | Matrix legs run in parallel and repeat the same reads with no `etag`. |

## pr-verify

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:215` | The shared client sends up to 3 attempts with full jitter, and the rate latch waits out a reset within 60 s, then refuses (a notice under the hold opt-in). Writes go out once. |
| 2 | gap | `.github/scripts/pr-verify/resolve-pr.mjs:586`, `.github/scripts/pr-verify/resolve-pr.mjs:1062` | Completeness checks throw, but the throw sets `exitCode = 1`, so the run goes red. |
| 3 | gap | `.github/workflows/pr-verify.yml:130`, `.github/workflows/maintenance-reconcile-lost-runs.yml:9` | A stopped run fails on purpose so the reconciler re-runs it once, from an attempt record. That is a re-arm, which the owner kept as attempt 2's trust proof. |
| 4 | met | `.github/workflows/pr-verify.yml:51`, `.github/scripts/pr-verify/resolve-pr.mjs:46` | A FAIL needs a complete judgment, and a later pass supersedes it. |
| 5 | met | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:128` | The reconciler idles while the status page shows Actions as anything but operational, and re-runs only once it is and its own reads succeed. The page stops the resume path but starts nothing. |
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
| 1 | gap | `.github/workflows/pr-require-checks.yml:4859`, `.github/workflows/pr-require-checks.yml:4689` | Callers loop 3 times with linear sleeps around a `gh_read` that can send twice, so a read can go out 6 times. A guessed secondary limit fails at once. Status writes are retried (`:4044`). |
| 2 | gap | `.github/workflows/pr-require-checks.yml:4691`, `.github/workflows/pr-require-checks.yml:4863` | A read failure fails the check red on purpose instead of holding green. |
| 3 | gap | `.github/workflows/pr-require-checks.yml:4695` | A held result recovers only through another lane's re-run, a person or the reconciler. The cron at `:29` is not the probe. |
| 4 | gap | `.github/workflows/pr-require-checks.yml:6959` | A missing review run sets `failed=1`, which fails on absent evidence. |
| 5 | met | `.github/workflows/pr-require-checks.yml:6964`, `.github/workflows/pr-require-checks.yml:7020` | `ci-status` reads a review the status-page gate stopped and starts nothing from the page. That it reads the stop as red is element 4's concern. |
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
| 5 | met | `.github/workflows/pr-unblock-dispatch.yml:109`, `.github/workflows/pr-feedback-dispatch.yml:388` | `degraded` gates the dispatch steps. That is a stop, and the page starts nothing. |
| 6 | gap | `.github/scripts/pr-unblock/gate-source.mjs:447`, `.github/workflows/pr-feedback-dispatch.yml:111` | `Promise.all` reads in parallel, and the sweep group uses `queue: max` (`:114`). The `etag` use (`request-budget.mjs:86`) and the cron at minutes 9 and 39 are fine. |

## pr-merge

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/scripts/pr-merge/retry-call.bash:39`, `.github/scripts/pr-merge/enable-auto-merge.mjs:357` | The listing's `retry_call` meets the element. The shared client still sends a read up to 3 times, `withRetry` stacks on top of it, and `.github/actions/request-lane-token/action.yml:287` can sleep up to 480 s. |
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
  (`.github/scripts/pr-merge/enable-auto-merge.mjs:2387`).
- **1000 or more open pull requests.** The job prints `::error::` and ends red
  (`.github/workflows/pr-merge.yml:1193`). It files no issue and writes no held summary
  (`.github/workflows/pr-merge.yml:1901`), so the signal never counts it. enable-auto-merge
  throws (`.github/scripts/pr-merge/enable-auto-merge.mjs:1639`) and also ends red.
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

Part 1 (#12291) fixed no gap. The **workflow** gaps below need a workflow-file change, which this
lane cannot push. The **script** gaps are part 2 of #12283 (#12292). #12282 builds element 4's
self-close.

Part 2 fixed these element 1 gaps, each with a test:

- **Shared client.** `createGitHub` and `budgetedFetch` send a read at most 3 times, with full
  jitter (`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`).
- **pr-merge.** `withRetry` resends only a GraphQL mutation, so a query goes out at most 3 times,
  not 12 (`.github/scripts/pr-merge/enable-auto-merge.mjs`).
- **retry-fetch.** The apply-patch, pr-unblock and work-resolve-issue copies wait out a rate limit
  before a resend: `retry-after`, else the reset, else 60 s. A wait past 60 s per client is not
  taken (`.github/scripts/work-resolve-issue/retry-fetch.mjs`).
- **pr-unblock.** The escalation and lane-stopped comment POSTs go out once
  (`.github/scripts/pr-unblock/report-escalation.sh`).

A later part 2 change fixed these gaps, each with a test:

- **pr-unblock, element 1.** `budgetedFetch` resends only a read after a rate limit, so a
  rate-limited POST, PATCH or GraphQL mutation goes out once. The time to each reset, summed over
  the run, stays within a minute, down from 6 minutes. Each wait adds one second so the resend
  lands after the reset (`.github/scripts/pr-unblock/request-budget.mjs`).
- **pr-unblock, element 6.** The lane's scripts send their reads one at a time, not through
  `Promise.all`. For example, the review reader reads review comments and then reviews, and
  `reviewRunAt` lists one review workflow at a time. The files are `gate-source.mjs`,
  `feedback-dispatch.mjs`, `address-feedback.mjs`, `fix-ci-context.mjs` and
  `review-dependency.mjs`, all under `.github/scripts/pr-unblock/`.
- **work-resolve-issue, element 1.** A PR create that failed on the network is read back and never
  sent again. When the read finds no PR, the run fails, and a rerun reuses the PR or opens it
  (`.github/scripts/work-resolve-issue/report-outcome.mjs`).
- **intake-triage, element 4.** A failed visibility read throws, like the other admission reads,
  so it no longer counts the repository as private (`.github/scripts/intake-triage/admit.mjs`).
  work-unblock's admission check shares this read.

A third part 2 change fixed pr-merge's two script gaps, each with a test:

- **pr-merge, element 2.** With more than 1000 open pull requests, `enable-auto-merge.mjs` holds:
  it arms, disarms and notes nothing, prints a `::notice::` and a step summary line, and ends
  green. The next run reads the listing again (`.github/scripts/pr-merge/enable-auto-merge.mjs`).
  The workflow's own listing still ends red at the limit (the `pr-merge.yml:1192` row below).
- **pr-merge, element 1.** The lane-token request sends at most 3 requests and waits at most 60 s
  in all, down from 4 requests and 480 s. A `github-unavailable` retry waits 0 to 20 s, then 0 to
  40 s (full jitter), or a longer `Retry-After`. A wait that does not fit is not taken, and the step
  fails red at once, as it does on any final broker answer: holding the calling job green instead is
  that workflow's change (`.github/actions/request-lane-token/action.yml`).

A fourth part 2 change fixed these gaps, each with a test:

- **work-resolve-issue and pr-refine, element 6.** `handoff-evidence.sh` reads the job listing a
  page at a time. Each read after the first sends each page that came with an `etag` as a
  conditional request, and a `304` reuses the page it already read
  (`.github/scripts/lib/handoff-evidence.sh`).
- **pr-unblock, element 2.** A read that fails, whatever GitHub answered, no longer fails
  `pr-unblock-dispatch.yml`. A listing it cannot read dispatches nothing, and a PR whose reads
  fail is skipped, each with a warning, and the next tick reads them again. Before, a read held
  only on a `5xx`, or in some places a rate limit, and any other failure ended the run red. A
  failed dispatch still does (`dispatch.mjs`, `fix-ci-dispatch.mjs`, `fix-docs-dispatch.mjs` and
  `dependency-dispatch.mjs` under `.github/scripts/pr-unblock/`). Two things are unchanged. A rate
  limit past the guard's wait budget still ends the run red, because the shared rate guard fails
  the step unless the workflow sets `API_BUDGET_HOLD=1` (the shared rows below). And `fix-ci` still dispatches under its caps when it cannot read its required run or
  the head's check runs for a reason other than a `5xx` or a rate limit, or when the verifier
  reader fails.

A fifth part 2 change fixed the shared rate guard's gaps, each with a test:

- **shared, element 1.** The rate latch waits out a stop whose reset fits a 60 s budget per latch
  (`SERVER_RETRY_BUDGET_MS`, the resets summed), plus a second so the call lands after the reset,
  and then sends the call instead of refusing it. `createGitHub` sends a read a rate limit refused
  once more after that wait, inside its 3 attempts, and that refusal fails nothing; a write is
  never resent. A reset past the budget is still refused without a request
  (`.github/actions/log-api-budget/rate-guard.mjs`,
  `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`).
- **shared, element 2.** A step that sets `API_BUDGET_HOLD=1` holds on a rate limit past the
  budget: the Node guard logs a `::notice::`, no `::error::`, and leaves the exit to the caller,
  and the gh wrapper prints a notice (`.github/actions/log-api-budget/api-budget.bash`). The call
  is still refused, so a gate that does not hold fails closed: the trusted-trigger check still
  answers `proceed=false`, and `ci-status` sets no hold. Holding is opt-in because a caller that
  reads a refusal as "nothing found" would otherwise pass it. A stop the job's stop file cannot take
  still fails the step. Each lane holds only once its workflow sets the variable.

A sixth part 2 change fixed this gap, with a test:

- **pr-refine, element 1.** `budgetedFetch` resends a rate-limited read the way `createGitHub`
  does (`retryServerErrors` with `resendLimited`): after the reset, inside the read's 3 attempts
  and the latch's 60 s budget, and the guard fails nothing for that refusal. It counts and logs
  each request sent, a resend included. A write still goes out once, and a refusal it does not
  resend still fails the step unless the step holds
  (`.github/scripts/pr-unblock/request-budget.mjs`).

A seventh part 2 change fixed work-resolve-issue's script gaps, each with a test. A hold keeps
`agent-ready` and posts no marker, so work-unblock's sweep starts the issue again, once per version
of the lane workflow files and then on the stranded backoff (`refireRefusal` in
`.github/scripts/work-unblock/label-unblocked.mjs`). The files are `report-outcome.mjs` and
`stop-routes.json` under `.github/scripts/work-resolve-issue/`.

- **work-resolve-issue, element 2: `--find-prior`.** A failed read, or an answer of the wrong shape,
  writes `proceed=false`, logs a `::notice::` and ends green, so the model does not run and no branch
  is reused or pruned. A bad issue number or an unreadable trusted list still fails the step. So does
  the issue-fields job's re-derive, whose failure withholds the run's branch claim.
- **work-resolve-issue, element 4: labeler read.** When who added `merge: human` cannot be read, a
  run that would open a PR opens none, posts nothing and ends green with a notice, so the branch
  stays unreported and the next run opens the PR from it. The label is never ignored, and the PR is
  no longer held for a person on no evidence. A stop that opens no PR reports as usual, and an
  unreadable trusted list still holds the PR.
- **work-resolve-issue, element 4: `retry-spent`.** Rows with `fault: true` are the lane's machinery
  failing: `outcome-unread`, `issue-file`, `scan-refused-fault` and `patch-apply-failed`. At the cap,
  a fault stop whose counted retries were all faults holds instead of failing the issue. Three cases
  still take the route: a run that left a branch of its own, which with no marker the next run would
  open a PR from whatever its checks said; `limits.stop-retries: 0`; and a stop the run itself caused,
  such as `outcome-invalid` or `patch-invalid`, which a retry can repeat for a reason in the issue.

An eighth part 2 change fixed work-unblock's listing gap, with tests
(`.github/scripts/work-unblock/label-unblocked.mjs`):

- **work-unblock, element 2.** A sweep whose closed-issue listing fails prints a `::notice::`, reads
  and writes nothing more and ends green. A held run looks like a full one in the run and step
  conclusions, so a sweep now logs `label-unblocked: read the closed-issue listing` once it has read
  that listing, and `sweepSince` starts its window from the last run only when that run's job log
  holds the line. Otherwise the window is the full `LOOKBACK_HOURS`, so the next sweep reads the
  closes the held one missed. That is one more read per sweep on the job token, and three holds or
  more in a row still lose closes older than the 3 hours, as red runs did. A failed
  listing of the deferred, open or `agent-ready` issues holds with a notice and the sweep goes on:
  each is read whole every sweep. A read or write that fails for one issue still ends the run red,
  and a rate limit past the guard's budget does too until the workflow sets `API_BUDGET_HOLD=1`.
  Either red run is left out of `sweepSince`, so the window stays back.

A ninth part 2 change fixed pr-refine's script gaps but one, with tests:

- **pr-refine, element 1.** Each `handoff-evidence.sh` wait is drawn at random from 0 to its cap
  (full jitter), for every caller. Reads go on at the last cap until the waits reach the caps' sum,
  so a listing that lags keeps its five minutes: at most 12 reads and about seven minutes. A
  `fix-docs` call stops after 3 failed reads; other callers keep 6, since pr-unblock starts a second
  model leg on a failed read. The head-SHA read is the workflow's (row below).
- **pr-refine, element 2.** A `fix-docs` or `fix-docs-subscription` read that fails holds: one
  `::notice::`, no output, exit 0, and a rate limit's annotation is a notice (the script sets
  `API_BUDGET_HOLD=1` for these two calls). The script scopes this by `CALLS`, since a workflow edit
  is out of this lane's reach and every other caller reads a red job or empty output its own way, so
  they still fail closed. A listing that lags ends as a notice through the two jobs'
  `HANDOFF_EVIDENCE_LAG=notice` in `pr-refine.yml`. A hold looks green, so a permanent fault such as
  a token that cannot read the jobs shows only as notices, and each PR's hold ends with element 3's
  count.
- **pr-refine, element 3.** `fix-docs-dispatch.mjs` no longer ends a PR on a red run with no check. It
  dispatches again until `limit-stops-per-head` runs went red or held, which bounds a broker refusal,
  since red names no cause. A held run ends green, so the dispatcher reads a green run's jobs: a leg
  that handed off, whose handoff job succeeded, with no next leg held. That is two more REST reads
  for each green run a candidate head has, until one ends the PR. An outage past that many runs still ends the PR.

Part 2 also fixed intake-triage's element 2 gap, with tests. A GitHub fault in `apply-verdict.mjs`
(a 5xx or 429, a rate-guard stop under the step's `API_BUDGET_HOLD` opt-in, or no answer), in
admission or anywhere else in the run, holds green with one `held:` notice (`closing`, `isFault`);
any other error, another 4xx, a forbidden missed edge and an unwritten reasons comment still fail. The lane has no
cron, but two hourly sweeps take a held issue up again: work-unblock's `readmitReady` runs
admission on a `status: ready` issue in no queue, and the triage sweep dispatches intake on one with
no `status:` label. The triage sweep reads a `held:` notice as it reads a failure annotation
(`triage-sweep.mjs` `classifyRun`), so a hold on a 5xx stays forgiven and a hold on any other
status counts. A hold also sets the apply-verdict job's `held` output, and `refine-select` runs only
when it is empty (`.github/workflows/intake-triage.yml`), so no refinement acts on a verdict whose
result is unknown.

Part 2 also fixed pr-verify's element 2 fault gap, with tests. When `resolve-pr.mjs` throws on a
GitHub fault (the same `isFault` test as `apply-verdict.mjs`, now shared from
`check-trusted-trigger.mjs`: a 5xx or 429, a rate-guard stop under the resolver steps'
`API_BUDGET_HOLD` opt-in, or no answer), the step logs one `held:` notice, writes `proceed=false`
and `reason=held`, and ends green, so nothing is judged (`closing`). Any other error, a 4xx
included, still fails, and so does a 200 whose completeness check fails. A held run concludes
success, so it is not lost. Its `Note the hold` step (`.github/workflows/pr-verify.yml`) marks it,
and the lost-run reconciler's next pass reads that job's annotations for the `held:` notice, as
`triage-sweep.mjs` `classifyRun` does, and re-runs the run once with the same record a lost lane
run gets (`reconcile.mjs` `faultHeld`). That happens only at attempt 1 and only while the status
page shows Actions operational, so outside an outage a held verdict is retried within about 30
minutes (the cron runs at minutes 4 and 34). A run held again at attempt 2 waits for the head's
next checks run. The reconciler lists pr-verify's succeeded runs from `FAULT_HELD_HOURS` back, or
from the last pass that read when that is earlier, since a pass idle through an outage reads
nothing, or from the oldest first attempt that pass saw still going, since a run's three jobs can
take about 17 hours. That pass already lists the runs still going, so this adds no read. Each run's jobs are read once, since a run with no hold is carried as settled, and at
most `FAULT_HELD_READS` a pass. At about 700 succeeded runs a day that is about 30 jobs reads an
hour, plus one or two listing reads a pass. Monitor signal 13 does not count these holds.

The holds above end green with only a notice, so the monitoring lane's signal 13 counts them: the
`retry-spent` fault hold, work-unblock's held listings, pr-refine's held `fix-docs` reads and
intake-triage's held verdicts (`apply-verdict.mjs` `closing`). A
lane with `monitor.lane-holds.threshold` held runs over `monitor.lane-holds.window-hours` in
`docs/conventions/pr-pipeline.yaml` raises the signal's issue, as signal 12 does for pr-merge
(`.github/scripts/maintenance-monitor-signals/signals.mjs` `laneHoldFindings`). It adds no stop
and no cap. intake-triage runs once per triaged issue, more green runs an hour than the monitor's
per-lane read cap (`collect.mjs` `LIMITS.holdRuns`), so its `HOLD_LANES` entry sets its own cap.

The shared element 2 opt-in is set step by step where the script holds green on a refused call:
work-unblock's label-unblocked step, the pr-unblock-dispatch dispatch step, pr-merge's candidate
listing and intake-triage's verdict step. Every other lane workflow says in its header why its steps
stay unset, and `callers.test.mjs` keeps the opt-in off workflow and job level and off every gate.

pr-refine's element 4 row is kept on evidence: the failure check `decide.mjs` posts for a run with
no verdict is the retry signal. `fix-docs-dispatch.mjs` `docsRunsEnded`
(`.github/scripts/pr-unblock/fix-docs-dispatch.mjs:180-186`) dispatches again after a red run but
counts a green run that did not hold on a handoff read as done, so a green hold that posts nothing
would stop the retry a red run gets. pr-unblock's `fix-ci-unreported` reads the same failure
(`.github/workflows/pr-unblock.yml`, `fix-ci-unreported`). A neutral check is no fix either, since
babysit counts neutral as passing. A broker failure on pr-refine does not reach `decide.mjs`: off
`pull_request` the report job posts no check on it (`.github/workflows/pr-run-activity-read.yml`,
`Choose the head the check is posted on`).

Two parts of the work-unblock rows stay open, for the reasons in the table:

- **Element 3.** The breaker records are not redundant state. The sweep counts them to back a
  kill-switch re-fire off past `limit-stops-per-issue`, which bounds re-fires that start a lane run
  and, at a mint, run the model again. `isRestart` reads them so the App's removal counts as a
  restart, and `backoff` uses them to keep a trip from raising another cause's wait.
- **Element 6.** Nothing in the `label-unblocked` job keeps an `etag` between runs, and a cache
  must not reach a job that mints. The closed listing's URL also changes every run with its
  `since`, so its `etag` could not match.

A later change fixed work-resolve-issue's workflow gaps, with tests. Its rows cite that change's
head, not `222d8023`.

- **work-resolve-issue, elements 2 and 3.** When a read the pause depends on fails or answers
  incomplete (the open listing, the merged count, the base config), `check-wip-cap.mjs` sets
  `capped` `true` and `pause_basis` `unknown` and logs one `WIP cap hold` notice. resolve-issue and
  its later calls start only on `capped` `false`, so a check that fails or sets nothing holds too,
  and pick-slot names that hold itself. The job ends green and work-unblock's sweep re-fires the
  issue as a WIP cap skip (`label-unblocked.mjs` `didNoWork`), with no per-issue bound. The cached
  last known pause is gone: the action's cache restore and save, its `save-state` input, and
  work-unblock's `wip-state` job, which only saved it. Monitor signal 13 does not count this hold:
  its work-resolve-issue entry reads only `report-outcome / run` (`signals.mjs` `HOLD_LANES`). So a
  permanent fault, such as a token that cannot search, holds every run and shows only as notices.

The other script rows below are still open.

| Lane | Element | Kind | File to change |
|---|---|---|---|
| work-unblock | 2 | script | `.github/scripts/work-unblock/label-unblocked.mjs` (a failed read for one issue still ends the run red); part 2 fixed the failed listings |
| work-unblock | 3 | script | `.github/scripts/work-unblock/label-unblocked.mjs` (dropping the breaker records needs another bound on kill-switch re-fires) |
| work-unblock | 3, 6 | workflow | `.github/workflows/work-unblock.yml` (sweep-kick, `queue: max`, somewhere to keep an `etag` between runs) |
| pr-refine | 4 | kept | `.github/actions/report-check-run/decide.mjs` keeps posting failure on no verdict: it is the retry signal `fix-docs-dispatch.mjs:180-186` and pr-unblock's `fix-ci-unreported` read (see above); part 2 fixed elements 1, 2 and 3 in `handoff-evidence.sh` and `fix-docs-dispatch.mjs` |
| pr-refine | 1, 2, 4 | workflow | `.github/workflows/pr-refine.yml`, `pr-run-activity-read.yml`, `pr-unblock-dispatch.yml` |
| pr-review, pr-review-security, pr-verify | 3 | kept | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs` keeps its one-time re-run record, the trust proof for an attempt 2 (`check-trusted-trigger.mjs` `verifyRecordedRerun`), and its status-page idle, a stop element 5 allows |
| pr-review, pr-review-security | 4 | larger | `plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py` (outside `.github/`) |
| pr-review, pr-review-security | 1, 2, 3, 4, 6 | workflow | `.github/workflows/pr-review-main.yml`, `pr-review-hosted.yml`, `pr-review-security-hosted.yml` |
| pr-verify | 2, 6 | script | `.github/scripts/pr-verify/resolve-pr.mjs` (a 200 whose completeness check fails still ends red), `check-trusted-trigger.mjs` (no `etag` on the re-run record poll); part 2 fixed the fault holds |
| pr-verify | 2, 3 | workflow | `.github/workflows/pr-verify.yml`; part 2 set `API_BUDGET_HOLD` on the resolver steps |
| pr-require-checks | 1, 2, 3, 4, 6 | workflow | `.github/workflows/pr-require-checks.yml` |
| pr-unblock | 3, 4 | script | `.github/scripts/pr-unblock/limit-stop.mjs`, `escalation-routes.json`; part 2 fixed `report-escalation.sh`'s comment resends, `request-budget.mjs`'s write resends and 6-minute waits, the lane's parallel reads, and the dispatchers' failed reads |
| pr-unblock | 6 | workflow | `.github/workflows/pr-unblock-dispatch.yml`, `pr-feedback-dispatch.yml` |
| pr-merge | 2, 6 | workflow | `.github/workflows/pr-merge.yml` (listing-full and rate-limit exits, cover-read dispatch, `queue: max`) |
| pr-merge | 2 | workflow | `.github/workflows/pr-merge.yml:1192`: hold green on a full listing and count it toward the monitor signal, so 1000 or more open pull requests reaches a person the way a held listing does |
| pr-merge | 3 | larger | the hub's lane breaker and kill switch, outside this repository |
| pr-merge | 4 | larger | `plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py` plus a `.github/workflows/pr-merge.yml` step (#12282) |
