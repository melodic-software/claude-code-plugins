# 3.0.6 Multi-PR scan (after readiness-pass, merge, or close)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

When current-PR monitoring ends (readiness gates pass, PR merged, or PR closed), scan for other open PRs needing attention before going idle: list the open PRs with number, head branch, title and `statusCheckRollup` ([GitHub](../../../reference/providers/github/pull-request/monitor.md#list-other-open-prs)).

For each open PR found, report a one-line status:

```text
Other open PRs:
  #101 feat/add-auth: 2 failing checks, 1 unresolved comment
  #103 fix/null-check: all checks green, awaiting review
```

**`statusCheckRollup` pitfall: a running check has `conclusion: ""` (empty string), not `null`.**
The obvious "did anything fail" filter, `select(.conclusion != null and .conclusion != "SUCCESS")`,
therefore matches every **in-progress** check and reports running CI as failures. Select the values
you mean, never the complement:

```bash
# failures only
--jq '[.statusCheckRollup[] | select(.conclusion=="FAILURE" or .conclusion=="TIMED_OUT" or .conclusion=="CANCELLED")]'
# still running
--jq '[.statusCheckRollup[] | select(.status!="COMPLETED")]'
```

**Constraint: Monitor watches are branch-locked.** Monitor MUST run in the session that owns the branch ([§3.5](monitor-integration.md)); scanning is READ-ONLY, and you cannot arm a watch for a PR on another branch from this worktree. Report status and suggest: *"Switch to the worktree for `<branch>` to monitor PR #N."*

**When NO other open PRs found:** report `No other open PRs need attention.` and let the session idle.

**Monitor does the work; it does not report and wait.** Evaluate comments (explore, research, classify), react, reply, fix VALID findings, and push. Every push in this phase is `bash "<skill-dir>/scripts/push-branch.sh" --pr <pr_number>` (plus `--dir <checkout>` for a fork head in a lane), never a bare `git push`, so a lane's push goes through `lane-push.sh` ([ready-for-review.md](ready-for-review.md) 2.5.4). Pause for user input only at explicit decision gates: a CI fix with multiple viable approaches, and merge confirmation. Do not ask whether to start evaluating; the invocation answered that. Run the full 3.1-3.4 workflow on every iteration with state changes.
