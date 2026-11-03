# 3.1 Monitoring loop (per-push)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there. Every push and every pause for input in this phase follows the phase-wide rules in [§3.0.6](monitor-multi-pr-scan.md) ("Monitor does the work").

**PR number**: resolve once at phase entry from the checked-out branch, naming the branch explicitly if multiple PRs are open against this checkout ([GitHub](../../../reference/providers/github/README.md#resolve-a-pull-request)). Capture it in a shell var and pass it explicitly to every later checks or PR read in this phase.

After each push, run this loop until convergence (**every** check in a terminal state + all comments addressed):

1. **Mergeable pre-check (MANDATORY before polling):** read the PR's `mergeable` and `mergeStateStatus` FIRST ([GitHub](../../../reference/providers/github/pull-request/monitor.md#read-mergeability)). If `mergeable == "CONFLICTING"`, GitHub will NOT trigger workflows: integrate the default branch (merge-forward first, per the stale-branch recovery rule in [§3.2](monitor-ci-failures.md)), resolve conflicts, push, and restart the loop. Proceed to CI polling only when `mergeable == "MERGEABLE"`. **Never blame the platform for missing CI runs before checking this.**
2. **Poll CI:** wait on the [§3.0.1](monitor-auto-watch.md) Monitor watch (60s, the standard cadence), or in a cloud session on the [§3.0.0](monitor-cloud-poll.md) background poll, and act when it emits. Never wait in a foreground `sleep` or `until` loop. The CLI's checks list is for a one-off read only, never a loop ("Polling CI from more than one worker" below). Never a blocking checks watch; before the first wait, report each pending job as queued or running per "Waiting on a pending check" below. **Wait for ALL checks to reach a terminal state** (pass/fail/skipped) before suggesting merge, no exceptions, regardless of PR type. Never merge while any check is pending or in_progress. **Before waiting on review lanes for a push that merged the default branch,** apply the remerge-diff test in B2 of the per-iteration checklist in [monitor.md](monitor.md#per-iteration-monitoring-checklist-on-every-ci-or-comment-event), which passes only on fully empty output: when it passes, the latest productive review on the pre-merge head stands and no local substitute review is needed, but the terminal-state wait above still applies to every check, the re-run lane checks included; when it fails or cannot be computed, wait and substitute as usual
3. **Check for new comments:** on each poll, also fetch new review comments (the inline review-comment surface, paginated; [GitHub](../../../reference/providers/github/README.md#review-surfaces))
4. **Process comments immediately:** if a bot comments while CI is running, start evaluating/researching it now
5. **On CI failure:** route to 3.2 (research-driven fix)
6. **On new comment:** route to 3.3 (evaluate + respond)
7. **After any fix push:** restart the loop (new push = new monitoring cycle)

**One fix round per head, including a delegated one.** Evaluating findings as they arrive (steps 4 and 6) is not dispatching a fix for each. When a worker does the fixing, hold the brief until every check and every reviewer on the current head is terminal ([§3.3.2](monitor-comments.md) step 0), then send one brief with all the head's findings: each failing check with its log excerpt, each unresolved review thread, and any independent verifier's failed criteria. A brief sent while a check or reviewer is pending leaves the late finding for a second round and push, each paying again for context and a full CI run. Repeat only when the new head produces new findings.

## Polling CI from more than one worker

When more than one worker polls CI under the same token (parallel PR monitors, babysit-prs workers,
subagents each watching a PR), read the PR and its checks over REST instead of the CLI's
GraphQL-backed checks list (a blocking watch included) or PR view. The §3.0.1 poll script is that
REST read: its state check and CI block (the `head_sha` read through `cur_checks`) run standalone
with `OWNER`, `REPO`, and `PR_NUMBER` set
([GitHub](../../../reference/providers/github/pull-request/monitor.md#poll-checks-over-rest)).
They emit one `name: bucket` line per check with the same rows and
`pass|fail|pending|skipping|cancel` buckets the CLI's checks list reports, and they always read
commit statuses, which the check-runs endpoint omits, so every bucket predicate above works
unchanged. The Monitor watch always uses this read, since babysit-prs arms one watch per PR; a
one-off read in a single session may keep the CLI's checks list, but a wait never uses a blocking
watch (see "Waiting on a pending check" below).

Why: the CLI's checks list and PR view query GraphQL, and concurrent workers under one token have
hit GraphQL secondary rate limits. GraphQL and REST have separate rate budgets, so REST polling
leaves the GraphQL budget for calls with no REST equivalent, such as review-thread resolution; the
concurrent-request ceiling is shared, so REST polling does not raise it. The figures, their sources and the recheck trigger are in the
[GitHub provider reference](../../../reference/providers/github/pull-request/monitor.md#why-polling-uses-rest).

## Waiting on a pending check

Any wait longer than one read is a REST poll on a fixed schedule, never the CLI's blocking checks
watch, whatever the worker count. That watch re-runs its GraphQL query on a short fixed interval
until every check settles
([GitHub](../../../reference/providers/github/pull-request/monitor.md#wait-on-a-pending-check)), so its cost grows with the wait's length, not with how much
changes; one session watching a job in a saturated self-hosted queue exhausted the account's
GraphQL limit before the job started. Poll with the §3.0.1 REST read at the monitor cadence: 60s in
the Monitor watch, 60-90s in the cloud background poll (§3.0.0), and never faster while every
pending check is queued.

Before the first wait, split `pending` into **queued** and **running**, which the bucket cannot
tell apart: every status short of `completed` (`queued`, `in_progress`, `waiting`, `requested`,
`pending`) lands in `pending`. Read the unfinished Actions jobs for the head SHA instead, one line
per job with its name, status, labels and creation time
([GitHub](../../../reference/providers/github/pull-request/monitor.md#list-unfinished-jobs-for-the-head)).

A `queued` job has no runner yet, and its `labels` are its `runs-on` set. Report it as queued, with
its labels and its age since `created_at` (`test: queued on self-hosted,linux for 41m`), never as a
slow job. When the token can list runners (`GET /repos/{owner}/{repo}/actions/runners`, or
`GET /orgs/{org}/actions/runners` for an org pool; both need admin access), add the pool's
occupancy for that label set. Count the runners whose `labels[].name` include every job label: the
ones with `busy` true over the ones with `status` `online` (`9/9 busy`). A non-admin token gets a
403 there; report `runner capacity not readable with this token` rather than guessing. A check that
is not an Actions job (an app's check run, a commit status) has no job record, but its check-run
`status` still separates `queued` from `in_progress`, without a label.

The states call for different action, so the report names which one it is:

- **Running** (`in_progress`): the wait comes from the change and its tests. Keep polling; a job well
  past its usual duration is worth opening its log.
- **Queued behind a busy pool:** the wait is runner-fleet capacity, and nothing on the branch
  shortens it. Keep the cadence above, report the queue state when it changes rather than every
  poll, and raise capacity with whoever owns the pool instead of touching the change.
- **Queued with no online runner for the label:** nothing will pick it up. Route it per the
  babysit-prs [stuck-checks reference](../../babysit-prs/reference/stuck-checks.md)
  (`stuck_queued`). Age past the stuck threshold routes it there only when occupancy is unreadable
  or shows a free online runner matching the label: a job queued behind a busy pool stays a
  capacity report however long it waits (a 63-minute queue on `9/9 busy` is still capacity).

The claim, basis and recheck trigger for this section are in the
[GitHub provider reference](../../../reference/providers/github/pull-request/monitor.md#evidence).

Compare triggered workflows against the expected set from Phase 2.5. Flag mismatches.

**When ANY check shows `fail`, ALWAYS read actual logs before classifying.** Use the prioritized fetch chain. The CLI's failed-log view is the LAST resort: it truncates at the CLI display layer ([GitHub](../../../reference/providers/github/pull-request/monitor.md#fetch-failed-logs)). The REST API path returns complete logs:

```bash
# Tier 1 — Annotations API (path/line/level/title/message — fix-location data)
# Sometimes alone is enough to classify (lint failures, type errors)
bash "<skill-dir>/scripts/fetch-annotations.sh" <pr-number> --failed

# Tier 2 — Full failure ZIP via the REST API (complete, untruncated). When the
# ${user_config.fetch_logs_max_bytes} option is a number other than the 52428800
# default (not empty, not a literal unexpanded token), append
# --max-bytes ${user_config.fetch_logs_max_bytes}
bash "<skill-dir>/scripts/fetch-failed-logs.sh" <run-id>
```

Tier 3, the LAST RESORT interactive eyeball, is the CLI's failed-log view grepped for `##[error]`; it TRUNCATES on large logs ([GitHub](../../../reference/providers/github/pull-request/monitor.md#fetch-failed-logs)).

**Grep CI logs for `##[error]` annotations first, not `grep -i "error\|fail\|..."`.** GitHub Actions marks real errors with `##[error]`; a broad keyword grep matches cleanup steps, variable names, and incidental output (e.g., "Bad credentials" from a token cleanup step when the real error is a workflow validation failure). Fall back to broader searches only if `##[error]` returns nothing.

**Stop at the first complete picture.** Tier 1 annotations usually answer "what failed in this job?"; escalate to the Tier 2 full ZIP only when they don't pinpoint the cause.

## Inline vs subagent dispatch decision

Log work runs inline in the main session for fast classification, or in a CI-log-audit subagent (when your environment provides one) for verbose audits. Choose by uncertainty + token budget:

| Situation | Path | Why |
|---|---|---|
| Single failing check with a clear `##[error]` marker | **inline** Tier 1 → Tier 2 | The annotations + full-ZIP path is ~3-5K tokens; the agent needs the result NOW for the next action. Subagent overhead buys nothing |
| Default `fetch-failed-logs.sh <run-id>` (errors+warnings) | **inline** | Same as above |
| `--raw` mode (full ZIP dump) | **subagent** (or read selectively) | 50-500K tokens that pollute main context with content the agent only needs to grep through |
| `--audit` mode (groups + timing + suspicious patterns) | **subagent** | Verbose multi-section output |
| "Why did this PR pass when something looks off?" | **subagent** | Cross-job mask detection, perf-vs-baseline comparison, annotation-gap analysis |

**Why not a subagent for everything:** the default mode's 3-5K-token output IS the answer the agent acts on, so a subagent for a single-response classification only adds overhead. A subagent earns its cost only when (a) verbose output would pollute main context, (b) persistent memory pays off, or (c) work runs in parallel. No audit subagent available → audit inline with the bundled script's `--audit` flags.

**Never guess at failure causes.** Common always-on-review workflow failures and their log signatures:

| Log signature | Meaning | Action |
|--------------|---------|--------|
| `Workflow validation failed` on an OIDC-based review action | PR modifies the workflow file, and OIDC requires the file to match the default branch | Informational. Expected when the PR touches that workflow |
| Usage/quota exhaustion messages (e.g. `out of extra usage`) | The review bot's subscription limit | Informational. Report accurately, wait for reset or merge without the second review |
| `error_max_turns` or similar truncation | Reviewer ran out of turns before completing | Informational. The review may be incomplete; check whether a comment was posted |
| OIDC / authentication errors | Token-exchange failure | Informational. Often intermittent; retry or classify |
| Actual code/tool errors | Real failure | Investigate |

Report the **exact error message** from logs, not a classification label.
