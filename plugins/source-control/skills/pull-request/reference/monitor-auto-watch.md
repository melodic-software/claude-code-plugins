# 3.0.1 Auto-watch setup (Monitor tool)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

**Every monitor invocation ensures a live event watch exists, and every watch is re-armed at its deadline.** Runs right after 3.0.0, before terminal state checks, CI polling, and comment processing.

1. Resolve PR identity into `PR_NUMBER`, `OWNER` and `REPO` ([GitHub](../../../reference/providers/github/pull-request/monitor.md#resolve-pr-identity))
2. Check whether this session already holds a live watch for this PR: a task id from its own step-4 arming call for `PR #$PR_NUMBER CI + comments`, with no exit line, deadline notice, stop, or `--resume` since. Do not look the watch up with `TaskList`: it is not offered in every session (record below), and a watch armed before a `--resume` is gone though the transcript still shows its id.
3. **If this session holds a live watch for the PR** → skip (watch already active). Proceed to 3.0.5
4. **Otherwise** → arm the watch:

   ```text
   Monitor(
     description: "PR #<N> CI + comments",
     timeout_ms: 1800000,
     command: <poll script below>
   )
   ```

   **Re-arm at the deadline.** On the deadline notice, if the PR is still `OPEN` and readiness has not passed ([§3.0.5](monitor-self-termination.md)), first run the poll script once through Bash with `SNAPSHOT_FILE` set to a path in the scratch directory: it writes the checks there in the format the watch reads, then exits. Never write or edit the snapshot by hand; the watch refuses a file the script did not write. Then arm the watch with this same call, `BASELINE_FILE` set to that path (empty if the snapshot run exited non-zero), and finish the full iteration (step 5). Starting from that snapshot, the watch emits a check that finishes after the read exactly once, and does not re-report one already finished. The iteration covers anything else that landed between the deadline and the new watch: the new watch reports only comments posted after it starts, and its first poll records the review-thread count without emitting it. With no snapshot (the first arming), the first poll only records the checks.

   We pass the Monitor deadline maximum on every arming call and re-arm on the deadline notice for as long as the PR needs watching.

   - **Pointer**: when you need the Monitor deadline's default, its maximum, the lower cap in a non-interactive run, or what happens at the deadline, fetch [Monitor tool](https://code.claude.com/docs/en/tools-reference#monitor-tool) live.
   - **As of**: 2026-10-10
   - **Recheck trigger**: the Monitor tool section changes its deadline or its re-arm notice, or a release note names a Monitor input.

   A single-prompt `-p` run accepts the arming call's `timeout_ms` and clamps it to the non-interactive cap rather than rejecting it (Claude Code 2.1.312, [#6877 probe](https://github.com/melodic-software/claude-code-plugins/issues/6877)), so the same arming call and re-arm rule apply.

   - **Pointer**: the `-p` probe result (Claude Code 2.1.312), in [Claude Code releases, Probes](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/upstream/claude-code.md#probes); the run is on [#6877](https://github.com/melodic-software/claude-code-plugins/issues/6877).
   - **As of**: 2026-10-28
   - **Recheck trigger**: the Monitor tool section changes the non-interactive cap, or a release note names the Monitor deadline.

   Source conflict: the Claude Code 2.1.271 changelog entry and the Monitor tool section disagree on which inputs a command watch accepts. We follow the live tool schema: no `persistent`, an explicit `timeout_ms`.

   - **Pointer**: when you need the inputs a command watch accepts, fetch the 2.1.271 entry of the [Claude Code changelog](https://code.claude.com/docs/en/changelog) and [Monitor tool](https://code.claude.com/docs/en/tools-reference#monitor-tool) live.
   - **As of**: 2026-10-10
   - **Recheck trigger**: the Monitor tool section documents `timeout_ms` for command watches or mentions `persistent`.

   The step-2 check rests on this session's own arming record, not on a task-list lookup, because the task-tracking tools are not offered on every model.

   - **Pointer**: when you need which models and sessions get `TaskList` and how to opt in, fetch [Task tool availability](https://code.claude.com/docs/en/tools-reference#task-tool-availability) live.
   - **As of**: 2026-10-10
   - **Recheck trigger**: the Task tool availability section changes which sessions get the task tools, or a release note names task-tool gating.

   The poll script, passed inline in the `command` parameter, is the REST poll in the provider
   reference ([GitHub](../../../reference/providers/github/pull-request/monitor.md#poll-checks-over-rest)).
   Set `PR_NUMBER=<N>` at its top, and `INTERVAL` above its default 60 when other watchers run,
   per the [API budget](../../../reference/providers/github/README.md#api-budget); it resolves
   `OWNER` and `REPO` itself. Its contract:

   - Polls every `INTERVAL` seconds and exits 0 with `PR #<N> <state> — watch complete` once the PR is
     merged or closed.
   - Exits 2 with a `RATE-LIMITED` line on a rate-limit error. Re-arm only after the wait the
     [API budget](../../../reference/providers/github/README.md#api-budget) sets.
   - Emits one `name: bucket` line for each check that newly reaches `pass`, `fail`, `skipping` or
     `cancel`, from a REST read that reports the same rows and buckets as the CLI's checks list,
     commit statuses included.
   - Emits a `COMMENT`, `INLINE-COMMENT` or `REVIEW` line for each new item on all three review
     surfaces (issue-level comments, inline review comments, review bodies), and advances its
     watermark only when every fetch succeeded, so a transient failure never skips a comment.
   - Every 4th poll (about 4 minutes) runs the Gate 7 thread read through
     `<scripts-dir>/source-control-review-threads` and emits `REVIEW-THREADS unresolved=<n>` when
     the unresolved count, or `THREADS_UNPROVEN`, changes. Resolving a thread moves no check and
     posts no comment, so the other reads never see it.
   - It records the thread count on its first poll, and the checks as the baseline on the first poll
     whose check read succeeds, unless `BASELINE_FILE` names a snapshot the script's snapshot run wrote. With one, the
     snapshot is the baseline: the first successful checks read emits a check finished in the live
     read but not in the snapshot, and nothing else. A `BASELINE_FILE` that is unreadable or lacks
     the snapshot marker emits `BASELINE-UNREADABLE <path>` and records only; run a full checks scan when it wakes you. A poll
     whose check read fails (any call in the read errors) keeps the baseline and emits no check lines.

   Capture the returned task id. Report: `Monitor watch armed (task <id>, PR #<N>). Fires on CI check completion, new comments, and review-thread count changes. Stop with TaskStop <id> or end session; re-armed at each deadline.` Keep that task id: step 2 and §3.0.5 check it.

5. Proceed with the current monitoring iteration

**Why Monitor over fixed-interval cron:** a cron fires every N minutes regardless of PR activity; Monitor fires only when the filter emits, typically 5-15 times per PR lifecycle, with zero request cost while idle.

**Re-arm after `--resume`:** Monitor is session-scoped and does NOT restore on `--resume`. In a new or resumed session, any `/source-control:pull-request monitor` invocation's §3.0.1 idempotency check (step 2) finds no watch and re-arms.
