# 3.5 Monitor integration

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

The monitor phase arms a background watch via [§3.0.1](monitor-auto-watch.md) and re-arms it at each deadline; the user does NOT need to invoke `/loop`.

**Where to run it: the same session that owns the branch.**

Monitor MUST run in the session that created the PR, because:

1. Monitor writes to the PR branch (pushes CI fixes, rebases, posts comments)
2. Writing requires being checked out on that branch
3. Git enforces one-branch-per-worktree, so no second session can check out the same branch
4. Therefore: monitor runs in the session that owns the branch

```text
Session A: feat/feature-x → create PR → /source-control:pull-request monitor (arms watch) → keep working or idle
Session B: feat/feature-y → different branch, different worktree → code the next thing
```

Watch notifications arrive between turns; mid-response, a notification queues until your turn completes.

**For read-only status checks from any session:** use `/source-control:pull-request status`, which only calls `gh` commands and needs no branch checkout.

**Key behaviors:**

- **Self-termination on merge/close/readiness-pass:** the poll script exits on MERGED/CLOSED; `TaskStop` also fires from monitoring logic
- **Zero cost during idle periods:** Monitor fires only when the filter emits
- **Full monitoring on state changes:** when a check run completes or a new comment lands, the emitted line wakes the model and the full 3.1-3.4 logic runs
- **Session-scoped:** the watch terminates when the session exits; no orphaned background processes. It does not restore on `--resume`. §3.0.1's idempotency check re-arms it
- **Manual cancel:** "stop the PR monitor" or `TaskStop <id>`

The non-restore claim is verified 2026-09-06 against Claude Code 2.1.263 and
[Run prompts on a schedule](https://code.claude.com/docs/en/scheduled-tasks#limitations), which
states that resuming restores unexpired recurring tasks and pending one-shots, and that
"Background Bash and monitor tasks are never restored on resume." Recheck when that page stops
carrying that sentence, or when a release note names Monitor or resume behavior.

**Cloud sessions (`CLAUDE_CODE_REMOTE=true`):** [§3.0.0](monitor-cloud-poll.md)'s baseline poll handles event delivery, with the PR-activity subscription waking the session early on reviews and failed checks. Check `CLAUDE_CODE_REMOTE` before arming.

**`/loop` fallback:** when Monitor is unavailable, `/loop 2m /source-control:pull-request monitor` gives the same coverage at a full model turn per interval. Monitor is the default for active CLI sessions.
