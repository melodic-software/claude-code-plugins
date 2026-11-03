# 3.0.5 Loop-aware monitoring (self-termination support)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

When `/source-control:pull-request monitor` runs in a loop (auto-created by 3.0.1 or user-created via `/loop`), each iteration is lightweight and self-terminating. Runs **after** 3.0.1 on every iteration.

**Terminal state pre-check (MANDATORY first action on every iteration):** read the PR's state ([GitHub](../../../reference/providers/github/pull-request/monitor.md#read-pr-state)).

| State | Action |
|-------|--------|
| `OPEN` | Proceed to 3.1 monitoring loop as normal |
| `MERGED` | Output final report (see below), self-terminate the loop |
| `CLOSED` | Output final report (see below), self-terminate the loop |

**Readiness-pass check (OPEN PRs only):** if the previous iteration already presented "All readiness gates passed. Recommend merge." and nothing new has happened since (no check-run completions, comments, or pushes), self-terminate the loop with the protocol below; further polling adds nothing the user needs to merge. After a later push, the next `/source-control:pull-request monitor` invocation re-creates the loop via 3.0.1.

**Self-termination protocol** (when PR is MERGED or CLOSED):

1. Output a brief completion message:

   ```text
   PR #N: MERGED. Monitoring complete. Stopping watch.
   ```

2. Take the task id this session recorded when it armed the watch for this PR ([§3.0.1](monitor-auto-watch.md) step 4), not a `TaskList` lookup
3. If this session holds a live watch for the PR, call `TaskStop <task_id>` to kill the background watch process, and do not re-arm it at the deadline notice
4. If it holds none (manual invocation, or the watch already exited, stopped, or reached its deadline): skip steps 2-3 and continue to step 5
5. In a cloud session that subscribed to this PR's activity ([§3.0.0](monitor-cloud-poll.md)), unsubscribe

**Minimal output for no-change iterations.** When the Monitor watch emits nothing and there are no new CI state changes or comments since the last check, output a single status line:

```
PR #N monitoring: OPEN | CI: 3/8 complete | Comments: 0 new | Next check in ~2m
```

This keeps context cost to ~50 tokens per iteration instead of a full report.
