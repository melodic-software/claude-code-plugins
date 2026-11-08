# Lane audit against the outage pause-and-resume posture

This audit checks each of the 14 lanes in `.github/actions/resolve-config/lane-rules.json` against
the six elements of the outage posture (#9205, owner decision Q677). It is slice 3 of #9205,
and issue #12291 is part 1 of 2 of #12283. Each `path:line` links to the commit it describes, by full SHA: `222d8023` for the first audit's rows, and for a later row the commit its section names or the change that wrote the citation. Line numbers
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
([`.github/scripts/pr-unblock/request-budget.mjs`:36](https://github.com/melodic-software/claude-code-plugins/blob/ab3b3a2e03fd9a6fab6df6c708196c75cea4f71f/.github/scripts/pr-unblock/request-budget.mjs#L36)) use the retry at
[`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`:201](https://github.com/melodic-software/claude-code-plugins/blob/ab3b3a2e03fd9a6fab6df6c708196c75cea4f71f/.github/actions/check-trusted-trigger/check-trusted-trigger.mjs#L201), which sends a read up to 3
times, after waits of up to 2 and 4 s with full jitter. The rate guard waits out a rate-limit stop
that resets within 60 s ([`.github/actions/log-api-budget/rate-guard.mjs`:580](https://github.com/melodic-software/claude-code-plugins/blob/ab3b3a2e03fd9a6fab6df6c708196c75cea4f71f/.github/actions/log-api-budget/rate-guard.mjs#L580)) and refuses a call
past that ([`.github/actions/log-api-budget/rate-guard.mjs`:590](https://github.com/melodic-software/claude-code-plugins/blob/ab3b3a2e03fd9a6fab6df6c708196c75cea4f71f/.github/actions/log-api-budget/rate-guard.mjs#L590)), with a notice instead of an error
under `API_BUDGET_HOLD=1`.
Part 2 changed both (see Remaining). The listing helper [`.github/scripts/pr-merge/retry-call.bash`:39](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-merge/retry-call.bash#L39) meets
element 1, but only pr-merge uses it. Every workflow's `Resolve main's tip` step tries its
`git ls-remote` up to 3 times, after waits of up to 2 and 4 s with full jitter, and fails red when
no try yields a SHA ([`.github/workflows/pr-verify.yml`:144](https://github.com/melodic-software/claude-code-plugins/blob/d9098daa3d43f08b328fd46e340abb848e0591fa/.github/workflows/pr-verify.yml#L144)).

## work-resolve-issue

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/scripts/work-resolve-issue/retry-fetch.mjs`:45-51](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-resolve-issue/retry-fetch.mjs#L45-L51), [`.github/scripts/work-resolve-issue/report-outcome.mjs`:2692-2705](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-resolve-issue/report-outcome.mjs#L2692-L2705) | A read refused on a rate limit is sent again within its 3 attempts only after `retry-after`, else the reset, else 60 s, and a wait past 60 s per client is not taken. A PR create that failed on the network is read back with `findOpen` and never sent again: when no PR reads back, the run fails and a rerun reuses or opens it. |
| 2 | met | [`.github/scripts/work-resolve-issue/report-outcome.mjs`:2190](https://github.com/melodic-software/claude-code-plugins/blob/1150626669f6db966eff8b83611d0848bd8dd1a9/.github/scripts/work-resolve-issue/report-outcome.mjs#L2190), [`.github/actions/check-wip-cap/check-wip-cap.mjs`:398](https://github.com/melodic-software/claude-code-plugins/blob/6139bb3916ebc573b237758c6519f99970d0dcc5/.github/actions/check-wip-cap/check-wip-cap.mjs#L398), [`.github/workflows/work-resolve-issue.yml`:292](https://github.com/melodic-software/claude-code-plugins/blob/41dc60c983ada772bbd823ab1115a4504d608f7a/.github/workflows/work-resolve-issue.yml#L292) | `--find-prior` holds green on a failed read (see Remaining). A failed or incomplete open-PR listing or base config read sets `capped` `true` with a `WIP cap hold` notice (`check-wip-cap.mjs:404`); a failed merged count takes the configured `limits.wip-cap`, and resolve-issue starts only on `capped` `false`, so a check that sets nothing holds too, with pick-slot's notice (`work-resolve-issue.yml:246`). A rate limit past the guard's budget still prints the guard's `::error::` on the green job, since the check is a gate and sets no `API_BUDGET_HOLD`. |
| 3 | met | [`.github/actions/check-wip-cap/action.yml`:64](https://github.com/melodic-software/claude-code-plugins/blob/41dc60c983ada772bbd823ab1115a4504d608f7a/.github/actions/check-wip-cap/action.yml#L64), [`.github/workflows/work-unblock.yml`:105](https://github.com/melodic-software/claude-code-plugins/blob/1150626669f6db966eff8b83611d0848bd8dd1a9/.github/workflows/work-unblock.yml#L105) | No cache is restored or saved, so no earlier pause decides. A held run reads as a WIP cap skip, and work-unblock's sweep (cron and `workflow_run`) re-fires it, whose run reads again. |
| 4 | met | [`.github/scripts/work-resolve-issue/report-outcome.mjs`:2542-2546](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-resolve-issue/report-outcome.mjs#L2542-L2546), [`.github/scripts/work-resolve-issue/report-outcome.mjs`:2653](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-resolve-issue/report-outcome.mjs#L2653), [`.github/scripts/work-resolve-issue/report-outcome.mjs`:1973](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-resolve-issue/report-outcome.mjs#L1973), [`.github/scripts/work-resolve-issue/stop-routes.json`:2](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-resolve-issue/stop-routes.json#L2) | A labeler that cannot be read is `null`, so a run that would open a PR opens none and ends green with a notice; the next run opens it. Past its cap a `fault: true` stop whose counted retries were all faults holds instead of taking `retry-spent`'s route (`spentOnFaults`), unless the run left a branch of its own or `limits.stop-retries` is 0. |
| 5 | met | [`.github/workflows/work-resolve-issue.yml`:66](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/work-resolve-issue.yml#L66), [`.github/workflows/work-resolve-issue.yml`:129](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/work-resolve-issue.yml#L129) | The status-page result (`degraded`) gates the admit job's `proceed` output. That is a stop, and the page starts nothing. |
| 6 | met | [`.github/scripts/lib/handoff-evidence.sh`:163](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/lib/handoff-evidence.sh#L163), [`.github/scripts/lib/handoff-evidence.sh`:170](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/lib/handoff-evidence.sh#L170), [`.github/workflows/work-resolve-issue.yml`:412](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/workflows/work-resolve-issue.yml#L412) | The job-listing poll sends each page's `etag` as `If-None-Match` on every read after the first, and a 304 reuses the page it already read. One pending run per issue (`:55`) and the slot cap (`:216`) are fine. |

## intake-triage

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/scripts/intake-triage/apply-verdict.mjs`:926](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/intake-triage/apply-verdict.mjs#L926), [`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`:258-298](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/actions/check-trusted-trigger/check-trusted-trigger.mjs#L258-L298), [`.github/actions/log-api-budget/rate-guard.mjs`:577](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/actions/log-api-budget/rate-guard.mjs#L577) | The shared client sends a read at most 3 times with full jitter, and the rate latch waits out a reset within 60 s before the resend, then refuses past it (a notice under the hold opt-in). |
| 2 | met | [`.github/scripts/intake-triage/apply-verdict.mjs`:803-826](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/intake-triage/apply-verdict.mjs#L803-L826), [`.github/scripts/intake-triage/apply-verdict.mjs`:683](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/intake-triage/apply-verdict.mjs#L683), [`.github/workflows/intake-triage.yml`:588](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/workflows/intake-triage.yml#L588) | A GitHub fault (`isFault`), in admission or anywhere else in the run, holds green with one `held:` notice and sets the job's `held` output; any other error still fails. The step opts in with `API_BUDGET_HOLD`. |
| 3 | not applicable | [`.github/workflows/intake-triage.yml`:33](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/intake-triage.yml#L33) | The lane triggers only on `issues` and `workflow_dispatch`, with no cron and no stored breaker. |
| 4 | met | [`.github/scripts/intake-triage/admit.mjs`:2513-2516](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/intake-triage/admit.mjs#L2513-L2516), [`.github/workflows/intake-triage.yml`:332](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/workflows/intake-triage.yml#L332) | A failed visibility read throws, like the other admission reads, so it no longer counts the repository as private; only a read of `public` skips the `cost_private` charge words. The lane lifts its own holds. |
| 5 | met | [`.github/workflows/intake-triage.yml`:210](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/intake-triage.yml#L210), [`.github/workflows/intake-triage.yml`:248](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/intake-triage.yml#L248) | `upstream-degraded` blocks the triage job. That is a stop, and the page starts nothing. |
| 6 | met | [`.github/workflows/intake-triage.yml`:255](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/intake-triage.yml#L255), [`.github/workflows/intake-triage.yml`:595](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/intake-triage.yml#L595) | There is one pending run per issue, the optional refine step runs only after apply-verdict succeeds, and reads are sequential. |

## work-unblock

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/scripts/work-unblock/label-unblocked.mjs`:2397](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/work-unblock/label-unblocked.mjs#L2397), [`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`:258-298](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/actions/check-trusted-trigger/check-trusted-trigger.mjs#L258-L298), [`.github/actions/log-api-budget/rate-guard.mjs`:577](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/actions/log-api-budget/rate-guard.mjs#L577) | The shared client sends a read at most 3 times with full jitter, and the rate latch waits out a reset within 60 s before the resend; a longer one fails the step (a notice under the hold opt-in, [`.github/workflows/work-unblock.yml`:261](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/workflows/work-unblock.yml#L261)). |
| 2 | met | [`.github/scripts/work-unblock/label-unblocked.mjs`:487](https://github.com/melodic-software/claude-code-plugins/blob/3745a08ba02f4fa2b8e7751b1bc42ea2f6446716/.github/scripts/work-unblock/label-unblocked.mjs#L487), [`.github/scripts/work-unblock/label-unblocked.mjs`:674](https://github.com/melodic-software/claude-code-plugins/blob/3745a08ba02f4fa2b8e7751b1bc42ea2f6446716/.github/scripts/work-unblock/label-unblocked.mjs#L674) (lines at this change, after `222d8023`) | A failed listing, or a GitHub fault on one issue's read, holds with a notice and the run exits 0. A sweep that held an issue keeps the next window back. A failed write, or a read that fails for another reason (another 4xx, an answer of the wrong shape), still ends the run red. |
| 3 | gap | [`.github/workflows/work-unblock.yml`:33](https://github.com/melodic-software/claude-code-plugins/blob/90e8a09862a21534957c59196df4d25f733df8e5/.github/workflows/work-unblock.yml#L33), [`.github/scripts/work-unblock/label-unblocked.mjs`:1350](https://github.com/melodic-software/claude-code-plugins/blob/90e8a09862a21534957c59196df4d25f733df8e5/.github/scripts/work-unblock/label-unblocked.mjs#L1350) | The workflow half is met: nothing re-arms the sweep, so the next cron or `workflow_run` sweep is the probe (see below). Breaker-trip records are kept for each issue: they bound model re-runs and gate no tick (still-open table, kept). |
| 4 | met | [`.github/scripts/work-unblock/label-unblocked.mjs`:194](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/work-unblock/label-unblocked.mjs#L194), [`.github/scripts/work-unblock/label-unblocked.mjs`:82](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/work-unblock/label-unblocked.mjs#L82) | The lane lifts its own refs-hold `needs-human` once the PR merges or closes, and infrastructure re-fires never file `needs-human`. |
| 5 | met | [`.github/workflows/work-unblock.yml`:170](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/work-unblock.yml#L170) | The kill switch is the only pre-gate. No status-page step runs. |
| 6 | met | [`.github/workflows/work-unblock.yml`:134](https://github.com/melodic-software/claude-code-plugins/blob/90e8a09862a21534957c59196df4d25f733df8e5/.github/workflows/work-unblock.yml#L134), [`.github/scripts/work-unblock/label-unblocked.mjs`:674](https://github.com/melodic-software/claude-code-plugins/blob/90e8a09862a21534957c59196df4d25f733df8e5/.github/scripts/work-unblock/label-unblocked.mjs#L674) | `label-unblocked` keeps the default single pending run (see below). An `etag` is not applicable: no job state carries one between runs, and the closed listing's URL changes every run with its `since`. The cron at minute 47 is fine. |

## pr-refine

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/workflows/pr-refine.yml`:184](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/workflows/pr-refine.yml#L184), [`.github/workflows/pr-run-activity-read.yml`:3827](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/workflows/pr-run-activity-read.yml#L3827), [`.github/scripts/pr-unblock/read-pr-head.bash`:32](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/scripts/pr-unblock/read-pr-head.bash#L32) (lines at the later change below) | Part 2 gave `handoff-evidence.sh` full-jitter waits. Both PR head reads, fix-docs-head's and the read runner's report job's, read a transient fault once more after a full-jitter wait and never a rate limit. The tip step's `git ls-remote` gets 3 tries with full jitter, as in every workflow. |
| 2 | met | [`.github/workflows/pr-refine.yml`:184](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/workflows/pr-refine.yml#L184), [`.github/workflows/pr-refine.yml`:223](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/workflows/pr-refine.yml#L223), [`.github/scripts/pr-unblock/lane-hold.mjs`:82](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/scripts/pr-unblock/lane-hold.mjs#L82), [`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`:197](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/scripts/pr-unblock/fix-docs-dispatch.mjs#L197) (lines at the later change below) | A head fix-docs-head cannot read, or a human-gated hold whose reads meet a GitHub fault, holds green with a notice and starts nothing, and the dispatcher counts the held run toward `limit-stops-per-head`. Part 2 holds the `fix-docs` handoff reads (see Remaining). |
| 3 | met | [`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`:247-264](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/fix-docs-dispatch.mjs#L247-L264), [`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`:217](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/fix-docs-dispatch.mjs#L217), [`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`:236](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/fix-docs-dispatch.mjs#L236) | A red run with no check no longer ends the PR: the dispatcher dispatches again until `limit-stops-per-head` runs went red or held. A green run whose jobs show a handoff hold (`heldHandoff`) or an unread head (`heldHead`) counts toward that cap, not as done. An outage past that many runs still ends the PR. |
| 4 | met | [`.github/actions/report-check-run/decide.mjs`:105](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/actions/report-check-run/decide.mjs#L105), [`.github/workflows/pr-run-activity-read.yml`:3880](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/workflows/pr-run-activity-read.yml#L3880) (lines at the later change below) | `decide.mjs` still posts `failure` for a run with no verdict, kept on evidence as the retry signal (see Remaining). No workflow step files or demotes on an incomplete read: with `post-decline: false` the report job posts no check on a run whose run job set no head, and fix-docs-head's hold files nothing. |
| 5 | met | [`.github/workflows/pr-unblock-dispatch.yml`:109](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-unblock-dispatch.yml#L109), [`.github/workflows/pr-unblock-dispatch.yml`:184](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-unblock-dispatch.yml#L184) | The lane's only automatic starter skips the whole dispatch while the status page lists an outage. That is a stop, and the page starts nothing. |
| 6 | met | [`.github/scripts/lib/handoff-evidence.sh`:163](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/lib/handoff-evidence.sh#L163), [`.github/scripts/lib/handoff-evidence.sh`:170](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/lib/handoff-evidence.sh#L170) | The job-listing poll sends each page's `etag` as `If-None-Match` on every read after the first, and a 304 reuses the page it already read. Concurrency ([`.github/workflows/pr-refine.yml`:55](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/workflows/pr-refine.yml#L55)) is fine. |

## pr-run-checks

The lane has no workflow or script in this repository. It is declared at
[`.github/actions/resolve-config/lane-rules.json`:22](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L22), and [`.github/standards/runner-policy/policy.json`:273](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/standards/runner-policy/policy.json#L273)
points at a reusable in `melodic-software/ci-workflows`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:22](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L22) | Nothing in this repository makes calls for the lane. |
| 2 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:22](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L22) | Nothing reads. |
| 3 | not applicable | [`docs/conventions/pr-pipeline/README.md`:150](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/README.md#L150) | The lane has no cron and starts only by dispatch. |
| 4 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:22](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L22) | Nothing files. |
| 5 | not applicable | [`.github/standards/runner-policy/policy.json`:273](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/standards/runner-policy/policy.json#L273) | Only an external reusable is referenced. |
| 6 | not applicable | [`.github/standards/runner-policy/policy.json`:273](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/standards/runner-policy/policy.json#L273) | There is no concurrency or cron block here. |

## pr-review

The lane runs from `.github/workflows/pr-review-hosted.yml`, a caller of the external
`pr-review-cli.yml`, and the `claude-review` row of `.github/workflows/pr-review-main.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/workflows/pr-review-main.yml`:188](https://github.com/melodic-software/claude-code-plugins/blob/d2e6bdc1eb240c3ec9075c35853fa5d6257eed35/.github/workflows/pr-review-main.yml#L188), [`.github/workflows/pr-review-main.yml`:369](https://github.com/melodic-software/claude-code-plugins/blob/d2e6bdc1eb240c3ec9075c35853fa5d6257eed35/.github/workflows/pr-review-main.yml#L369), [`.github/workflows/pr-review-main.yml`:246](https://github.com/melodic-software/claude-code-plugins/blob/d2e6bdc1eb240c3ec9075c35853fa5d6257eed35/.github/workflows/pr-review-main.yml#L246) | Every file-list read goes through `retry_call --read` (`.github/scripts/pr-merge/retry-call.bash`): 3 reads at most, full jitter, a rate stop waited out within 60 s (see Remaining). So does each read of the judged-head pre-filter (`try_read`: the verdict listing, the run, the verdict zip, the head's check runs and the fetch of a run's main commit); one still unread after 3 runs the review with a `::notice::`, fail open, so nothing is lost but a review's cost. The shared client sends up to 3 attempts with full jitter. The hosted review's own reads, in ci-workflows' `pr-review-cli.yml` ([`.github/workflows/pr-review-hosted.yml`:331](https://github.com/melodic-software/claude-code-plugins/blob/db160c259ac38231df3f61ae8b500f2a954ecf30/.github/workflows/pr-review-hosted.yml#L331)), retry too, since ci-workflows#1033 (Remaining). |
| 2 | met | [`.github/workflows/pr-review-main.yml`:377](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-review-main.yml#L377), [`.github/workflows/pr-review-main.yml`:394](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-review-main.yml#L394), [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:758](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L758) (lines at the later change below) | A file list unread after 3 reads holds the select green with a `held:` notice and no review, and `Note the hold` marks the run; the reconciler re-runs it once (`faultHeld`, as for pr-verify). "No verdict" still ends red, kept: that red is what the reconciler's one-time re-run reads (`RECORDED_LANES`), and the merge gate binds a verdict only from a run that completed with success (`babysit_review_evidence.py:507` `_main_bound`). |
| 3 | gap | [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:333](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L333), [`.github/workflows/pr-review-hosted.yml`:215](https://github.com/melodic-software/claude-code-plugins/blob/db160c259ac38231df3f61ae8b500f2a954ecf30/.github/workflows/pr-review-hosted.yml#L215) | The rest is met; the one re-arm is kept (still-open table). Recovery is the reconciler's next pass: a recorded one-time re-run, idle while the status page lists an outage (element 5 allows that stop). The one-time record is a re-arm the owner kept: it is the trust proof for an attempt 2 (`check-trusted-trigger.mjs` `verifyRecordedRerun`). No other re-arm runs: the key-credit probing marker (`pr-review-main.yml` `review-handoffs-credit`) gates which credential runs, not when a review restarts. |
| 4 | gap | [`.github/workflows/pr-review-main.yml`:3068](https://github.com/melodic-software/claude-code-plugins/blob/b771deac0ad9dc4400db46f46875c1d6fc0cf024/.github/workflows/pr-review-main.yml#L3068), [`plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py`:497-503](https://github.com/melodic-software/claude-code-plugins/blob/5599e627fc0c0f29931e17676cc362212f7e8d52/plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py#L497-L503) | Kept (still-open table). A later clean review never clears a CRITICAL count: the merge gate carries the most CRITICAL findings any main-run review recorded on any head of the pull request (`_recorded_critical`, fed by `babysit_merge.py` `carried_critical`), so neither a re-run nor a whitespace push clears a security hold. Letting a later review close it would loosen a security control, which only the owner decides. |
| 5 | met | [`.github/workflows/pr-review-hosted.yml`:215](https://github.com/melodic-software/claude-code-plugins/blob/db160c259ac38231df3f61ae8b500f2a954ecf30/.github/workflows/pr-review-hosted.yml#L215), [`.github/workflows/pr-review-main.yml`:619](https://github.com/melodic-software/claude-code-plugins/blob/b771deac0ad9dc4400db46f46875c1d6fc0cf024/.github/workflows/pr-review-main.yml#L619) | `check-upstream-status` stops the review with exit 1. That is a stop, and the page starts nothing. The red stays: the reconciler re-runs on that failed step (`reconcile.mjs:250` `UPSTREAM_STOP_STEP`) and the merge gate binds the re-run on its error (`babysit_review_evidence.py:262` `UPSTREAM_STOP_RE`). |
| 6 | met | [`.github/workflows/pr-review-main.yml`:541](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L541), [`.github/workflows/pr-review-main.yml`:1019](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L1019), [`.github/workflows/pr-review-main.yml`:1028](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L1028), [`.github/scripts/pr-review-main/take-shared-text.sh`:21](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/scripts/pr-review-main/take-shared-text.sh#L21), [`.github/artifact-retention.json`:153](https://github.com/melodic-software/claude-code-plugins/blob/fd2181aaa7d834beedac0e384d4e8f6390e16a28/.github/artifact-retention.json#L153) (lines at this change) | Concurrency per PR and head is fine, and reads are serial within a job. The `trusted-text` job reads the PR's trusted text once per run and every leg takes it when it matches and the read is at most `SHARED_TEXT_MAX_AGE_MINUTES` old (`take-shared-text.sh:28`), so the legs no longer each read it (see the later change below). A later leg's own gate and file-list read are its trust check on a fresh VM, so they stay. |

## pr-review-security

The lane runs from `.github/workflows/pr-review-security-hosted.yml` and the
`claude-security-review` row of `.github/workflows/pr-review-main.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/workflows/pr-review-main.yml`:188](https://github.com/melodic-software/claude-code-plugins/blob/d2e6bdc1eb240c3ec9075c35853fa5d6257eed35/.github/workflows/pr-review-main.yml#L188), [`.github/workflows/pr-review-main.yml`:369](https://github.com/melodic-software/claude-code-plugins/blob/d2e6bdc1eb240c3ec9075c35853fa5d6257eed35/.github/workflows/pr-review-main.yml#L369), [`.github/workflows/pr-review-main.yml`:246](https://github.com/melodic-software/claude-code-plugins/blob/d2e6bdc1eb240c3ec9075c35853fa5d6257eed35/.github/workflows/pr-review-main.yml#L246), [`.github/workflows/pr-review-security-hosted.yml`:336](https://github.com/melodic-software/claude-code-plugins/blob/db160c259ac38231df3f61ae8b500f2a954ecf30/.github/workflows/pr-review-security-hosted.yml#L336) | It shares pr-review's code, so its file-list and judged-head reads retry, and so do the hosted review's own reads, since ci-workflows#1033 (Remaining). |
| 2 | met | [`.github/workflows/pr-review-main.yml`:377](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-review-main.yml#L377), [`.github/workflows/pr-review-main.yml`:394](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-review-main.yml#L394) (lines at the later change below) | It shares pr-review's code: a list still unread holds green for the reconciler's `faultHeld` re-run, and "no verdict" stays red, as for pr-review. |
| 3 | gap | [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:333](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L333), [`.github/workflows/pr-review-security-hosted.yml`:220](https://github.com/melodic-software/claude-code-plugins/blob/db160c259ac38231df3f61ae8b500f2a954ecf30/.github/workflows/pr-review-security-hosted.yml#L220) | As for pr-review, the rest is met and the re-arm is kept. Resume is the reconciler's next pass and its one-time recorded re-run, a re-arm the owner kept as attempt 2's trust proof, as for pr-review. |
| 4 | gap | [`.github/workflows/pr-review-main.yml`:3068](https://github.com/melodic-software/claude-code-plugins/blob/b771deac0ad9dc4400db46f46875c1d6fc0cf024/.github/workflows/pr-review-main.yml#L3068), [`plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py`:497-503](https://github.com/melodic-software/claude-code-plugins/blob/5599e627fc0c0f29931e17676cc362212f7e8d52/plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py#L497-L503) | Kept, as for pr-review: a later complete read never closes a carried CRITICAL count, a security control only the owner may loosen. |
| 5 | met | [`.github/workflows/pr-review-security-hosted.yml`:220](https://github.com/melodic-software/claude-code-plugins/blob/db160c259ac38231df3f61ae8b500f2a954ecf30/.github/workflows/pr-review-security-hosted.yml#L220), [`.github/workflows/pr-review-main.yml`:619](https://github.com/melodic-software/claude-code-plugins/blob/b771deac0ad9dc4400db46f46875c1d6fc0cf024/.github/workflows/pr-review-main.yml#L619) | The status page gates the run and turns it red. That is a stop, and the page starts nothing; the red is what the reconciler and the merge gate read, as for pr-review. |
| 6 | met | [`.github/workflows/pr-review-main.yml`:541](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L541), [`.github/workflows/pr-review-main.yml`:1019](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L1019), [`.github/workflows/pr-review-main.yml`:1028](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L1028) (lines at this change) | It shares pr-review's code: one read of the trusted text per run, which each leg takes when it matches, as for pr-review. |

## pr-verify

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/scripts/pr-verify/resolve-pr.mjs`:1142](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-verify/resolve-pr.mjs#L1142), [`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`:258-298](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/actions/check-trusted-trigger/check-trusted-trigger.mjs#L258-L298), [`.github/actions/log-api-budget/rate-guard.mjs`:577](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/actions/log-api-budget/rate-guard.mjs#L577) | The shared client sends a read at most 3 times with full jitter, and the rate latch waits out a reset within 60 s before the resend, then refuses past it (a notice under the hold opt-in). Writes go out once. |
| 2 | met | [`.github/scripts/pr-verify/resolve-pr.mjs`:1185](https://github.com/melodic-software/claude-code-plugins/blob/c6ba147d30ad9a47b7de45788539578be9128abd/.github/scripts/pr-verify/resolve-pr.mjs#L1185), [`.github/workflows/pr-verify.yml`:233](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-verify.yml#L233), [`.github/actions/check-trusted-trigger/check-trusted-trigger.mjs`:1463](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/actions/check-trusted-trigger/check-trusted-trigger.mjs#L1463) (lines at the later changes below) | A fault or a 200 whose completeness check fails (`incomplete`: a list shorter than its count, a missing field) holds the resolver green with the `held:` notice and `reason=held`, and `Note the hold` marks the run. A malformed input, a GraphQL error other than `NOT_FOUND`, a list past what the query reads (`shortList`) and the page cap stay red. The workflow's other reads still end red, kept so the reconciler re-runs the run (see Remaining). A read fault in the trigger gate stops with reason `read-fault`, and `Note the hold` marks that run too, with a `held:` notice; signal 13 counts both holds. |
| 3 | gap | [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:702](https://github.com/melodic-software/claude-code-plugins/blob/c6ba147d30ad9a47b7de45788539578be9128abd/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L702), [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:750](https://github.com/melodic-software/claude-code-plugins/blob/c6ba147d30ad9a47b7de45788539578be9128abd/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L750), [`.github/workflows/pr-verify.yml`:168](https://github.com/melodic-software/claude-code-plugins/blob/11ad59f6e11bfc0c1c59cf341445c59fae6f3b41/.github/workflows/pr-verify.yml#L168) (lines at the later change below) | A red run whose verdict write never started, the kill switch's stop included, and a held green run are each re-run once by the reconciler, from an attempt record. That is a re-arm, which the owner kept as attempt 2's trust proof, and it is the lane's whole element 3. |
| 4 | met | [`.github/workflows/pr-verify.yml`:51](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-verify.yml#L51), [`.github/scripts/pr-verify/resolve-pr.mjs`:46](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-verify/resolve-pr.mjs#L46) | A FAIL needs a complete judgment, and a later pass supersedes it. |
| 5 | met | [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:128](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L128) | The reconciler idles while the status page shows Actions as anything but operational, and re-runs only once it is and its own reads succeed. The page stops the resume path but starts nothing. |
| 6 | met | `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs` `verifyRecordedRerun` (`readListing`), `.github/actions/check-trusted-trigger/check-trusted-trigger.mjs` `createGitHub` (`ETAG`) | The re-run record listing's re-read sends the page's `etag` (`If-None-Match`), and a 304 gives back the body it came with. Concurrency ([`.github/workflows/pr-verify.yml`:102](https://github.com/melodic-software/claude-code-plugins/blob/11ad59f6e11bfc0c1c59cf341445c59fae6f3b41/.github/workflows/pr-verify.yml#L102)) and serial reads are fine. |

## pr-explain

The lane has no workflow or script in this repository. It is declared at
[`.github/actions/resolve-config/lane-rules.json`:42](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L42).

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:42](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L42) | The lane makes no calls. |
| 2 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:42](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L42) | The lane makes no reads. |
| 3 | not applicable | [`docs/conventions/pr-pipeline/README.md`:153](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/README.md#L153) | The lane has no cron. |
| 4 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:45](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L45) | The lane files nothing and may not gate. |
| 5 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:42](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L42) | No code here consults a status page. |
| 6 | not applicable | [`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml`:146](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml#L146) | There is no workflow. |

## pr-require-checks

`ci-status` is the repository's only required check, so it is a gate: a read it cannot complete
ends it red, and that red is correct. Rows 2 to 6 cite commit `91414684`, not `222d8023`; row 1
cites #13671's head, the change that made `gh_read` the one retry layer.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | gap | [`.github/workflows/pr-require-checks.yml`:4887](https://github.com/melodic-software/claude-code-plugins/blob/58af91c4db7a094bf9e0ab50c37a19f6f53504b3/.github/workflows/pr-require-checks.yml#L4887), [`.github/workflows/pr-require-checks.yml`:4909](https://github.com/melodic-software/claude-code-plugins/blob/58af91c4db7a094bf9e0ab50c37a19f6f53504b3/.github/workflows/pr-require-checks.yml#L4909) | `gh_read` is the job's one retry layer: 3 sends at most. A 4xx that is no rate limit, such as a 404 or a 403 the token lacks, fails at once (`:4904`). A 5xx, a network error or a failure with no HTTP status is sent again after a full-jitter wait of up to 5, then 10 s (`:4921`), unless that wait would end past the job's deadline. A rate limit waits once, to a second past a reset a header gave, inside the deadline; a guessed stop, such as a secondary limit with no `retry-after`, fails at once (`:4931`). A third send rate limited with a header reset names that reset in its error (`:4910`). Its callers read once and fail closed with their own error (`:5074`, `:5741`, `:5817`, `:5826`, `:6000`, `:6456`, `:7020`, `:7041`). The cost-hold loop takes no rate wait on purpose (`:5397`). The `mark-lanes` status POST (`:916`) posts the same pending status each time, so a resend changes nothing. The gap left is the pinned composites' own reads: ci-workflows#1026 fixed them, but the pins (`:5044`, `:6908`) predate it (Remaining). |
| 2 | gap | [`.github/workflows/pr-require-checks.yml`:3](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L3), [`.github/workflows/pr-require-checks.yml`:4865](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L4865), [`.github/actions/resolve-config/callers.test.mjs`:3137](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/actions/resolve-config/callers.test.mjs#L3137) | Kept: a read that fails ends red, never neutral, and no step sets `API_BUDGET_HOLD`, which `callers.test.mjs` keeps off every gate step. Holding green would pass what the gate could not read. |
| 3 | gap | [`.github/workflows/pr-require-checks.yml`:4868](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L4868), [`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`:67](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs#L67) | The workflow keeps no breaker: the `ci-lanes` status is the last full run's verdict, marked pending by each full run (`:916`) and written again at its end. A red `ci-status` recovers on the next push or label event, on `rerun-ci-status` when a review completes, or on the reconciler's one-time recorded re-run (its Switch and Pending kinds), the re-arm the owner kept (still-open table). The cron at `:35` is the whole-tree run, not the probe. |
| 4 | met | [`.github/workflows/pr-require-checks.yml`:7354](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L7354), [`.github/workflows/pr-require-checks.yml`:7340](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L7340) | `ci-status` files and demotes nothing. A review lane with no run on the head, one still running past the wait, or one a stop ended fails the check on a complete read of the head's runs, since the gate passes only on positive evidence of a review. The next `ci-status` run replaces that red, and `rerun-ci-status` and the reconciler's Pending kind start it once the review completes. |
| 5 | met | [`.github/workflows/pr-require-checks.yml`:7362](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L7362), [`.github/workflows/pr-require-checks.yml`:7414](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L7414) | `ci-status` reads a review the status-page gate stopped and starts nothing from the page; it reads the stop as red, as element 4 requires of a gate. |
| 6 | gap | [`.github/workflows/pr-require-checks.yml`:115](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L115), [`.github/workflows/pr-require-checks.yml`:7344](https://github.com/melodic-software/claude-code-plugins/blob/9141468405460a766471a7b6a9599746f1c87949/.github/workflows/pr-require-checks.yml#L7344) | Reads are serial, and the cron (`17 9,16`) is off minute 0. A scheduled run keeps its own `run_id` group, kept: the two ticks are 7 hours apart and a full run's p95 is 580 s (`:6905`), so a shared group would never hold one pending. The review wait reads each running review run once a minute, up to 8 times, with no `etag`, kept as not worth doing (see Remaining). |

## pr-unblock

The lane runs from `.github/workflows/pr-unblock.yml`, with the dispatchers
`.github/workflows/pr-unblock-dispatch.yml` and `.github/workflows/pr-feedback-dispatch.yml`.

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/scripts/pr-unblock/report-escalation.sh`:47](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/report-escalation.sh#L47), [`.github/scripts/pr-unblock/request-budget.mjs`:69](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/request-budget.mjs#L69), [`.github/scripts/pr-unblock/request-budget.mjs`:87](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/request-budget.mjs#L87) | The escalation and lane-stopped comment POSTs go out once. `budgetedFetch` resends only a read after a rate limit, inside its 3 attempts and the latch's 60 s budget, so a rate-limited POST, PATCH or GraphQL mutation goes out once with an `::error::` line. |
| 2 | met | [`.github/scripts/pr-unblock/dispatch.mjs`:222](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/dispatch.mjs#L222), [`.github/scripts/pr-unblock/dispatch.mjs`:305](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/dispatch.mjs#L305), [`.github/scripts/pr-unblock/dispatch.mjs`:873](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/scripts/pr-unblock/dispatch.mjs#L873) | A read that fails, whatever GitHub answered, holds what it was read for: an unreadable listing dispatches nothing and a PR whose reads fail is skipped, each with a warning, and the next tick reads again. A failed dispatch still counts as `failed` and exits 1. |
| 3 | gap | [`.github/scripts/pr-unblock/dispatch.mjs`:229](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-unblock/dispatch.mjs#L229), [`.github/scripts/pr-unblock/limit-stop.mjs`:21](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-unblock/limit-stop.mjs#L21) | Failed runs use up a cap for each head that blocks re-dispatch until a new push. That is a stored breaker. Part 2 took out a run whose model never started (`limit-stop.mjs` `faultStop`: class `install-failed` or `sandbox-unavailable`): it neither handles the head nor counts, so the next tick dispatches again. A `no-credential` stop still counts, since a missing secret fails every tick the way `auth` does, and so does an `overloaded`, `no-outcome`, `rate-limit` or `auth` stop or a red run with no record, because a model turn may have run, the bound the work-unblock note keeps. That count is kept on evidence (see Remaining). |
| 4 | gap | [`.github/scripts/pr-unblock/escalation-routes.json`:27](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-unblock/escalation-routes.json#L27), [`.github/scripts/pr-unblock/report-escalation.sh`:106](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-unblock/report-escalation.sh#L106) | A job fault, such as a lane token that was not obtained, files a fail route, and an unlisted reason holds the PR for a person. Its `clear` mode (`:74`) does clear its own status. A workflow-modified token refusal the feedback sweep resends files nothing; the route for every other `feedback-publish-failed` is kept on evidence (see Remaining). |
| 5 | met | [`.github/workflows/pr-unblock-dispatch.yml`:109](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-unblock-dispatch.yml#L109), [`.github/workflows/pr-feedback-dispatch.yml`:388](https://github.com/melodic-software/claude-code-plugins/blob/db1cec1cf607c268c0582bf1a9e89202c8368747/.github/workflows/pr-feedback-dispatch.yml#L388) | `degraded` gates the dispatch steps. That is a stop, and the page starts nothing. |
| 6 | met | [`.github/workflows/pr-unblock-dispatch.yml`:77](https://github.com/melodic-software/claude-code-plugins/blob/a27aff8a9c632571684d9b9dd4e9f2c977ca3e92/.github/workflows/pr-unblock-dispatch.yml#L77), [`.github/workflows/pr-unblock-dispatch.yml`:228](https://github.com/melodic-software/claude-code-plugins/blob/a27aff8a9c632571684d9b9dd4e9f2c977ca3e92/.github/workflows/pr-unblock-dispatch.yml#L228), [`.github/workflows/pr-feedback-dispatch.yml`:111](https://github.com/melodic-software/claude-code-plugins/blob/db1cec1cf607c268c0582bf1a9e89202c8368747/.github/workflows/pr-feedback-dispatch.yml#L111) (lines at the later change below) | The dispatcher keeps the default single pending run, and only a push cancels the run going. Its cron at minutes 9 and 39 (`:61`) is off minute 0 and used by no other workflow. The FAIL-cap reader's Python and PyYAML installs (`:228`, `:237`) take the dispatch step's gate, so a paced tick installs nothing. Neither workflow has a matrix or a background read, and the scripts read serially (see Remaining). Repeated reads send an `etag`: `request-budget.mjs:74` and rerun-ci-status's poll (`pr-feedback-dispatch.yml:875`). pr-feedback-dispatch's `queue: max` is kept: every pr-unblock-dispatch completion, push runs included, shares the `sweep` group, so the default would let a push run's completion, which dispatches nothing (`:321`), replace a waiting scheduled sweep; the per-head groups need it too (`:105`, `workflow-gates.test.mjs`). The upstream-status check fails open, as element 5 allows, and a failed pace read runs the tick as before (`pr-unblock-dispatch.yml:182`). |

## pr-merge

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | met | [`.github/scripts/pr-merge/retry-call.bash`:39](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-merge/retry-call.bash#L39), [`.github/scripts/pr-merge/enable-auto-merge.mjs`:406](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/scripts/pr-merge/enable-auto-merge.mjs#L406), [`.github/actions/request-lane-token/action.yml`:324](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/actions/request-lane-token/action.yml#L324), [`.github/actions/request-lane-token/action.yml`:405](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/actions/request-lane-token/action.yml#L405) (lines at this change) | The listing's `retry_call` meets the element. `withRetry` resends only a GraphQL mutation lost on the network (`:407`), and leaves reads to the shared client's 3 attempts, so no read stacks. A resent arm or disarm is pinned to the head the run read and read back once on an error (`:394-398`); the REST refusal comment goes out once. The lane-token request sends at most 3 requests and waits at most 60 s in all (`action.yml:323-324`); a rate-limit wait past that is not taken, and with `rate-limit-hold-ok`, which both of pr-merge's token steps set ([`.github/workflows/pr-merge.yml`:1167](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-merge.yml#L1167), `:2463`), it holds green with a `Lane token hold` notice and `skip-reason` `rate-limited`, and every step that uses the token skips on the empty `token`, as on a kill-switch stop. Monitor signal 13 counts the hold (`signals.mjs` `HOLD_LANES`). |
| 2 | gap | [`.github/workflows/pr-merge.yml`:1279](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L1279), [`.github/workflows/pr-merge.yml`:1283](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L1283) (lines at the later change below) | A failed listing, a past-budget rate stop and a listing at the limit hold green with the `Merge lane hold` notice, and signal 12 counts each held sweep. The other rate-limit stops (`:303`, `:415`, `:565`, `:969`, `:1467`, `:1760`, `:2263`) still end red, kept on evidence, and so does a failed cover read's dispatch with no cap (`:420`) (see Remaining). |
| 3 | met | [`.github/workflows/pr-merge.yml`:1036](https://github.com/melodic-software/claude-code-plugins/blob/f5d5a50f47f9cf8fcc607d43b5bd4e7e3cf318af/.github/workflows/pr-merge.yml#L1036), [issue 12292 comment](https://github.com/melodic-software/claude-code-plugins/issues/12292#issuecomment-6701472884) | The lane's own hold waits for the next tick. The lane breaker's kill switch (`CLAUDE_LANES_REPO_DISABLED`, which pr-merge stops on) clears with no person: after the reset, once every GitHub-token window reads above its clear threshold, the breaker sets it to `false`. The record shows 78 automatic `BREAKER-CLEAR` entries. |
| 4 | met | [`.github/workflows/pr-merge.yml`:1419](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-merge.yml#L1419), [`.github/workflows/pr-merge.yml`:1413](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-merge.yml#L1413), [`.github/workflows/post-merge-demotion-alert.yml`:1595-1626](https://github.com/melodic-software/claude-code-plugins/blob/5599e627fc0c0f29931e17676cc362212f7e8d52/.github/workflows/post-merge-demotion-alert.yml#L1595-L1626) | The lane files only on a judged failure and skips filing on a held listing. A later complete read closes the record it filed: post-merge-demotion-alert's `close-cleared` job closes a schedule or dispatch record (`babysit_postmerge.py` `SELF_CLEARING_SIGNALS`) at the oldest green full run on main that clears it, and `babysit_lift.py close` closes a canary, revert or read-back record once it lifts by the merge gate's rule (`babysit_merge_policy.py` `_lift`); a failed read closes nothing (#12282). A canary or revert record with no lift block keeps a person-only close, by owner decision (#7531, #11022 Q3). |
| 5 | met | [`.github/workflows/pr-merge.yml`:1187](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-merge.yml#L1187) | The hold notice reads no status page, and nothing in the lane reads githubstatus. |
| 6 | gap | [`.github/workflows/pr-merge.yml`:125](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L125), [`.github/workflows/pr-merge.yml`:929](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L929), [`.github/workflows/pr-merge.yml`:695](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L695) (lines at the later change below) | The cron (minutes 11 and 41) is off minute 0 and the gate loop is serial. The three `queue: max` groups (also `:2244`, `:3172`) are kept on evidence (see Remaining). An `etag` on the listing and cover reads is not applicable: each is read once a run and no job state carries one between runs. The re-run read-back polls one URL up to 7 times with no `etag`, kept as not worth doing (see Remaining). |

### How pr-merge surfaces a permanent fault (element 2)

- **A bad `GITHUB_TOKEN` on the listing.** `retry_call` tries 3 times, then the job prints only
  `::notice title=Merge lane hold::` and ends green ([`.github/workflows/pr-merge.yml`:1187](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-merge.yml#L1187)). The
  sweep summary records `listing_held` ([`.github/workflows/pr-merge.yml`:1911](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/workflows/pr-merge.yml#L1911)). After 4 held sweeps
  in a row, `maintenance-monitor-signals` updates a rolling issue
  ([`.github/scripts/maintenance-monitor-signals/signals.mjs`:385](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/maintenance-monitor-signals/signals.mjs#L385)). That issue is how a person
  hears about it.
- **A bad lane token.** A broker refusal or an unreachable broker prints `::error::` and turns the
  job red ([`.github/actions/request-lane-token/action.yml`:207](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/actions/request-lane-token/action.yml#L207), `:373`, `:446`). A GitHub rate
  limit past the request's 1-minute budget holds green instead, with the `Lane token hold` notice
  ([`.github/actions/request-lane-token/action.yml`:405](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/actions/request-lane-token/action.yml#L405)). In
  enable-auto-merge it prints `::error title=enable-auto-merge::` and turns red
  ([`.github/scripts/pr-merge/enable-auto-merge.mjs`:2387](https://github.com/melodic-software/claude-code-plugins/blob/f65ddab412299d5b0f2b8bf904d2161ddbf2bbbb/.github/scripts/pr-merge/enable-auto-merge.mjs#L2387)).
- **1000 or more open pull requests.** The listing holds green with the same notice and a fixed
  `listing full` reason, after one call ([`.github/workflows/pr-merge.yml`:1279](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L1279), lines at the later
  change below). The sweep summary records `listing_held`, so signal 12 counts it as it counts a
  failed listing. enable-auto-merge holds green too (see Remaining).
- **A rate limit during a green hold.** The shared `api_budget_stop` still prints `::error::`
  ([`.github/actions/log-api-budget/api-budget.bash`:388](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/log-api-budget/api-budget.bash#L388)). `retry_call` passes that stderr through
  ([`.github/scripts/pr-merge/retry-call.bash`:28](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/scripts/pr-merge/retry-call.bash#L28)), and the step then ends green with the notice.

This audit did not verify whether GitHub can return a short listing and a short `totalCount`
together.

## post-merge-verify

The lane has no workflow or script in this repository. It is declared at
[`.github/actions/resolve-config/lane-rules.json`:68](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L68). Only the example config lists it
([`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml`:171](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml#L171)).

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:68](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L68) | Nothing in this repository makes calls for the lane. |
| 2 | not applicable | [`docs/conventions/pr-pipeline/README.md`:158](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/README.md#L158) | The trigger is documented, but no workflow implements it. |
| 3 | not applicable | [`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml`:171](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml#L171) | `docs/conventions/pr-pipeline.yaml` has no such lane, so there is no cron. |
| 4 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:68](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L68) | Nothing files. |
| 5 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:68](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L68) | There is no code to check. |
| 6 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:68](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L68) | There is no workflow. |

## post-merge-sweep-comments

The lane has no workflow or script in this repository. It is declared at
[`.github/actions/resolve-config/lane-rules.json`:73](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L73). The example config lists it with
`enabled: false` ([`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml`:175](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml#L175)).

| Element | Verdict | Evidence | Why |
|---|---|---|---|
| 1 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:73](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L73) | Nothing in this repository makes calls for the lane. |
| 2 | not applicable | [`docs/conventions/pr-pipeline/README.md`:159](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/README.md#L159) | The trigger is documented, but no workflow implements it. |
| 3 | not applicable | [`docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml`:175](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/docs/conventions/pr-pipeline/examples/claude-code-plugins.yaml#L175) | The lane has no cron. |
| 4 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:73](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L73) | Nothing files. |
| 5 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:73](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L73) | There is no code to check. |
| 6 | not applicable | [`.github/actions/resolve-config/lane-rules.json`:73](https://github.com/melodic-software/claude-code-plugins/blob/222d80236d0c900bd3f1c183f99514cfd026719d/.github/actions/resolve-config/lane-rules.json#L73) | There is no workflow. |

## Remaining

Part 1 (#12291) fixed no gap. The **workflow** gaps below need a workflow-file change, which this
lane cannot push. The **script** gaps are part 2 of #12283 (#12292). #12282 built element 4's
self-close for pr-merge's records.

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
  The later pr-merge change below holds the workflow's own listing at the limit too.
- **pr-merge, element 1.** The lane-token request sends at most 3 requests and waits at most 60 s
  in all, down from 4 requests and 480 s. A `github-unavailable` retry waits 0 to 20 s, then 0 to
  40 s (full jitter), or a longer `Retry-After`. A wait that does not fit is not taken, and the step
  fails red at once, as it does on any final broker answer (`.github/actions/request-lane-token/action.yml`).
  A later change holds that rate limit green for a caller that opts in: with `rate-limit-hold-ok`,
  a last answer of 503 `github-rate-limited` ends the step with a `Lane token hold` notice,
  `skip-reason` `rate-limited` and no token. Both pr-merge token steps opt in, and every step that
  uses the token already skips on an empty `token`, as for a kill-switch stop. The skipped sweep
  writes no sweep line, so signals 3 and 12 never see the hold; signal 13 counts it instead, through
  pr-merge's `HOLD_LANES` entry and the fixed reason `lane token rate-limited` (`signals.mjs`
  `HOLD_NOTICES`). The other callers keep the red
  until their workflow opts in (`.github/actions/request-lane-token/request-lane-token.test.mjs`).

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
next checks run. The reconciler lists pr-verify's and pr-review-main's succeeded runs from `FAULT_HELD_HOURS` back, or
from the last pass that read when that is earlier, since a pass idle through an outage reads
nothing, or from the oldest first attempt that pass saw still going, since a run's three jobs can
take about 17 hours. That pass already lists the runs still going, so this adds no read. Each run's jobs are read once, since a run with no hold is carried as settled, and at
most `FAULT_HELD_READS` a pass across both lanes. pr-verify's about 700 succeeded runs a day and
pr-review-main's 425 on 2026-11-05 make about 47 jobs reads an hour, plus one or two listing reads
per lane a pass. Monitor signal 13 counts these holds since the trigger-gate change below.

The holds above end green with only a notice, so the monitoring lane's signal 13 counts them: the
`retry-spent` fault hold, work-resolve-issue's `WIP cap hold`, work-unblock's held listings and issue reads, pr-refine's held `fix-docs` reads and unread heads,
intake-triage's held verdicts (`apply-verdict.mjs` `closing`), and pr-merge's `Lane token hold`. A
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
([`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`:188-199](https://github.com/melodic-software/claude-code-plugins/blob/a37ff7eb57a0c72e475792634304c30d2c287ba3/.github/scripts/pr-unblock/fix-docs-dispatch.mjs#L188-L199), lines at the later change below)
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
  and on `workflow_run` ([`.github/scripts/work-unblock/label-unblocked.mjs`:2367](https://github.com/melodic-software/claude-code-plugins/blob/90e8a09862a21534957c59196df4d25f733df8e5/.github/scripts/work-unblock/label-unblocked.mjs#L2367)). Nothing was
  stranded. The sweep's window counts only successful scheduled runs
  (`label-unblocked.mjs:626-632`), so a kick never moved it, and a broker-check trip re-fires on the
  next sweep with no wait (`label-unblocked.mjs:1879`), while a mint trip waited
  `limits.reset-clamp-min` with or without a kick.
- **work-unblock, element 6.** `queue: max` is gone from `label-unblocked`
  ([`.github/workflows/work-unblock.yml`:134](https://github.com/melodic-software/claude-code-plugins/blob/90e8a09862a21534957c59196df4d25f733df8e5/.github/workflows/work-unblock.yml#L134)), so a newer run replaces the waiting one. No waiting
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
  fix-docs skipped, but has no such job, so it still ends the PR. A bad `pr-number` still ends red,
  and so does a `lane-hold.mjs` read refused for a reason other than a fault (the change below).
- **pr-refine, element 4.** Nothing to change: no workflow step files or demotes on an incomplete
  read. A cancelled run whose report-time head read fails still posts `failure` on the gated head,
  but the cancel itself (a timeout, since `cancel-in-progress` is false) is the evidence, and for
  fix-docs any check on the PR's last 50 commits ends the PR either way (`historyHasRun`).

Later changes fixed pr-review's and pr-review-security's file-list and judged-head reads, with
tests. Their rows cite the latest of those heads, not `222d8023`.

- **pr-review and pr-review-security, element 1.** The trigger job's file-list read and each leg's
  select read go through `retry_call --read 60` (`.github/scripts/pr-merge/retry-call.bash`): up to
  3 reads, a capped backoff with full jitter, and a rate stop waited out within 60 s of waits. A
  trigger read still unread leaves no result and the gate runs, as before; a select read still
  unread holds green (element 2, below). The
  judged-head pre-filter's reads and its fetch go through it too (`try_read`); one still unread
  runs the review with a notice, the safe side: nothing is lost but a review's cost. Element 3's
  one re-arm is kept, and element 5 is met as it stands (still-open table).

A later change held pr-review-main's unread file lists green, with tests. The pr-review and
pr-review-security rows 2 cite its head.

- **pr-review and pr-review-security, element 2.** Each of the four `Select a lane-source pull
  request` steps (the trigger job's and each leg's) that cannot read the list after 3 reads prints
  a `held:` notice, sets `held`, and exits 0 ([`.github/workflows/pr-review-main.yml`:377](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-review-main.yml#L377)). `Note
  the hold` follows it, as in pr-verify. A held trigger job starts no leg: its `held` output skips
  the key leg, the credit gate's skipped-leg reports and the credit-stop handoff. A held leg takes
  no gate result, so it reviews nothing and leaves no verdict. The reconciler's `faultHeld` now
  lists pr-review-main's succeeded runs beside pr-verify's (`FAULT_HELD_LANES`,
  `reconcile.mjs:351`) and re-runs a held first attempt once, with the lane record. It waits while
  the upstream gate reads an outage, as a lost pr-review-main run does (`:1398`). A held run in
  which any job's verdict write started is held for a person, as `holdReason` holds a red one,
  since a whole-run re-run would review the written lane again. "No verdict" stays red. Signal 13
  counts the hold with the fixed reason `file list unread` (`signals.mjs` `HOLD_LANES`): the
  entry reads the trigger job and each leg, whose matrix runs list as `review (…)`, and only a job
  whose `Note the hold` ran has its annotations read. Its cap of 70 runs a window and 4 list pages
  scales pr-verify's measured peaks to pr-review-main's 425 green runs on 2026-11-05.

A later change read pr-review-main's trusted PR text once per run, with tests. The pr-review and
pr-review-security rows 6 cite its head.

- **pr-review and pr-review-security, element 6.** Each leg read the text itself
  (`select-trusted-text`): a pull read, three listings, a GraphQL read of the closing issues and
  renames, at least one GraphQL read of the editors, and two reads per closing issue
  ([`.github/actions/select-trusted-text/select-trusted-text.mjs`:153-202](https://github.com/melodic-software/claude-code-plugins/blob/fd2181aaa7d834beedac0e384d4e8f6390e16a28/.github/actions/select-trusted-text/select-trusted-text.mjs#L153-L202)), so at least 6 calls a
  leg, and 12 a run once both key legs ran, plus 6 for each subscription or fallback leg. The
  `trusted-text` job now reads it once ([`.github/workflows/pr-review-main.yml`:541](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L541)), on this
  attempt's trigger gate result and under the legs' kill switch and upstream status, whose stop is a
  notice there rather than a red. It scans `context.json` with `scan-upload` and uploads it as
  `trusted-text-pr-review-main`, its own 1-day family outside the `pr-review-main-*` verdict names
  ([`.github/artifact-retention.json`:153](https://github.com/melodic-software/claude-code-plugins/blob/fd2181aaa7d834beedac0e384d4e8f6390e16a28/.github/artifact-retention.json#L153)), and outputs its sha256, main commit, PR number, head and
  run attempt, and the time it read the text. Each leg downloads it
  ([`.github/workflows/pr-review-main.yml`:1019](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L1019)) and takes it
  ([`.github/workflows/pr-review-main.yml`:1028](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/workflows/pr-review-main.yml#L1028)) only when all five match its own
  ([`.github/scripts/pr-review-main/take-shared-text.sh`:21](https://github.com/melodic-software/claude-code-plugins/blob/f5a8ec073f507ec0d16dd168e5438020bfd5de72/.github/scripts/pr-review-main/take-shared-text.sh#L21)) and the read is at most
  `SHARED_TEXT_MAX_AGE_MINUTES` (20) old (`take-shared-text.sh:28`), since a subscription or
  fallback leg can start hours later, after the PR body or a trusted comment changed; any other case, a missing artifact
  included, leaves its own read as before, so a run sends 6 calls where it sent 12 or more. The
  job and each of its steps that can fail carry `continue-on-error`, and each leg's `needs` edge sits
  under its `!cancelled()` gate, so a failed read neither turns the run red nor skips a leg. The
  file-list selects, their `held:` notice and `Note the hold` are unchanged. A run whose diff
  stops before the review (binary, too large) now still sends the one read, where it sent none.

A later audit of pr-require-checks' workflow changed no step; its rows 2 to 6 cite commit
`91414684`. A change after it, #13671, rewrote the job's read retries; row 1 cites #13671's head.

- **pr-require-checks, element 1.** `retry_call --read` could not wrap these reads. Wrapped
  around `gh_read`, its rate wait ran inside each of the 3 tries, so the sends stacked, and
  `gh-read.sh` is written before the `.base` checkout that carries `retry-call.bash`. `gh_read`
  now holds the retry itself: 3 sends, full jitter, and a header-given reset waited out; a 4xx
  that is no rate limit is not sent again. It is written inline rather than as a verbatim copy,
  since it reads its own pool's stop, fails a guessed one at once, and measures each wait against
  the job's deadline instead of a seconds budget. The callers' loops are gone, and each still
  fails closed when `gh_read` gives up.
- **pr-require-checks, elements 2, 4 and 6.** Kept on evidence: the gate fails closed, its red on
  a missing review is a complete read's result, and the scheduled group never holds two runs.
  Element 3's only re-arm is the reconciler's kept record, and element 5 is met.

A later change reviewed pr-verify's workflow row. Its pr-verify rows 2 and 3 cite that change's head.
Only the workflow header's account of the resolver changed: no step was made to hold.

- **pr-verify, element 2.** Every read before the verdict write other than the resolver's still
  ends red: main's tip ([`.github/workflows/pr-verify.yml`:137](https://github.com/melodic-software/claude-code-plugins/blob/11ad59f6e11bfc0c1c59cf341445c59fae6f3b41/.github/workflows/pr-verify.yml#L137)), the checkout (`:147`), the trusted
  PR text (`:245`), the diff fetch (`:264`), the upstream run's jobs (`:303`) and the model config
  (`:367`), with the same steps in the two later jobs. That is kept. The reconciler re-runs a red
  first attempt whose verdict write never started (`reconcile.mjs:236`, `holdReason` at `:702`),
  and it re-runs a green one only when the job ran `Note the hold` with a `held:` notice
  (`faultHeld`, `reconcile.mjs:750`). A step held green any other way would end that re-run unseen.
  After the write starts, a red run is held for a person, so a head is never judged twice
  (`reconcile.mjs:738`). wake-pr-merge cannot fail the run (`continue-on-error`): a failed read dispatches
  anyway and a failed dispatch warns, and pr-merge's schedule arms the PR (`pr-verify.yml:5804`). A
  rate limit past the guard's budget still prints the gh wrapper's `::error::` there, since the
  step sets no `API_BUDGET_HOLD` (`api-budget.bash:409`). A read fault in the trigger gate now
  reads `read-fault` and is a counted hold (the trigger-gate change below).
- **pr-verify, element 3.** It is the kept re-run alone. The next pr-require-checks completion is
  the only other start, and a run held again at attempt 2 waits for it.

A later change audited pr-unblock's two dispatcher workflows, with tests. Its pr-unblock row 6
cites that change's head.

- **pr-unblock, element 6.** `pr-unblock-dispatch.yml`'s Python and PyYAML installs now take the
  dispatch step's gate, so a tick the burn-rate pacer paces installs nothing. The rest is kept on
  evidence: the cron, the single pending dispatcher run, the conditional reads, and
  pr-feedback-dispatch's `queue: max`, which keeps a scheduled sweep from being replaced by a push
  run's completion.

A later change fixed pr-merge's listing-full gap, with tests. Its pr-merge rows 2 and 6 cite that
change's head, not `222d8023`.

- **pr-merge, element 2: a full listing.** A listing that reaches gh's limit of 1000 now holds as
  a failed listing does: the `Merge lane hold` notice, `held` with the fixed reason `listing full`,
  no `listed`, and a green exit after one call ([`.github/workflows/pr-merge.yml`:1279](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L1279)). Nothing
  after it gates, arms or merges, and the next scheduled run lists again. The sweep summary records
  `listing_held`, so signal 12 counts these sweeps (`signals.mjs` `listingHeldFindings`, fed by
  `collect.mjs:412`). Counting it under signal 13 too would count the same hold twice, so pr-merge's
  `HOLD_LANES` entry has no `Merge lane hold` pattern and counts only the lane token hold.
- **pr-merge, element 2: the other rate-limit stops, kept.** The post-merge check (`:303`,
  `:1467`), the cover read (`:415`), the dispatch (`:565`), the gate (`:1760`) and the jobs' first
  step after post-merge-dispatch's stop (`:969`, `:2263`) still end red. The red skips every later
  step that runs only on success (`:967-968`), and the steps that run after a failure test the
  stop's `rate-limited` output, so a green exit would run steps that now skip.
  Signal 3 reads their failure annotations (`signals.mjs:129-139`); only the listing's hold reaches
  it from a green run (`signals.mjs:146-153`). The convention says a stop costs at most one sweep
  ([`docs/conventions/pr-pipeline/README.md`:3636-3641](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/docs/conventions/pr-pipeline/README.md#L3636-L3641)), and the workflow header says a step sets
  `API_BUDGET_HOLD` only once its script is shown to hold ([`.github/workflows/pr-merge.yml`:72-77](https://github.com/melodic-software/claude-code-plugins/blob/ab8218883b1d502048246060f60a44e72ae3ca6e/.github/workflows/pr-merge.yml#L72-L77)).
- **pr-merge, element 2 and 6: the cover-read dispatch, kept.** A cover read that fails for a
  reason other than a rate limit dispatches with no cap (`:420`, `:2991`). That dispatch merges
  nothing: it is the merge's verification run, and skipping it would leave a merge unverified, and
  the lane arming nothing past `merge.max-in-flight`, until a run reads the cover again. The load is
  bounded: pr-require-checks holds main's dispatches in one group, one running and one waiting,
  and a newer dispatch replaces the waiting one before it starts (`:2832-2835`).
  `workflow.test.mjs` and `merge-job.test.mjs` pin the `no cap applies` warning.
- **pr-merge, element 6: `queue: max`, kept.** Each group's comment shows why a waiting run is never
  dropped. A cancelled merge run leaves a CANCELLED `merge` check that the merge hook refuses
  (`:917-926`). A cancelled enable-auto-merge run leaves a CANCELLED check on the PR that woke it
  (`:2240`). gate-check's runs wait in line so that none is cancelled onto a PR head (`:3164-3166`).

A later part 2 change held `lane-hold.mjs` green on a read fault, with tests. Its pr-refine row 2
cites its head.

- **pr-refine and pr-unblock, element 2: the human-gated hold.** When the pull, timeline or review
  read meets a GitHub fault (a 5xx or 429, a rate-guard stop under the step's `API_BUDGET_HOLD`
  opt-in, or no answer), `lane-hold.mjs` logs one notice, writes `unread=true` and neither `held`
  nor `lane-escalated`, and exits 0 ([`.github/scripts/pr-unblock/lane-hold.mjs`:82](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/scripts/pr-unblock/lane-hold.mjs#L82)). Before, the
  pull or timeline read ended the step red, and a failed review read held the PR as a person's
  hold, which for fix-docs ended the PR. Any other refused read, a 403 or 404 among them, still ends
  red, and a review read refused that way still holds for a person. Each caller proceeds only on
  `held` `false` and posts its skip only on `held` `true`, so a fault hold runs and posts nothing:
  - pr-refine's `fix-docs-head` passes the hold's `unread` on, so only `fix-docs-head-held` starts.
    Its `PR head hold` notice names the hold (`the human-gated hold of #N could not be read`), and
    signal 13 counts it with the fixed reason `PR hold unread` (`signals.mjs` `HOLD_NOTICES`).
    `fix-docs-dispatch.mjs` `heldHead` counts the run toward `limit-stops-per-head`, as it counts an
    unread head.
  - pr-unblock's `resolve-conflicts-select` and `sync-shared-copies-select` decide nothing (empty
    `proceed`), so no check lands on the head and the next dispatcher tick sends it again. The
    dispatcher reads the same hold first (`dispatch.mjs` `prHold`) and skips a PR whose reads fail,
    so an outage sends nothing. For sync-shared-copies this replaces the failure check a red select
    posted, which counted toward the head's cap.

A later part 2 change made pr-verify's trigger-gate fault a counted hold, with tests. Its pr-verify
row 2 cites its head.

- **pr-verify, element 2: the trigger gate.** The gate turned a read fault into `proceed=false`
  with `no-pr`, `untrusted-actor` or `untrusted-rerunner`, the reasons a real refusal gets, so the
  job ended green with no notice and no re-run. A stop is now marked as a fault where a read throws
  and the gate refuses on it (`fetchPull`, `resolveRunPull`, `readOrRefuse`, the tag lookup, the
  re-run record listing, and an unexpected error in `main`), when `isFault` holds: a 5xx or 429,
  a rate-guard stop, or no answer. With the action's new `fault-reason: "true"` input, `main` then
  writes reason `read-fault` (`check-trusted-trigger.mjs:1463`). Only pr-verify's three gate steps
  and pr-verify-capture's two set it, which keeps the capture's gate the judge's own; every other
  caller still gets the refusal's reason, since `pr-run-activity-read.yml` and
  `pr-run-activity-write.yml` post a gate's reason as a skip check. `proceed` stays `false` on a
  fault, so nothing the gate refused before proceeds, and a refusal on an answer GitHub gave (a
  404, a 403, an unlisted actor or author, a fork, a non-default base, a tag that shares the
  default branch's name) keeps its own reason; tests pin both. A candidate record whose run read
  fails still only fails to vouch, so a later refusal keeps its reason.
- `Note the hold` now follows the gate in each pr-verify job ([`.github/workflows/pr-verify.yml`:233](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-verify.yml#L233))
  and runs on the resolver's `held` or the gate's `read-fault`. For the gate it prints the
  `::notice title=pr-verify::held:` line `reconcile.mjs` `heldNoted` reads, so the reconciler
  re-runs the run once, and attempt 2 checks the trigger again from scratch. A rate-guard stop still
  fails the gate step red, as a gate must, and the reconciler re-runs that red run as before.
- Signal 13 counts both pr-verify holds (`signals.mjs` `HOLD_LANES`, `:429`), with the fixed reasons
  `resolver fault` and `trigger gate fault`. The 24 hours to 2026-11-06T12:00Z had 504 green
  pr-verify runs, with a peak of 58 created in one hour and 267 in one 7-hour created span, past
  the default caps of 6 runs a window and 3 list pages. The entry sets 80 runs and 5 pages, and
  reads a job's annotations only when its `Note the hold` step succeeded (`holdStep`, in
  `collect.mjs`), so a run that did not hold costs one jobs read.

pr-unblock's elements 3 and 4 script row is kept on evidence; nothing in it is left to build:

- **Element 3.** `limit-stop.mjs` already leaves out a run whose model never started: a
  `install-failed` or `sandbox-unavailable` stop neither handles the head nor counts
  ([`.github/scripts/pr-unblock/limit-stop.mjs`:109](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/scripts/pr-unblock/limit-stop.mjs#L109), `faultStop`). What still counts is a stop where
  a model turn may have run, and that count is the lane's plan-usage bound, not a stored breaker:
  resolve-conflicts' dispatcher retries a failed run on every half-hourly tick
  ([`.github/scripts/pr-unblock/dispatch.mjs`:257](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/scripts/pr-unblock/dispatch.mjs#L257), `failuresRetry`), and only the cap ends the head
  until a new push (`limit-stop.mjs:182`). No tick waits on it, so the next tick is still the probe.
- **Element 4.** `feedback-publish-failed` already files nothing where a sweep sends the reply job
  again: `report-stop-status` reads this run's jobs and the reply job's annotations, and on a
  workflow-modified token refusal that `feedback-dispatch.mjs` `sweepRefused` resends it posts no
  status and no comment ([`.github/scripts/pr-unblock/report-escalation.sh`:120](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/scripts/pr-unblock/report-escalation.sh#L120), `:211`;
  [`.github/workflows/pr-unblock.yml`:4493](https://github.com/melodic-software/claude-code-plugins/blob/25bd67f8e1a779421e6b09a2b065bd6ddd772d81/.github/workflows/pr-unblock.yml#L4493)). Every other `feedback-publish-failed` (a script error, a
  transient token refusal, a failed read, a head at the sweep's `SWEEP_HEAD_CAP`) has no resend, so
  withholding its failing status would leave the head stopped with no record; the route is that
  record, and its `clear` mode removes it once a later round succeeds.

The two `etag` rows are kept as not worth doing:

- **pr-require-checks, element 6: the review wait.** It reads each review run still going once a
  poll, `REVIEW_WAIT_SECONDS / REVIEW_POLL_SECONDS` = 480 / 60 = 8 polls at most per lane, and at
  most two lanes wait, so a `ci-status` run sends at most 16 such reads
  ([`.github/workflows/pr-require-checks.yml`:7323](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/workflows/pr-require-checks.yml#L7323), `:7337`). There were 586 `pull_request` runs of
  the workflow in the 24 hours to 2026-11-06T12:00Z, about 24 an hour, and a label or edit run
  waits 0 s (`:7005`). If every run waited the whole cap, that is about 390 reads an hour; how
  many runs wait, and for how long, is UNVERIFIED.
  GitHub counts a `304` answer to an authorized conditional request against no primary rate limit
  ([best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api):
  "Making a conditional request does not count against your primary rate limit if a `304` response
  is returned"), but the `GITHUB_TOKEN` limit is 1,000 requests an hour
  per repository ([rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)),
  and the rate-limits page says nothing about a `304` and secondary limits, where a GET costs one
  point. The run being polled is still going, so its body (status, `updated_at`) can change between
  polls, and a `304` saves only polls where nothing moved: at most 8 reads a lane a run. Saving them
  would add a conditional path to `gh_read`, the required gate's one retry layer, which has no path
  for a `304` today. Not worth doing while the wait is that bounded; reopen if `ci-status` shows
  `GITHUB_TOKEN` rate stops.
- **pr-merge, element 6: the re-run read-back.** After one `rerun-failed-jobs` POST the step reads
  the run up to 7 times (waits 0, 5, 10, 20, 30, 45 and 60 s), and stops at the first read that
  shows an attempt past 1 ([`.github/workflows/pr-merge.yml`:697-705](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/workflows/pr-merge.yml#L697-L705)), so it sends at most 7 reads
  a re-run, on a step that runs only when a merge run needs a re-run. How often a `304` would
  answer one of them is not measured. Not worth doing.

The other script rows below are still open.

| Lane | Element | Kind | File to change |
|---|---|---|---|
| work-unblock | 3 | kept | `.github/scripts/work-unblock/label-unblocked.mjs` keeps its breaker-trip records: they are the lane's own comments, read from GitHub each run, and bound kill-switch re-fires that start a lane run or a model turn (see above); they gate no cron tick, so the next sweep is still the probe |
| pr-refine | 4 | kept | `.github/actions/report-check-run/decide.mjs` keeps posting failure on no verdict: it is the retry signal `fix-docs-dispatch.mjs:188-199` and pr-unblock's `fix-ci-unreported` read (see above); part 2 fixed elements 1, 2 and 3 in `handoff-evidence.sh` and `fix-docs-dispatch.mjs`, and the later pr-refine change above the workflow's elements 1, 2 and 4 |
| pr-review, pr-review-security, pr-verify, pr-require-checks | 3 | kept | `.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs` keeps its one-time re-run record, the trust proof for an attempt 2 (`check-trusted-trigger.mjs` `verifyRecordedRerun`), and its status-page idle, a stop element 5 allows |
| pr-review, pr-review-security | 4 | kept | `plugins/source-control/skills/babysit-prs/scripts/babysit_review_evidence.py` keeps carrying the most CRITICAL findings any review recorded on the pull request (`_recorded_critical`): a later clean review closing it would loosen a security control, which is the owner's decision, not this audit's |
| pr-verify | 2 | kept | `.github/workflows/pr-verify.yml` keeps its non-resolver reads red: the reconciler re-runs a red run whose verdict write never started, and sees a green hold only through `Note the hold` and a `held:` notice (`reconcile.mjs` `faultHeld`) (see above) |
| pr-require-checks | 2, 4, 6 | kept | `.github/workflows/pr-require-checks.yml` keeps its red on a read it could not complete and on a head with no counted review, since a gate that held green would pass what it could not read; scheduled runs keep their own groups, which two ticks 7 hours apart never contend for |
| pr-unblock | 3, 4 | kept | `.github/scripts/pr-unblock/limit-stop.mjs` keeps counting a stop where a model turn may have run toward `limit-stops-per-head`, the lane's plan-usage bound, and `escalation-routes.json` keeps `feedback-publish-failed`'s fail route for every stop no sweep sends again (see above); part 2 fixed `report-escalation.sh`'s comment resends, `request-budget.mjs`'s write resends and 6-minute waits, the lane's parallel reads, the dispatchers' failed reads, and the cap's count of fault stops whose model never started |
| pr-merge | 2, 6 | kept | `.github/workflows/pr-merge.yml` keeps its rate-limit stops red (the red skips the rest of the job, and signal 3 reads it), the failed cover read's uncapped dispatch (a verification run, bounded by pr-require-checks' main-dispatch group) and its three `queue: max` groups (a cancelled run leaves a CANCELLED check) (see above) |
| pr-require-checks, pr-merge | 6 | kept | the review wait's run poll ([`.github/workflows/pr-require-checks.yml`:7337](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/workflows/pr-require-checks.yml#L7337)) and the re-run read-back ([`.github/workflows/pr-merge.yml`:699](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/workflows/pr-merge.yml#L699)) send no `etag`: not worth a conditional read in a gate's one retry layer (see above) |

Outside this repository, `melodic-software/ci-workflows` fixed both gaps (lines at commit
`96ea8d4c` there):

- **pr-require-checks, elements 1 and 6.**
  [ci-workflows#1026](https://github.com/melodic-software/ci-workflows/pull/1026) changed the
  `check-contract` and `aggregate-results` composites (called at
  [`.github/workflows/pr-require-checks.yml`:5045](https://github.com/melodic-software/claude-code-plugins/blob/d4d5c4939c10ecc0939b76f9d4346762293ab2bf/.github/workflows/pr-require-checks.yml#L5045) and `:6896`). Their shared `gh_api`
  (`.github/actions/pr-require-checks/gh-api.sh:234`) sends a call at most 3 times. It waits out a
  rate limit once, within `rate-limit-wait-seconds`. It resends a 5xx or a network error after a
  full-jitter wait, but never a GraphQL mutation (`:222`), a comment create or a
  `rerun-failed-jobs`. A repeated GET sends `If-None-Match` (`:123`). This repository pins both
  composites to commits from before that change (`check-contract@2476d5dd`,
  `aggregate-results@226dad32`), so the fix reaches `ci-status` only when the pins move to a commit
  that contains `03d2e3dc`.
- **pr-review and pr-review-security, elements 1, 2 and 6.**
  [ci-workflows#1033](https://github.com/melodic-software/ci-workflows/pull/1033) changed
  `pr-review-cli.yml`. Each read in the hosted leg goes out at most 3 times: the scope step's
  client (`.github/workflows/pr-review-cli.yml:911`) and the compare and context reads (`:1292`).
  A diff base it still cannot read sets `held` (`:1336`). The status job's `Note the hold` step
  (`:7659`) then posts a `held:` notice and ends green, and no model runs. Reads are serial and
  nothing polls, so an `etag` has nothing to save.
