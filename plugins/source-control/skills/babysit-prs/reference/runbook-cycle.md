# Operational runbook (engine-backed cycle)

Step-by-step cycle for queue and worker modes. Read [safety.md](safety.md) before mutating
anything; before dispatching workers also read [worktrees.md](worktrees.md) and the concurrency
guard in [orchestration.md](orchestration.md). Python-free safe runs follow [loop.md](loop.md)
instead of this runbook.

1. Acquire the deterministic lease for this run (queue scope for a full cycle, worker scope with
   `--pr` for a single PR), retain the token, and heartbeat it on a bounded cadence:
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/manage_babysit_lease.py" acquire
   --scope queue --state-dir <state-dir>` (add `--repo <owner/repo>` when sharding sessions per
   repo). On exit 3 either reclaim a provably dead holder with `--steal-stale` or skip; treat a
   token-mismatch heartbeat as lost ownership ([orchestration.md](orchestration.md)).

2. In queue mode only, while holding the queue lease, prune unleased clean merged/closed worktrees
   and reap expired worker leases:
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/prune_babysit_worktrees.py"
   --apply --root <worktree-root> --state-dir <state-dir>` and
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/manage_babysit_lease.py" reap
   --apply --state-dir <state-dir>`.

3. Run the snapshot with the tier's scope:
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/pr_queue_snapshot.py" --queue
   --author @me --owners <watched-owners> --state-dir <state-dir> --write-state`
   (the `@me` scopes discovery to your own gh login; when `babysit_self_logins` is non-empty and not a
   literal unexpanded token, append `--extra-self <self-logins>` — those extra posting identities join
   the self-suppression set independently of `--author`, surviving autopilot widening; when
   `babysit_intended_write_identity` is set and not a literal unexpanded token, append
   `--intended-write-identity <intended-write-identity>` so a wrong-self-login write surfaces as
   attribution drift; append review-trigger flags only when configured; `--pr owner/repo#N` (single PR)
   or `--repo <owner/repo-csv>` (sharded); drop `--author` only to widen — self-suppression no longer rides on it).
   Capture the prior cycle's `generated_at` per [cadence.md](cadence.md) before writing new state.

4. Decide per PR from the snapshot's `classification`, `needs_worker`, `recommended_cadence`, and
   `material_findings`: delegate a worker (only when `needs_worker` is true), act locally, report,
   back off, or escalate. Load [freshness.md](freshness.md) only when a branch is behind,
   [stuck-checks.md](stuck-checks.md) when a PR's `checks.stuck` is non-empty (escalate the
   routing, never auto-fix) **or** when `branch_freshness.state == "conflicting"` — that file also
   covers the inverse case, where a conflicted PR's `pull_request` lanes are never scheduled and the
   check list is short rather than stuck, [feedback.md](feedback.md) and [review-trigger.md](review-trigger.md)
   only for feedback or review gates, the fan-out gate in [orchestration.md](orchestration.md) only
   before assigning workers, and [cadence.md](cadence.md) only before interpreting a cadence state.

5. Process stale-branch refreshes and review-trigger posts as orchestrator-only actions before
   assigning workers; each is terminal for that PR's cycle until a later snapshot observes its new
   head ([freshness.md](freshness.md), [review-trigger.md](review-trigger.md)).

6. In worker mode, after a worker's fix is pushed and its checks are green, take a fresh post-push
   snapshot (or use the exact pushed commit after the worker has vetted that commit), then run the
   merge gate with `--merge --expected-head <post-push-head-sha>` only when it reports ready. Never
   reuse the pre-worker snapshot pin after the head moves — except a lane-pinned invocation
   ([safety.md](safety.md), "Lane-pinned merge authorization"), which reports the moved head instead
   of re-pinning, at every merge-capable tier. Resolve pre-push-outdated bot threads that block the
   gate — once the agent has confirmed they are not security/P1 — as a per-thread vetted loop: one
   `--autonomous --resolve --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>`
   call per thread, pins taken from the same snapshot that vetted it. `--autonomous --resolve` refuses
   a bulk (no `--thread-id`) call, so the comment-state pins are always enforced (a reply or edit
   after vetting blocks the resolve). Those pins do NOT catch displacement — a push that flips
   `isOutdated` while the comment count and last-updated still match is still resolved — so keeping
   such a thread unresolved rests on the pre-push-outdated agent-discipline rule, with the
   machine-enforced fix tracked in #571. In autopilot, after addressing the findings, additionally
   resolve AI-review and human threads with `--resolve --include-human`, then run the same pinned
   merge gate — the gate is never bypassed. After any `--resolve` run, parse its JSON output
   (per-thread `action`, and `resolvedCount`) before re-running the merge gate.

7. After each PR is integrated, prune only that PR's clean worktree with `--pr`, `--lease-token`, and
   `--prune-open-clean`, delete its local feature branch on merge, then release its worker lease.
   Never globally prune open-PR worktrees. Release the queue lease in finally-style cleanup.

8. Schedule the next wake per the cadence contract in [loop.md](loop.md) §5.3.
