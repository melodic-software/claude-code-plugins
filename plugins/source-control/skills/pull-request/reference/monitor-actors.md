# 3.0 Expected PR actors and merge readiness

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there.

**Before polling, know who you're waiting for.** The [readiness checklist](readiness.md) is the authoritative registry of expected PR actors: CI workflows, security scanners, AI reviewers, and comment-only bots. Read it before starting the monitoring loop.

**Key principle: "no comments" ≠ "ready to merge."** An empty comment list may mean reviewers haven't posted yet. The readiness checklist's **cooldown period** (minimum 2 minutes after the last check-run completion or comment arrival) stops monitor declaring readiness before all actors post.

**Bounded autonomy: monitor does not merge.** It evaluates, classifies, and recommends; merging is Phase 4. In `full` mode the readiness gates are checked automatically, never relaxed. Phase 4 merges or enqueues without asking only under [merge.md](merge.md) §4.2.1: once the PR is `CLEAN` and the AI review checks have passed on the head commit, with no strategy flag behind a merge queue. Every other merge waits for the user's approval (`/source-control:pull-request merge` or a manual merge). The merge command and its flags are [merge.md](merge.md) §4.2's; `--auto` always carries `--match-head-commit`.
