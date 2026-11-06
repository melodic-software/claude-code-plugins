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
| 2 | met | `.github/scripts/work-resolve-issue/report-outcome.mjs:2190`, `.github/actions/check-wip-cap/check-wip-cap.mjs:398`, `.github/workflows/work-resolve-issue.yml:292` | `--find-prior` holds green on a failed read (see Remaining). A failed or incomplete open-PR listing or base config read sets `capped` `true` with a `WIP cap hold` notice (`check-wip-cap.mjs:404`); a failed merged count takes the configured `limits.wip-cap`, and resolve-issue starts only on `capped` `false`, so a check that sets nothing holds too, with pick-slot's notice (`work-resolve-issue.yml:246`). A rate limit past the guard's budget still prints the guard's `::error::` on the green job, since the check is a gate and sets no `API_BUDGET_HOLD`. |
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
| 2 | met | `.github/scripts/work-unblock/label-unblocked.mjs:487`, `.github/scripts/work-unblock/label-unblocked.mjs:674` (lines at this change, after `222d8023`) | A failed listing, or a GitHub fault on one issue's read, holds with a notice and the run exits 0. A sweep that held an issue keeps the next window back. A failed write, or a read that fails for another reason (another 4xx, an answer of the wrong shape), still ends the run red. |
| 3 | gap | `.github/workflows/work-unblock.yml:33`, `.github/scripts/work-unblock/label-unblocked.mjs:1350` | The workflow half is met: nothing re-arms the sweep, so the next cron or `workflow_run` sweep is the probe (see below). Breaker-trip records are kept for each issue: they bound model re-runs and gate no tick (still-open table, kept). |
| 4 | met | `.github/scripts/work-unblock/label-unblocked.mjs:194`, `.github/scripts/work-unblock/label-unblocked.mjs:82` | The lane lifts its own refs-hold `needs-human` once the PR merges or closes, and infrastructure re-fires never file `needs-human`. |
| 5 | met | `.github/workflows/work-unblock.yml:170` | The kill switch is the only pre-gate. No status-page step runs. |
| 6 | met | `.github/workflows/work-unblock.yml:134`, `.github/scripts/work-unblock/label-unblocked.mjs:674` | `label-unblocked` keeps the default single pending run (see below). An `etag` is not applicable: no job state carries one between runs, and the closed listing's URL changes every run with its `since`. The cron at minute 47 is fine. |

## pr-refine

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | `.github/workflows/pr-refine.yml:184`, `.github/workflows/pr-run-activity-read.yml:3827`, `.github/scripts/pr-unblock/read-pr-head.bash:32` (lines at the later change below) | Part 2 gave `handoff-evidence.sh` full-jitter waits. Both PR head reads, fix-docs-head's and the read runner's report job's, read a transient fault once more after a full-jitter wait and never a rate limit. The tip step's `git ls-remote` is shared by every workflow (see Remaining). |
| 2 | gap | `.github/workflows/pr-refine.yml:184`, `.github/workflows/pr-refine.yml:223`, `.github/scripts/pr-unblock/fix-docs-dispatch.mjs:197` (lines at the later change below) | A head fix-docs-head cannot read holds green with a notice and starts nothing, and the dispatcher counts the held run toward `limit-stops-per-head`. Part 2 holds the `fix-docs` handoff reads. What is left is a script: a failed `lane-hold.mjs` read still ends fix-docs-head red (see Remaining). |
| 3 | gap | `.github/scripts/pr-unblock/fix-docs-dispatch.mjs:178`, `.github/scripts/pr-unblock/fix-docs-dispatch.mjs:258` | The dispatcher counts any completed run, including a red outage run, as done, so the next tick never re-dispatches it. |
| 4 | met | `.github/actions/report-check-run/decide.mjs:105`, `.github/workflows/pr-run-activity-read.yml:3880` (lines at the later change below) | `decide.mjs` still posts `failure` for a run with no verdict, kept on evidence as the retry signal (see Remaining). No workflow step files or demotes on an incomplete read: with `post-decline: false` the report job posts no check on a run whose run job set no head, and fix-docs-head's hold files nothing. |
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
| 1 | gap | `.github/workflows/pr-review-main.yml:188`, `.github/workflows/pr-review-main.yml:352`, `.github/workflows/pr-review-main.yml:262` | Every file-list read now goes through `retry_call --read` (`.github/scripts/pr-merge/retry-call.bash`): 3 reads at most, full jitter, a rate stop waited out within 60 s (see Remaining). The shared client sends up to 3 attempts with full jitter. Still open: the judged-head pre-filter's reads are sent once, and a failed one runs the review (fail open, so nothing is lost but a review's cost), and the hosted review's own reads are in ci-workflows' `pr-review-cli.yml` (`.github/workflows/pr-review-hosted.yml:246`). |
| 2 | gap | `.github/workflows/pr-review-main.yml:352`, `.github/workflows/pr-review-main.yml:1325`, `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:333` | A list unread after 3 reads, or "no verdict", still ends red, on evidence: that red is what the reconciler's kept one-time re-run reads (`RECORDED_LANES`, a run lost before or during its review), and the merge gate binds a verdict only from a run that completed with success (`babysit_review_evidence.py:507` `_main_bound`). A green hold needs the reconciler to read it, as `faultHeld` does for pr-verify (still-open table). |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:333`, `.github/workflows/pr-review-hosted.yml:214` | The rest is met; the one re-arm is kept (still-open table). Recovery is the reconciler's next pass: a recorded one-time re-run, idle while the status page lists an outage (element 5 allows that stop). The one-time record is a re-arm the owner kept: it is the trust proof for an attempt 2 (`check-trusted-trigger.mjs` `verifyRecordedRerun`). No other re-arm runs: the key-credit probing marker (`pr-review-main.yml` `review-handoffs-credit`) gates which credential runs, not when a review restarts. |
| 4 | gap | `.github/workflows/pr-review-main.yml:3051`, `plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py:507` | A later clean review never clears a CRITICAL check run, by design: the merge gate keeps the most CRITICAL findings any review of the tree reported, so a re-run cannot clear a security hold. Changing that is the merge gate's (still-open table, larger). |
| 5 | met | `.github/workflows/pr-review-hosted.yml:214`, `.github/workflows/pr-review-main.yml:602` | `check-upstream-status` stops the review with exit 1. That is a stop, and the page starts nothing. The red stays: the reconciler re-runs on that failed step (`reconcile.mjs:250` `UPSTREAM_STOP_STEP`) and the merge gate binds the re-run on its error (`babysit_review_evidence.py:262` `UPSTREAM_STOP_RE`). |
| 6 | gap | `.github/workflows/pr-review-main.yml:80`, `.github/workflows/pr-review-main.yml:820` | Concurrency per PR and head is fine, and reads are serial within a job. The two lanes' parallel legs each read the PR's trusted text (`select-trusted-text`); reading it once and passing it on changes what the model reads, so it stays open (still-open table). A later leg's own gate and file-list read are its trust check on a fresh VM, so they stay. |

## pr-review-security

The lane runs from `.github/workflows/pr-review-security-hosted.yml` and the
`claude-security-review` row of `.github/workflows/pr-review-main.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/workflows/pr-review-main.yml:188`, `.github/workflows/pr-review-main.yml:352`, `.github/workflows/pr-review-security-hosted.yml:251` | It shares pr-review's code, so its file-list reads retry and the same reads stay open. |
| 2 | gap | `.github/workflows/pr-review-main.yml:352`, `.github/workflows/pr-review-main.yml:1325` | A list still unread, or "no verdict", makes the run red, the signal the reconciler's kept re-run reads, as for pr-review. |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:333`, `.github/workflows/pr-review-security-hosted.yml:219` | As for pr-review, the rest is met and the re-arm is kept. Resume is the reconciler's next pass and its one-time recorded re-run, a re-arm the owner kept as attempt 2's trust proof, as for pr-review. |
| 4 | gap | `.github/workflows/pr-review-main.yml:3051`, `plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py:507` | A later complete read never closes a filed CRITICAL count, by the merge gate's design, as for pr-review. |
| 5 | met | `.github/workflows/pr-review-security-hosted.yml:219`, `.github/workflows/pr-review-main.yml:602` | The status page gates the run and turns it red. That is a stop, and the page starts nothing; the red is what the reconciler and the merge gate read, as for pr-review. |
| 6 | gap | `.github/workflows/pr-review-main.yml:80`, `.github/workflows/pr-review-main.yml:820` | As for pr-review: the parallel legs each read the trusted text. |

## pr-verify

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:201`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:215` | The shared client sends up to 3 attempts with full jitter, and the rate latch waits out a reset within 60 s, then refuses (a notice under the hold opt-in). Writes go out once. |
| 2 | gap | `.github/scripts/pr-verify/resolve-pr.mjs:1185`, `.github/workflows/pr-verify.yml:209`, `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs:663` (lines at the later change below) | A fault or a 200 whose completeness check fails (`incomplete`: a list shorter than its count, a missing field) holds the resolver green with the `held:` notice and `reason=held`, and `Note the hold` marks the run. A malformed input, a GraphQL error other than `NOT_FOUND`, a list past what the query reads (`shortList`) and the page cap stay red. The workflow's other reads still end red, kept so the reconciler re-runs the run (see Remaining). A read fault in the trigger gate ends the run green with no notice and no re-run. |
| 3 | gap | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:702`, `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:750`, `.github/workflows/pr-verify.yml:168` (lines at the later change below) | A red run whose verdict write never started, the kill switch's stop included, and a held green run are each re-run once by the reconciler, from an attempt record. That is a re-arm, which the owner kept as attempt 2's trust proof, and it is the lane's whole element 3. |
| 4 | met | `.github/workflows/pr-verify.yml:51`, `.github/scripts/pr-verify/resolve-pr.mjs:46` | A FAIL needs a complete judgment, and a later pass supersedes it. |
| 5 | met | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs:128` | The reconciler idles while the status page shows Actions as anything but operational, and re-runs only once it is and its own reads succeed. The page stops the resume path but starts nothing. |
| 6 | met | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs` `verifyRecordedRerun` (`readListing`), `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs` `createGitHub` (`ETAG`) | The re-run record listing's re-read sends the page's `etag` (`If-None-Match`), and a 304 gives back the body it came with. Concurrency (`.github/workflows/pr-verify.yml:102`) and serial reads are fine. |

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
| 3 | gap | `.github/scripts/pr-unblock/dispatch.mjs:229`, `.github/scripts/pr-unblock/limit-stop.mjs:21` | Failed runs use up a cap for each head that blocks re-dispatch until a new push. That is a stored breaker. Part 2 took out a run whose model never started (`limit-stop.mjs` `faultStop`: class `install-failed` or `sandbox-unavailable`): it neither handles the head nor counts, so the next tick dispatches again. A `no-credential` stop still counts, since a missing secret fails every tick the way `auth` does, and so does an `overloaded`, `no-outcome`, `rate-limit` or `auth` stop or a red run with no record, because a model turn may have run, the bound the work-unblock note keeps. |
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
  each is read whole every sweep. A read for one issue that meets a GitHub fault holds that issue
  with a notice, and the rest of the sweep goes on. Only a failed write, or a read that fails for
  another reason, ends the run red. A held run prints a line that `sweepSince` reads, and a red run
  is left out of it, so either way the window stays back.

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
and `reason=held`, and ends green, so nothing is judged (`closing`). A 200 a re-read could
return whole (a missing node or list, or fewer nodes than a count the page could hold) holds the
same way (`incomplete`). A 200 past what the query reads (more than `comments(first: 100)`, a jobs
page or the closing issues hold, another page) still fails, since every re-read meets the same
limit and a hold would leave the head unverified with no signal; so does any other error, a 4xx
included. A held run concludes
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
`retry-spent` fault hold, work-resolve-issue's `WIP cap hold`, work-unblock's held listings and issue reads, pr-refine's held `fix-docs` reads and unread heads, and
intake-triage's held verdicts (`apply-verdict.mjs` `closing`). A
lane with `monitor.lane-holds.threshold` held runs over `monitor.lane-holds.window-hours` in
`docs/conventions/pr-pipeline.yaml` raises the signal's issue, as signal 12 does for pr-merge
(`.github/scripts/maintenance-monitor-signals/signals.mjs` `laneHoldFindings`). It adds no stop
and no cap. intake-triage runs once per triaged issue, more green runs an hour than the monitor's
per-lane read cap (`collect.mjs` `LIMITS.holdRuns`), so its `HOLD_LANES` entry sets its own cap.
work-unblock's sweep also runs more often than that cap, a mean of 6.9 green runs an hour, so its
entry sets a cap of 20.

The shared element 2 opt-in is set step by step where the script holds green on a refused call:
work-unblock's label-unblocked step, the pr-unblock-dispatch dispatch step, pr-merge's candidate
listing and intake-triage's verdict step. Every other lane workflow says in its header why its steps
stay unset, and `callers.test.mjs` keeps the opt-in off workflow and job level and off every gate.

pr-refine's element 4 row is kept on evidence: the failure check `decide.mjs` posts for a run with
no verdict is the retry signal. `fix-docs-dispatch.mjs` `docsRunsEnded`
(`.github/scripts/pr-unblock/fix-docs-dispatch.mjs:188-199`, lines at the later change below)
dispatches again after a red run but counts a green run that did not hold on a handoff read or an
unread head as done, so a green hold that posts nothing
would stop the retry a red run gets. pr-unblock's `fix-ci-unreported` reads the same failure
(`.github/workflows/pr-unblock.yml`, `fix-ci-unreported`). A neutral check is no fix either, since
babysit counts neutral as passing. A broker failure on pr-refine does not reach `decide.mjs`: off
`pull_request` the report job posts no check on it (`.github/workflows/pr-run-activity-read.yml`,
`Choose the head the check is posted on`).

work-unblock's element 3 script row is kept on evidence:

- **Element 3.** The breaker records are not redundant state, and they are no breaker that gates
  the probe: they are the lane's own comments, read from GitHub on every sweep, and no tick waits
  on them. Replacing them with another count read each run (refused run logs, or the App's
  agent-ready re-adds) costs more calls or merges causes into one bound. The sweep counts them to back a
  kill-switch re-fire off past `limit-stops-per-issue`, which bounds re-fires that start a lane run
  and, at a mint, run the model again. `isRestart` reads them so the App's removal counts as a
  restart, and `backoff` uses them to keep a trip from raising another cause's wait.

A later change closed work-unblock's workflow row. Its element 3 and 6 rows cite that change's
head, not `222d8023`.

- **work-unblock, element 3.** The marker-issue sweep-kick is gone: closing the issue labeled
  `work-unblock-sweep` now runs the close path like any close, and the sweep runs only on the cron
  and on `workflow_run` (`.github/scripts/work-unblock/label-unblocked.mjs:2367`). Nothing was
  stranded. The sweep's window counts only successful scheduled runs
  (`label-unblocked.mjs:626-632`), so a kick never moved it, and a broker-check trip re-fires on the
  next sweep with no wait (`label-unblocked.mjs:1879`), while a mint trip waited
  `limits.reset-clamp-min` with or without a kick.
- **work-unblock, element 6.** `queue: max` is gone from `label-unblocked`
  (`.github/workflows/work-unblock.yml:134`), so a newer run replaces the waiting one. No waiting
  run carries work only it does: a sweep reads the whole state, and a close run's work
  (`labelUnblocked`, `closeSplitParents`, `stripClosed`) is repeated by the next sweep for every
  issue its closed-issue window lists (`label-unblocked.mjs:1267-1276`, `:2197`). A replaced sweep's
  admissions and re-fires wait for the next one, and a replaced scheduled sweep only widens the next
  window, up to `LOOKBACK_HOURS`. An `etag` is not applicable: nothing in the job keeps one between
  runs, a cache must not reach a job that mints, and the closed listing's URL changes every run
  with its `since` (`label-unblocked.mjs:674`).

A later change fixed work-resolve-issue's workflow gaps, with tests. Its rows cite that change's
head, not `222d8023`.

- **work-resolve-issue, elements 2 and 3.** When a read the pause depends on fails or answers
  incomplete (the open listing, the base config), `check-wip-cap.mjs` sets
  `capped` `true` and `pause_basis` `unknown` and logs one `WIP cap hold` notice. resolve-issue and
  its later calls start only on `capped` `false`, so a check that fails or sets nothing holds too,
  and pick-slot names that hold itself. The job ends green and work-unblock's sweep re-fires the
  issue as a WIP cap skip (`label-unblocked.mjs` `didNoWork`), with no per-issue bound. The cached
  last known pause is gone: the action's cache restore and save, its `save-state` input, and
  work-unblock's `wip-state` job, which only saved it. Monitor signal 13 counts this hold: its
  work-resolve-issue entry reads `pick-slot` too (`signals.mjs` `HOLD_LANES`), so a permanent fault,
  such as a token that cannot search, raises the signal's issue.

A later change fixed pr-refine's workflow gaps, with tests. Its pr-refine rows cite that change's
head. `pr-unblock-dispatch.yml` needed nothing: its dispatch step holds a refused call
(`API_BUDGET_HOLD` at `:257`), a run listing or jobs read that fails warns and dispatches nothing
(`fix-docs-dispatch.mjs:273`, `:283`), and its trigger check is a gate, which stays red.

- **pr-refine, element 1.** The read runner's report job reads the PR head through
  `read-pr-head.bash`, as fix-docs-head does: a transient fault is read once more, never a rate
  limit, and a read that still fails warns and leaves the head empty, as before. The helper's wait
  before that second read is now drawn from 0 to 10 s (full jitter), for pr-unblock's callers too.
- **pr-refine, element 2.** When fix-docs-head cannot read the head (a failed read, a rate limit
  past the guard's budget under the step's `API_BUDGET_HOLD`, or an answer with no SHA), the step
  logs a notice, sets `unread`, and ends green. Nothing after it starts but `fix-docs-head-held`,
  a job with no grant whose `PR head hold` notice monitor signal 13 counts (`signals.mjs`
  `HOLD_LANES`). `fix-docs-dispatch.mjs` `heldHead` reads that job's conclusion, which no head code
  can write, and counts the run as it counts a handoff hold, so the PR is dispatched again until
  `limit-stops-per-head` runs went red or held. A person's hold also ends the run green with
  fix-docs skipped, but has no such job, so it still ends the PR. A bad `pr-number` and a failed
  `lane-hold.mjs` read still end red.
- **pr-refine, element 4.** Nothing to change: no workflow step files or demotes on an incomplete
  read. A cancelled run whose report-time head read fails still posts `failure` on the gated head,
  but the cancel itself (a timeout, since `cancel-in-progress` is false) is the evidence, and for
  fix-docs any check on the PR's last 50 commits ends the PR either way (`historyHasRun`).

A later change fixed pr-review's and pr-review-security's file-list reads, with tests. Their rows
cite that change's head, not `222d8023`.

- **pr-review and pr-review-security, element 1.** The trigger job's file-list read and each leg's
  select read go through `retry_call --read 60` (`.github/scripts/pr-merge/retry-call.bash`): up to
  3 reads, a capped backoff with full jitter, and a rate stop waited out within 60 s of waits. A
  trigger read still unread leaves no result and the gate runs, as before; a select read still
  unread ends the step red, the failure the reconciler's kept one-time re-run reads. Element 2 is
  kept red on that evidence (`reconcile.mjs:25-28`: a lane run that failed before its verdict write
  is re-run once), element 3's one re-arm is kept, and element 5 is met as it stands (still-open
  table).

A later change reviewed pr-verify's workflow row. Its pr-verify rows 2 and 3 cite that change's head.
Only the workflow header's account of the resolver changed: no step was made to hold.

- **pr-verify, element 2.** Every read before the verdict write other than the resolver's still
  ends red: main's tip (`.github/workflows/pr-verify.yml:137`), the checkout (`:147`), the trusted
  PR text (`:245`), the diff fetch (`:264`), the upstream run's jobs (`:303`) and the model config
  (`:367`), with the same steps in the two later jobs. That is kept. The reconciler re-runs a red
  first attempt whose verdict write never started (`reconcile.mjs:236`, `holdReason` at `:702`),
  and it re-runs a green one only when the job ran `Note the hold` with a `held:` notice
  (`faultHeld`, `reconcile.mjs:750`). A step held green any other way would end that re-run unseen.
  After the write starts, a red run is held for a person, so a head is never judged twice
  (`reconcile.mjs:738`). wake-pr-merge already holds: a failed read dispatches anyway and a failed
  dispatch warns, and pr-merge's schedule arms the PR (`pr-verify.yml:5804`). The trigger gate turns
  a read fault into `proceed=false` with reason `no-pr` (`check-trusted-trigger.mjs:663`, `:687`),
  the same reason as a run with no PR, so the job skips every later step and ends green with no
  notice and no re-run. The workflow cannot tell that fault from a real refusal, so the
  gate's script row below records it.
- **pr-verify, element 3.** It is the kept re-run alone. The next pr-require-checks completion is
  the only other start, and a run held again at attempt 2 waits for it.

The other script rows below are still open.

| Lane | Element | Kind | File to change |
|---|---|---|---|
| work-unblock | 3 | kept | `.github/scripts/work-unblock/label-unblocked.mjs` keeps its breaker-trip records: they are the lane's own comments, read from GitHub each run, and bound kill-switch re-fires that start a lane run or a model turn (see above); they gate no cron tick, so the next sweep is still the probe |
| pr-refine | 4 | kept | `.github/actions/report-check-run/decide.mjs` keeps posting failure on no verdict: it is the retry signal `fix-docs-dispatch.mjs:188-199` and pr-unblock's `fix-ci-unreported` read (see above); part 2 fixed elements 1, 2 and 3 in `handoff-evidence.sh` and `fix-docs-dispatch.mjs`, and the later pr-refine change above the workflow's elements 1, 2 and 4 |
| pr-refine | 2 | script | `.github/scripts/pr-unblock/lane-hold.mjs` (a failed label or timeline read ends fix-docs-head red, a run the dispatcher counts; pr-unblock's `resolve-conflicts-select` shares the script) |
| shared | 1 | workflow | every workflow's `Resolve main's tip` step: its one `git ls-remote` is never retried, and `callers.test.mjs` pins the step's text across more than 70 jobs (`TIP_RUN`) |
| pr-review, pr-review-security, pr-verify | 3 | kept | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs` keeps its one-time re-run record, the trust proof for an attempt 2 (`check-trusted-trigger.mjs` `verifyRecordedRerun`), and its status-page idle, a stop element 5 allows |
| pr-review, pr-review-security | 4 | larger | `plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py` (outside `.github/`) |
| pr-review, pr-review-security | 2 | larger | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`: read a pr-review-main hold, as `faultHeld` reads pr-verify's, before `pr-review-main.yml` holds an unread file list or a run with no verdict green; until then that red is the kept re-run's signal |
| pr-review, pr-review-security | 1, 6 | workflow | `.github/workflows/pr-review-main.yml`: retry the judged-head pre-filter's reads, and read the trusted PR text once per run for both lanes, which changes what the model reads |
| pr-review, pr-review-security | 1, 2, 6 | larger | the hosted review's own reads, in `melodic-software/ci-workflows` `pr-review-cli.yml` |
| pr-verify | 2 | kept | `.github/workflows/pr-verify.yml` keeps its non-resolver reads red: the reconciler re-runs a red run whose verdict write never started, and sees a green hold only through `Note the hold` and a `held:` notice (`reconcile.mjs` `faultHeld`) (see above) |
| pr-verify | 2 | script | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs` (a read fault stops with `no-pr`, the reason a run with no PR gets, so pr-verify ends green with no notice and no re-run; a separate fault reason the workflow can mark with `Note the hold`, plus a pr-verify entry in `signals.mjs` `HOLD_LANES`, would make it a counted hold) |
| pr-require-checks | 1, 2, 3, 4, 6 | workflow | `.github/workflows/pr-require-checks.yml` |
| pr-unblock | 3, 4 | script | `.github/scripts/pr-unblock/limit-stop.mjs` (a stop where a model turn may have run still counts toward the cap), `escalation-routes.json` (`feedback-publish-failed` still files a failing status: withholding it strands the head, since only a workflow-modified refusal is sent again, `feedback-dispatch.mjs` `sweepRefused`); part 2 fixed `report-escalation.sh`'s comment resends, `request-budget.mjs`'s write resends and 6-minute waits, the lane's parallel reads, the dispatchers' failed reads, and the cap's count of fault stops whose model never started |
| pr-unblock | 6 | workflow | `.github/workflows/pr-unblock-dispatch.yml`, `pr-feedback-dispatch.yml` |
| pr-merge | 2, 6 | workflow | `.github/workflows/pr-merge.yml` (listing-full and rate-limit exits, cover-read dispatch, `queue: max`) |
| pr-merge | 2 | workflow | `.github/workflows/pr-merge.yml:1192`: hold green on a full listing and count it toward the monitor signal, so 1000 or more open pull requests reaches a person the way a held listing does |
| pr-merge | 3 | larger | the hub's lane breaker and kill switch, outside this repository |
| pr-merge | 4 | larger | `plugins/source-control/skills/babysit-prs/scripts/babysit_postmerge.py` plus a `.github/workflows/pr-merge.yml` step (#12282) |
