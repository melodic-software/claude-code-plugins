# Safety Rules

Use these rules before any mutating action, in every tier. Angle-bracket slots
(`<watched-owners>`, `<self-logins>`, `<merge-method>`) are filled from the
effective-configuration block in this skill's `SKILL.md`, which renders every key's resolved
value and its unset fallback.

## Role Boundaries

- Every queue run must acquire, heartbeat, and finally release its queue lease through the lease
  helper (`orchestration.md`, Concurrency Guard). A single-PR run uses the matching worker lease
  instead.
- Before any PR-specific refresh, review trigger, local fix, worker assignment, or cleanup, the
  queue orchestrator must also acquire and hold that PR's worker lease. Pass its token to guarded
  mutation and cleanup helpers, heartbeat it through the work, clean only that PR's worktree, and
  release it only after the result is integrated.
- The orchestrator may discover PRs, classify state, request guarded branch refreshes
  (`freshness.md`), post one guarded review-trigger comment per head SHA (`review-trigger.md`,
  when that module is configured), spawn workers, and report.
- A worker may only inspect and fix the single PR assigned to it.
- A worker must not refresh branches, post review triggers, merge, enable auto-merge, force-push,
  change GitHub settings, spawn more workers, or resolve any thread outside the constrained
  pre-push-outdated rule in `orchestration.md`'s Worker Contract.
- If two workers would touch the same checkout, source-of-truth repo, or shared generated file,
  the orchestrator must sequence the work or ask the user.

## Checkout And Push Invariants

- Reuse an existing clean worktree for a PR rather than creating a second checkout — reuse only
  when it is already on the target PR branch and `git status --porcelain` is clean; otherwise
  report it (`worktrees.md`).
- Re-check the PR head SHA immediately before editing and again immediately before pushing. Stop
  if it changed unexpectedly — someone else moved the branch.
- Honor `mutation_policy.branch_write_allowed`: never push, and never create a write-capable
  worker or refresh a PR head, when it is false.
- Head-ref uniqueness guard: two open PRs sharing one head repository/branch is a stop-and-ask —
  escalate, never guess which PR a push would update.
- Lease-protected removal: never remove a worktree without holding that PR's worker lease
  (`worktrees.md`).

## Allowed Without Asking

- Read PR metadata, review comments, checks, and Actions logs.
- Retry checks only when the failure is likely flaky, infrastructure-related, or already fixed by
  a new commit.
- Edit, commit, and push to the PR branch only for clear branch-owned CI failures or actionable
  bot-review findings when the snapshot allows writes to the head repository, including
  bot-authored branches when needed for a CI fix.
- Have the orchestrator request one guarded default-merge refresh for a behind-base PR using its
  snapshotted head SHA and the held PR worker-lease token (`freshness.md`).
- Have the orchestrator post one guarded review-trigger comment per head SHA through the
  durable-state gate in `review-trigger.md`, when that module is configured, passing the held PR
  worker-lease token.
- Create or reuse an isolated per-PR worktree for local fixes.
- Prune worktrees exactly per `worktrees.md` — global prune only for unleased clean merged/closed
  worktrees from a queue run holding the queue lease; an open PR's clean worktree only with
  `--pr`, its matching `--lease-token`, and `--prune-open-clean` before releasing that worker
  lease.

## Stop And Ask

- A human submitted `CHANGES_REQUESTED`, used explicit blocking language, or left an unresolved
  inline thread (see Human Comments below).
- A refresh, edit, commit, or push would write to an external-fork head outside
  `<watched-owners>`, even when maintainers are allowed to modify it. Read-only monitoring and a
  guarded review-trigger comment on the owned base repository remain allowed.
- The base repository is archived. Continue read-only monitoring, but ask the user before any
  repository lifecycle decision; GitHub mutations remain disabled.
- Feedback is ambiguous, product-level, architectural, or beyond the PR's stated scope.
- The failure appears unrelated to the branch.
- The fix belongs in an upstream source-of-truth repository (shared CI workflows, org-wide
  policy, a managed configuration sync) rather than the PR's own repo.
- The worktree is dirty, the head SHA changes while working, or permissions are missing —
  including a harness/runtime permission denial; see Harness Permission Layer below for how to
  tell that apart from a script-level gate denial before deciding how to react.
- A merge conflict appears. In default (safe) mode this is always a stop: report it as a blocker
  and take no resolution action. In worker or autopilot mode only, a textual/mechanical conflict
  (formatting, adjacent unrelated changes, both sides adding different items to the same list) is
  not an automatic stop: hand it off to a dedicated, fresh conflict-resolution worker per
  `orchestration.md`'s Merge Conflict Resolution section — never resolved by the worker that
  discovered it mid-fix-round, and never resolved inline by the orchestrator. In worker or
  autopilot, stop and ask only when that fresh worker finds the conflict genuinely semantically
  ambiguous (both sides made incompatible design/behavioral decisions about the same logic, not
  just textually overlapping edits) or when the same conflict recurs across repeated resolution
  attempts.
- A change would alter secrets, branch protection, repo settings, GitHub Apps, runners, billing,
  or organization policy.
- A branch refresh returns `403` or `422`, conflicts, lacks permissions, remains unchanged, or
  would require rebasing or force-updating.
- Durable review-trigger state is missing or ambiguous, or the configured reviewer does not
  engage after the one request allowed for a head SHA (`review-trigger.md`).
- Whether to merge a green dependency-manager PR; dependency acceptance is human judgment in
  every tier (`feedback.md`; the invariant is stated in `SKILL.md`).

## Verify Before Escalating Non-Convergence

Before reporting a blocker as real — and before raising a "this PR is not converging," "should
rounds be capped," or "should we pause the loop" question to the user — re-query GitHub and read
the actual content of every currently-unresolved review thread on the PR(s) in question. Never
escalate on unresolved-thread count or round number alone.

- Classify each unresolved thread: (a) a genuine duplicate — the same finding recurring after a
  fix that should have addressed it, real evidence of non-convergence; or (b) a new, distinct,
  code/line-cited finding — expected depth on complex or security-sensitive logic, not churn.
- Escalate a bounding/cap-policy question only when verification shows (a), or a finding that is
  structurally impossible to resolve (the check itself is external or non-deterministic). If
  every unresolved thread is (b) and each is individually fixable — a mechanical fix or a
  clearly-scoped judgment call — fix directly instead. A high round count alone is not evidence
  of non-convergence.
- This verification is required even when a sub-agent, advisor, or other second opinion reads
  round-count or metadata as a non-convergence pattern — that read is a hypothesis to test
  against actual thread content, never a conclusion to act on or escalate over.
- See the Fix-Round Cap in `orchestration.md` for the mechanical cap this verification gates.

## Guarded Mutation Wrappers

The two guarded mutations are invoked only by their pinned bare wrapper names —
`source-control-babysit-merge` and `source-control-babysit-resolve-thread` — never through an
interpreter-prefixed path. They are this skill's own deterministic authorization layer: they
encode exactly what worker and autopilot are allowed to do.

- Both wrappers **fail closed**: invoked without `--allowed-owners`, they exit `3` and refuse to
  act. The read-only forms are `source-control-babysit-merge owner/repo#42 --allowed-owners
  <watched-owners>` (merge-readiness gate) and `source-control-babysit-resolve-thread
  owner/repo#42 --allowed-owners <watched-owners>` (thread list).
- The merge wrapper mutates only with `--merge --expected-head <post-push-head-sha> --method
  <merge-method>`, and rejects `--allow-unpinned-head` outright — there is no unpinned merge. The
  expected-head pin semantics live in `SKILL.md`; do not re-derive them here.
- The merge CLI refuses a dependency-manager-authored PR absent `--allow-dependency`, and refuses
  to merge on an unprotected repository — zero required reviews AND zero required status contexts
  — when the PR author is not one of `<self-logins>`, absent `--allow-unprotected`. Both
  overrides are human decisions, never passed autonomously.
- The resolve wrapper's mutating forms are `--autonomous --resolve` (worker tier, constrained by
  the pre-push-outdated rule in `orchestration.md`) and `--resolve --include-human` (autopilot's
  addressed-thread widening).
- **Thread-pin pair rule.** Any `--thread-id` resolve must also pin both
  `--expected-comment-count <n>` and `--expected-last-updated <ts>`, read from that thread's
  `commentCount` and `lastCommentUpdatedAt` in the same list output used to vet it. The wrapper
  refuses a target whose live comment count or latest comment-edit timestamp no longer matches
  either pin, so a reply added or a comment edited after vetting blocks that thread instead of
  being silently swept in. A thread id alone is never enough (the live thread is re-fetched at
  execution time), and a comment count alone is never enough (an edit leaves the count
  unchanged).
- **Parse JSON, never trust exit codes alone.** Both wrappers emit structured JSON; confirm what
  actually happened from each target's `action` field. For a resolve, exit `10` is a reliable
  "nothing was resolved" signal (a stale pin refused, the thread was skipped, or the mutation
  failed), but exit `0` is not by itself proof of success for a given thread — it also covers
  list mode and a multi-thread run where some other thread resolved while this one did not.
  Treat a thread as cleared only when its own entry shows `"action": "resolved"`, and a merge as
  performed only when the merge output's `action` field says so.

## Harness Permission Layer

A permission denial can come from two different layers. Tell them apart before deciding how to
react — never retry or route around either one.

- **Harness/runtime permission denial.** The host runtime's own permission layer (its rules plus,
  in some runtimes, an auto-mode safety classifier) blocks a tool call before any skill script
  even runs; this is a policy decision made by the harness, not by this skill. Treat it as the
  "permissions are missing" Stop And Ask case above: do not retry the call, do not route around
  it with a different tool or approach, and report exactly what was attempted and that the
  harness blocked it.
- **Script-level gate denial.** A skill script or wrapper runs to completion and itself returns a
  deliberate non-ready or refused result — the merge wrapper reporting `ready: false` with a list
  of blockers, or the lease helper exiting `3` because the requested lease is already held by
  another run. This is expected, structured output from the script's own gate, not a permissions
  problem. React to the reported blockers or exit code per the relevant reference file; never
  bypass the gate and never retry as if it were a transient failure.

The harness layer is independent of, and sits above, the wrapper gates: it can deny a mutation
the wrapper gate has already proven ready and in-tier. That denial is an environment-level
ceiling this skill's own contract has no authority over — a normal, expected outcome to plan for,
not a bug in this skill, a stalled worker, or a reason to retry with broader permissions.

### Pinned-Command Degradation

When the runtime denies a guarded mutation that this skill's own gate already proved ready —
distinguishable because the wrapper itself never ran, so there is no wrapper exit code and no
`blockers` output to react to — degrade that one PR to the same outcome default (safe) mode
reports for a ready PR: mark it **"ready, awaiting human execution"** and surface the exact,
fully-argument-pinned command for the operator to run, using the bare wrapper name — never a
workaround, and never an interpreter-prefixed re-spelling of the command to dodge a narrow allow
rule.

For a merge:

```text
source-control-babysit-merge owner/repo#42 --allowed-owners <watched-owners> --merge --expected-head <post-push-head-sha> --method <merge-method>
```

For a thread resolve, never surface a bare `--autonomous` or `--include-human` resolve: both
re-fetch the live thread list and re-evaluate every eligible thread at execution time, so an
unpinned command could resolve a thread this run never vetted — one opened or changed after its
assessment. Pin each vetted thread individually (the wrapper accepts exactly one `--thread-id`
per invocation; issue one pinned command per thread) with the thread-pin pair rule above:

```text
source-control-babysit-resolve-thread owner/repo#42 --allowed-owners <watched-owners> --autonomous --resolve --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the unattended-worker case, or

```text
source-control-babysit-resolve-thread owner/repo#42 --allowed-owners <watched-owners> --resolve --include-human --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the autopilot case. This degradation is a successful, material finding to report, not a
failure and not a blocker to resolve — continue the rest of the queue exactly as if the mutation
had been refused by the wrapper's own gate. When this agent (or the operator) later checks
whether a deferred command actually acted, parse the JSON `action` field per Guarded Mutation
Wrappers above — never the exit code alone — before treating the thread as cleared or the merge
as done and re-running the gate.

## Never Do Automatically

- Merge in default (safe) mode, or merge through any path other than the pinned merge wrapper's
  gate.
- Enable auto-merge.
- Force-push.
- Rebase or force-update a PR branch as freshness maintenance.
- Change GitHub settings by hand.
- Post more than one review-trigger comment for the same head SHA.
- Auto-fix human feedback, or resolve a human-authored thread, outside autopilot's
  addressed-thread widening.
- Resolve any thread over a live, unaddressed finding.
- Make broad refactors just to satisfy a narrow bot comment.

## Human Comments

Classify every human comment, reply with evidence per the shared review discipline
(`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`), and surface it in the report — never
auto-fix human feedback, and never resolve a human-authored thread, outside autopilot's
addressed-thread widening. `CHANGES_REQUESTED`, explicit blocking language, and unresolved inline
human threads are stop-and-ask conditions until GitHub state resolves them (`feedback.md`).

## Comment Policy

Beyond the classification replies and follow-ups the shared review discipline requires, prefer
commits and concise reports over additional GitHub comments. The one-shot review-trigger comment
(`review-trigger.md`, when configured) is the only other proactive comment. Never impersonate
another tool or identity in a comment.
