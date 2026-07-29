# Autopilot tier

What the `autopilot` tier does per PR, what "every PR" excludes, and which scopes it widens.
The tier's place in the autonomy matrix stays in this skill's `SKILL.md`; the operative merge and
thread-resolution commands stay in [safety.md](safety.md). This file restates neither.

`autopilot` is a deliberate, set-aside power-user tier for a **solo owner** who wants the queue
driven to zero — not the default, and not for a repo with other human reviewers whose feedback
must not be steamrolled. Its purpose is to never get stuck saying "nothing I can do": it
processes every PR, fixes what it can, and escalates only the specific PRs that genuinely need
a human. Per PR, in its own fresh worker, autopilot:

1. Fixes every issue it can — failing CI, mergeability, actionable review findings —
   researching a fix from authoritative sources before conceding, and pushing to the PR branch.

2. Addresses each open review thread, then resolves it through the guarded resolve-thread wrapper
   (`--resolve --include-human` — bot, AI-review, and human threads alike); the exact command is
   the single home in [safety.md](safety.md). The order is
   load-bearing: **address the finding first, then resolve.** A thread is resolved only because
   its concern is fixed or confirmed stale — never to clear the merge gate over a live concern.
   After running, parse the JSON output and confirm each addressed thread's entry shows
   `"action": "resolved"` before treating it as cleared — never the exit code alone.

3. After the worker's final push, takes a fresh post-push snapshot (or uses the exact pushed
   commit after vetting it), then merges on that post-push head through the pinned
   `source-control-babysit-merge` gate once it proves the PR ready. The exact command — and the
   `--autopilot-merge-tier` flags the enabled tier layers on so an enabled config never merges
   via the base path — is the single home in [safety.md](safety.md). Never
   reuse the pre-worker snapshot pin after a push — except a lane-pinned invocation ([safety.md](safety.md),
   "Lane-pinned merge authorization"), which reports the moved head instead of re-pinning. The gate is never bypassed; if a PR cannot be made ready, autopilot reports that one PR and moves on.

"Every PR" means every PR: the orchestrator's own priority judgment is never grounds to leave
a queue member untouched. The only permitted exclusions are the deterministic ones — lease
contention, the owner allowlist, `mutation_policy.branch_write_allowed`, and the `needs_worker`
delta gate skipping a PR that has not materially changed since it was last handled. A PR the
coordinator judges lower-priority still gets its cycle; it is sequenced, never silently dropped
from the fan-out.

**Draft PRs** are in scope, not exempt. Its worker assesses whether the draft's work is
actually complete: if so, mark it ready for review (`gh pr ready`) and continue through the
normal fix/resolve/merge steps in the same cycle; if it is genuinely still in progress, leave
it draft and report why — that is a real escalation with a reason, not a silent skip.

Autopilot keeps every cross-tier invariant in `SKILL.md` — including dependency hold-merge. It
widens *author* scope (all authors under the watched owners) and *thread* scope
(`--include-human`); it does **not** widen the owner allowlist, and it does not gain force-push,
`--admin`, or settings powers — those still escalate. Run it looped:
`/loop 15m /source-control:babysit-prs autopilot`.
