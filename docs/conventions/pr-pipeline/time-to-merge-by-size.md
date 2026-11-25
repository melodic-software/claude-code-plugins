# Time to merge by size band

This file breaks the time from opening a pull request to merging it into stages, per size band, and
ranks the pipeline changes that would bring each band's median to one hour or less. It is analysis
only: [`stage-order-baseline.md`](stage-order-baseline.md) stays as it is, and each ranked change is
filed as its own issue. The target, set by the owner on
[#18929](https://github.com/melodic-software/claude-code-plugins/issues/18929#issuecomment-7163805963):
a median of at most 1 h in every band, or a measured reason for a band with too few pull requests
for a stable median.

## Window and sources

Measured 2026-11-25. The window is every pull request merged into `main` from 2026-11-18T18:00Z to
2026-11-25T18:00Z: 1,380 of them. A size band is additions plus deletions, as in the issue: under
200, 200-999, 1000-2999, and 3000 and over.

| Read | Command | Read at (UTC) | Feeds |
|---|---|---|---|
| Pull requests and their timelines | `gh api graphql` search `repo:melodic-software/claude-code-plugins is:pr is:merged merged:<from>..<to>` in 12-hour slices, 25 a page, reading `createdAt`, `mergedAt`, `additions`, `deletions`, `author`, `headRefOid`, `reviews(first:40)`, `commits(last:1)` and `timelineItems(first:100)` of types `READY_FOR_REVIEW_EVENT`, `CONVERT_TO_DRAFT_EVENT`, `ADDED_TO_MERGE_QUEUE_EVENT`, `REMOVED_FROM_MERGE_QUEUE_EVENT`, `LABELED_EVENT`, `UNLABELED_EVENT`, `HEAD_REF_FORCE_PUSHED_EVENT`, `AUTO_MERGE_ENABLED_EVENT` | 2026-11-25 18:28 to 18:34 | band table, queue, ejections, reviews |
| Check runs on each merged head | `gh api repos/melodic-software/claude-code-plugins/commits/<headRefOid>/check-runs?per_page=100&filter=all` | 2026-11-25 18:35 to 18:44 | stage table, what-if table |
| Commits on each sampled pull request | `gh api graphql` `pullRequest(number:<n>){commits(first:100){nodes{commit{oid committedDate messageHeadline author{name user{login}}}}}}`, 20 a call | 2026-11-25 18:45 | rework rounds, base merges |
| Merge-queue CI runs, one day | `gh api --paginate repos/melodic-software/claude-code-plugins/actions/workflows/pr-require-checks.yml/runs?event=merge_group&created=2026-11-24T00:00:00Z..2026-11-24T23:59:59Z&per_page=100` | 2026-11-25 18:46 | queue run time |
| Merge-queue settings | `gh api repos/melodic-software/claude-code-plugins/rules/branches/main` | 2026-11-25 18:36 | queue settings |
| The issue's own query, re-run | `gh pr list -R melodic-software/claude-code-plugins --state merged --limit 300 --json additions,deletions,createdAt,mergedAt` | 2026-11-25 18:49 | comparison with the issue |

Check runs and commits were read for a stratified sample of 311 pull requests, not all 1,380: every
pull request of 1,000 lines or more (111), and 100 drawn at random (seed 18929) from each of the two
smaller bands. Medians were computed by script over those reads; none was counted by hand. The whole
run used about 330 REST requests and about 80 GraphQL points.

## Owner waits

Active time is open-to-merge time less the owner's waits. A wait is the union of:

- each interval the pull request was a draft: from opening to the first ready event when it opened
  as a draft, and from each conversion to draft to the next ready event;
- each interval it carried a hold label that only a person lifts: `do-not-merge`, `needs-human`,
  `security: outside-actor` or `provenance: untrusted` (`labelHolds` in
  [`merge-holds.mjs`](../../../.github/scripts/pr-merge/merge-holds.mjs)), from the labeled event to
  the matching unlabeled event, or to the merge.

`pr-verify-failed` is not a wait: a lane lifts it. 800 of the 1,380 pull requests had some wait; the
median wait is about 1 minute in every band but the largest, where it is 20. Two timelines held over
100 events and were read truncated.

## Open to merge by band

| Band | PRs | Raw median, min | Active median, min | 95% interval of the active median | Active at 60 min or less | Active p75 | Active p90 |
|---|---|---|---|---|---|---|---|
| under 200 | 871 | 44 | 38 | 35 to 41 | 577 (66%) | 77 | 162 |
| 200-999 | 398 | 79 | 65 | 55 to 76 | 192 (48%) | 126 | 208 |
| 1000-2999 | 81 | 129 | 106 | 69 to 135 | 29 (36%) | 176 | 291 |
| 3000 and over | 30 | 202 | 92 | 68 to 129 | 6 (20%) | 157 | 238 |
| all | 1,380 | 57 | 48 | | 804 (58%) | 103 | 188 |

The interval is a bootstrap of the median, 2,000 resamples with seed 18929.

The issue's own query, re-run, covers 2026-11-24T03:42Z to 2026-11-25T18:23Z and gives raw medians of
0.6, 1.0, 1.5 and 2.6 h on 161, 113, 22 and 4 pull requests, against the issue body's 0.9, 1.2, 1.8
and 4.1 h. The 7-day window above replaces it: it holds 30 pull requests of 3000 lines or more where
the last 300 hold 4.

Active median by who opened the pull request:

| Band | Owner session | Lanes App | Release | Dependabot |
|---|---|---|---|---|
| under 200 | 39 (n=445) | 72 (n=169) | 26 (n=213) | 142 (n=18) |
| 200-999 | 69 (n=294) | 124 (n=66) | 34 (n=35) | 56 (n=3) |
| 1000-2999 | 105 (n=68) | 164 (n=8) | 39 (n=5) | none |
| 3000 and over | 87 (n=29) | 238 (n=1) | none | none |

Release pull requests are 253 of the 1,380 and merge in a median 27 minutes, so they pull the
smallest band's median down. The stage and what-if tables below leave them out.

## Where the time goes

The stages are sequential, so on each pull request they add up to its active time exactly:

- **Rework**: from opening to the push of the head that merged, less owner waits. It holds every
  earlier head's CI and review, the fixes they asked for, and merges of `main` into the branch.
- **CI**: from that head's push (its first check run) to its first `CI Status` success. `CI Status`
  is the one required check and aggregates the test jobs and the two hosted review lanes
  ([Stages](README.md#stages)).
- **Gate wait**: from that `CI Status` success to the last time the pull request entered the merge
  queue, less owner waits. It holds pr-verify, the merge-risk rating and arming
  ([Merge authority](README.md#merge-authority)), an owner session's own merge step, and any
  ejected queue attempt.
- **Queue**: from that last entry to the merge.

Medians per stage, sampled pull requests, release pull requests left out, minutes:

| Band | n | Active | Rework | CI | of which test jobs | Code review lane | Security review lane | Gate wait | Queue |
|---|---|---|---|---|---|---|---|---|---|
| under 200 | 73 | 49 | 0 | 7 | 6 | 5 | 5 | 10 | 9 |
| 200-999 | 85 | 77 | 31 | 9 | 8 | 6 | 5 | 8 | 9 |
| 1000-2999 | 76 | 111 | 51 | 12 | 11 | 8 | 7 | 4 | 12 |
| 3000 and over | 30 | 92 | 48 | 17 | 11 | 9 | 10 | 8 | 12 |

Means of the same stages, which add up to the active mean:

| Band | Active | Rework | CI | Gate wait | Queue |
|---|---|---|---|---|---|
| under 200 | 74 | 22 | 17 | 32 | 11 |
| 200-999 | 123 | 74 | 15 | 22 | 13 |
| 1000-2999 | 152 | 98 | 22 | 20 | 16 |
| 3000 and over | 129 | 77 | 25 | 17 | 16 |

What grows with size:

- **Rework is most of the growth.** Its mean goes from 22 to 98 minutes. The mean number of fix
  commits pushed after opening, merges of `main` left out, is 0.6, 1.7, 2.5 and 7.5 by band, and a
  pull request's rework per fix commit has a median of 16, 29, 23 and 11 minutes. The bot-reviewed heads per pull
  request (a `github-actions` or Codex review) rise from 0.40 to 0.79, 1.14 and 1.70, and the owner
  session's review replies from 0.44 to 5.47. Each fix round re-runs CI and both review lanes.
- **Merges of `main` into the branch** rise from 0.12 per pull request to 0.69, 1.22 and 1.33. Each
  one is a new head, so CI and review run again. The branch rule has
  `strict_required_status_checks_policy: false`, so none is needed to merge.
- **Merge-queue ejections** hit 66 of 871 pull requests under 200 lines and 11 of 30 at 3000 or
  more. The reasons, over all bands: 123 failed checks, 39 conflicts, 21 manual, 3 branch
  protection, 2 timeouts. An ejected pull request takes a median of 54 to 142 minutes from its
  first queue entry to merge; one that is not ejected takes 9 to 12.
- **CI grows modestly**: the test jobs go from 6 to 11 minutes and `CI Status` from 7 to 17.
- **The review lanes on the merged head** take 5 to 10 minutes and run alongside the tests.

What does not grow with size:

- **The queue** is the merge group's own CI run. The queue builds up to 5 groups at once, merges 1
  to 5 at a time and waits at most 5 minutes for the minimum of 1 (`max_entries_to_build: 5`,
  `min_entries_to_merge: 1`, `min_entries_to_merge_wait_minutes: 5`, `grouping_strategy: ALLGREEN`).
  On 2026-11-24, 284 merge-group runs of `pr-require-checks.yml` took a median 9.6 minutes (p90
  14.7); 9 failed. The queue median of 9 to 12 minutes is that run.
- **Gate wait** shrinks with size for owner sessions, but lanes App pull requests wait a median 28
  minutes against 5 for owner sessions. The lanes App's median is 72 minutes even under 200 lines.

## Current practice for the slow stages

From `/discovery:research` run on 2026-11-25. Every accepted claim states what a publisher's own
documentation says; none measured a time saving, so they are cited as mechanisms, not as speedups.

- **Review rounds (rework).** Anthropic's Claude Code Review focuses a later automatic review on the
  changes since the last one, and keeps the earlier result for a push whose added and removed lines
  are unchanged
  ([Code review for pull requests](https://code.claude.com/docs/en/code-review-pull-requests)). It
  skips drafts and runs on open, on every push, or on request
  ([Code review](https://code.claude.com/docs/en/code-review)). GitHub Copilot's automatic review of
  new pushes and of drafts is opt-in
  ([Configure automatic review](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/request-a-code-review/configure-automatic-review)).
  Large diffs are split into parallel chunks on hunk boundaries by Qwen Code
  ([Code review](https://qwenlm.github.io/qwen-code-docs/en/users/features/code-review/)) and prism
  ([dshills/prism](https://github.com/dshills/prism)); ai-pr-review reviews only new commits on later
  pushes ([tag1consulting/ai-pr-review](https://github.com/tag1consulting/ai-pr-review)).
- **Merge queue and ejections.** GitHub removes a pull request from the queue on a failed check, a
  conflict with the base or a timeout, and a pull request that jumps the queue rebuilds those in
  progress; required checks must run on `merge_group` or the merge fails; build concurrency and the
  merge limits are settings
  ([Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)).
  A stack of pull requests enters the queue as one merge group
  ([Stacked pull requests are generally available](https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available/)).
- **CI time that grows with the change.** Nx runs only the tasks whose inputs a change touched
  ([Affected](https://nx.dev/docs/features/ci-features/affected)); Playwright splits a suite across
  machines with `--shard=x/y`
  ([Sharding](https://playwright.dev/docs/test-sharding)); `actions/cache` restores by key and
  prefix ([Dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)).
- **Waits between green and merge.** GitHub auto-merge merges once requirements pass, and on a
  merge-queue branch "Merge when ready" enqueues
  ([Automatically merging a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)).
  DORA measures change lead time from commit to production and recommends smaller batches
  ([DORA's software delivery metrics](https://dora.dev/guides/dora-metrics/)); that is not open to
  merge.

Open in the research: whether size itself drives time to merge. One study found no relation between
size and time to merge ([Kudrjavets et al.](https://arxiv.org/abs/2203.05045)); vendor benchmarks
claiming smaller is faster were not accepted. Here the relation is measured directly in the band
table, and the stage table locates it in rework rather than in CI or the queue.

## Ranked changes

Each change is one pipeline change and can be filed as its own issue. The effect is the active
median, in minutes, of the 264 sampled non-release pull requests (49, 77, 111 and 92 by band; 76
overall) with that change applied to each pull request's own timestamps:

- **A, no trailing base merge**: when a pull request's last commits are merges of `main`, the push
  of its last own commit stands. Only a trailing merge is removed, so this is a floor.
- **B, no ejection**: an ejected pull request's time from first queue entry to merge drops to its
  band's median queue time without an ejection.
- **C, size-flat CI**: each pull request loses its band's median CI excess over the under-200 median
  (0, 1, 5 and 9 minutes).
- **D, one fix round**: a pull request with two or more fix commits after opening keeps the rework of
  one. This is an upper bound: an incremental review removes only the rounds that new findings on
  unchanged lines cause.
- **E, lane gate wait**: a lanes App pull request's gate wait drops to the owner sessions' median of
  5 minutes.

| Rank | Change | Scenario | under 200 | 200-999 | 1000-2999 | 3000 and over | All |
|---|---|---|---|---|---|---|---|
| | Baseline | | 49 | 77 | 111 | 92 | 76 |
| 1 | Hosted review lanes re-review only the lines changed since the last reviewed head, so a fix round raises no new findings on unchanged code | D | 40 | 63 | 65 | 58 | 59 |
| 2 | Remove the cause of failed-check ejections: find which merge-group jobs fail on heads whose own `CI Status` passed, and make the pull-request run select the same tests the merge group does | B | 35 | 74 | 104 | 76 | 69 |
| 3 | `/source-control:pull-request ready` merges `main` into the branch only on a conflict or a check `main` has since fixed, as the merging policy already says of rebases | A | 49 | 73 | 101 | 86 | 69 |
| 4 | Find the event the lanes App pull requests' 28-minute gate wait waits on and arm them on it, not on a later sweep | E | 30 | 76 | 107 | 98 | 68 |
| 5 | Shard the selected test suites by selected-test count, so test wall time stays at the under-200 level | C | 49 | 76 | 106 | 84 | 74 |
| | 2, 3 and 5 together | A+B+C | 34 | 65 | 66 | 61 | 58 |
| | 1, 2, 3 and 5 together | A+B+C+D | 32 | 53 | 47 | 41 | 44 |

The ranks follow the effect on the three bands over target. The cause in change 4 is not yet
measured: the gate wait is measured, the part of it each of pr-verify, the merge-risk rating and
the pr-merge sweep holds is not, and the issue's first step is to split it.

## Verdicts

- **under 200: meets the target.** Active median 38 minutes (95% interval 35 to 41) on 871 pull
  requests, and 49 in the non-release sample. This band is the regression guard: a change filed
  from this list must not raise it above 60, and its issue re-measures it with the commands above.
- **200-999: misses by 5 minutes, path found.** Active median 65 (55 to 76) on 398. Changes 2, 3
  and 5 bring the sample to 65 from 77, and adding change 1 to 53.
- **1000-2999: misses, path needs change 1.** Active median 106 (69 to 135) on 81. Changes 2, 3 and
  5 reach 66; with change 1, 47.
- **3000 and over: misses, path needs change 1; the median is not yet stable.** Active median 92 on
  30 pull requests, but its 95% interval runs from 68 to 129, too wide to judge a change of under an
  hour. The issue's n=5 premise no longer holds over 7 days. Changes 2, 3 and 5 reach 61; with
  change 1, 41. Re-measure this band over 14 days before judging any change on it.

## Limits

- **Stage and what-if figures come from the sample**, which over-represents large pull requests by
  design. Band rows are unbiased within a band; the "all" row is not the window's.
- **Scenarios are not independent**, and their medians do not add: the combined rows are computed
  per pull request, not summed.
- **Commit dates stand in for push times** in the base-merge and fix-round scenarios.
- **pr-verify and the merge-risk rating are inside gate wait**, not split out: their runs start on
  `workflow_run` on `main` and carry no pull-request head, so they would need the
  `pr-verify-<pr>-<sha>-<verdict>` artifact listing ([`stage-order-baseline.md`](stage-order-baseline.md)).
- **Owner waits cover drafts and person-held labels only.** A session that leaves a pull request
  open and ready, waiting for the owner, counts as active.
