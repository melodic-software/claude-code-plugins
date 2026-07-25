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
  when `git status --porcelain` is clean and its `HEAD` is the true PR head (the head assertion
  below), whether it is checked out on the PR branch or in detached HEAD because the branch is
  locked elsewhere; otherwise report it (`worktrees.md`).
- **Assigned-worktree head assertion.** Before any merge, edit, or push, resolve the assigned
  worktree's `HEAD` to a commit and assert it equals the true PR head — `gh pr view <N> --json
  headRefOid` (authoritative for same-repo and fork PRs; equal to a freshly re-fetched
  `origin/<headRefName>` for a same-repo PR). This holds whether the worktree is on the PR branch,
  in **detached HEAD** (the branch is checked out in a sibling worktree, or lives in a foreign dev
  worktree outside `<worktree-root>`), or on a **stale local branch tip** behind the PR head. If
  `HEAD` differs from that head, **stop** — never merge, edit, or push onto a stale tip: a naive
  `git merge origin/<baseRefName>` + push from a behind-head tip silently reverts the newest branch
  commit(s). Safety comes from this assertion, not from the assigned `HEAD` happening to match. The
  assertion is also on **identity, not just the commit**: a clean worktree whose tip merely equals
  `headRefOid` while checked out on some OTHER local branch must not enter full mode — a fix committed
  there advances that unrelated branch while only the refspec push lands on the PR branch, leaving the
  other branch locally carrying this PR's work. Require the checkout to be on the PR branch or in
  detached HEAD (a coincidental same-tip match on another branch heals via `gh pr checkout`). This
  extends the head-SHA re-check below — which covered only the head moving *mid-work* — to the moment
  the worktree is first assigned.
- Re-check the PR head SHA immediately before editing and again immediately before pushing. Stop
  if it changed unexpectedly — someone else moved the branch.
- **Refspec push to the branch's upstream, never branch checkout.** Do not depend on `git checkout
  <headRefName>` to reach the branch: when it is locked by a sibling worktree that command dead-ends
  (`fatal: '<branch>' is already used by worktree at ...`). Once the head assertion holds, push the
  integrated work with an explicit refspec to the remote `gh pr checkout` configured for the branch —
  `git push "$PUSH_REMOTE" HEAD:<headRefName>`, where `PUSH_REMOTE` resolves **fail-closed**. Decide
  same-repo vs fork from `gh pr view --json isCrossRepository`, never by whether `git config` happens
  to resolve: `origin` for a same-repo head; for a write-allowed cross-repo (in-owner fork) head, the
  fork destination from `branch.<headRefName>.pushRemote` or `branch.<headRefName>.remote`, validated
  by URL and gated on the trust boundary. First require the cross-repo head's OWNER to be within
  `<watched-owners>`, else read-only (Stop And Ask, below) — an external-fork head with maintainer
  edits enabled must not receive a push just because its URL matches. Then, because a named remote can
  carry separate `pushurl`(s) that `git push` honors and writes to ALL of, resolve the actual push URLs
  (`git remote get-url --push --all`) and canonicalize EACH (a remote name, a bare URL, or those
  `pushurl`s) to **host + owner/repo**, then require EVERY one to equal the head repo's own canonical
  URL (`gh api repos/<nameWithOwner> --jq .html_url`; `gh pr view --json headRepository` exposes no
  URL), not merely reject the literal `origin` name or match `owner/repo` on any host. Never hardcode
  `origin`, and never fall back to it when the destination cannot be validated — a fork head reached via
  `--detach` leaves no branch config, and a remote named `upstream` (or any name), a same-`owner/repo`
  path on a different host, a fork fetch URL masking a base-repo `pushurl`, or an extra base/attacker
  `pushurl` past a matching first one, can point at the base repo, so pushing there silently writes a
  same-named branch on base instead of updating the fork head; **stop (read-only) instead**. Known
  limitation: this validates the push URLs resolvable at guard time; git's own push-time URL rewrites
  (`url.<base>.pushInsteadOf` and similar) are outside the static guard's threat model, as they do not
  arise from the documented `gh pr checkout` flow. Because `HEAD` equalled the PR head and you only added
  commits on top, this push is a fast-forward; never `--force` or `--force-with-lease`. A rejected
  non-fast-forward push means the assertion no longer holds — re-fetch and stop, never force past it.
  (An external-fork head outside `<watched-owners>` remains the read-only stop-and-ask case below.)
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

## Two Gates, One Merge-Ready Authority

Two different scripts produce a verdict this skill's prose has historically called "readiness".
They answer different questions and are not interchangeable:

| Script | Question it answers | What it never checks |
| --- | --- | --- |
| `${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh` — the **finding-classification gate** | Did this iteration individually classify every source finding, and is the iteration checklist complete? | Branch rules, review decision, unresolved threads, required checks, head match — nothing about GitHub's merge state |
| `source-control-babysit-merge` — the **merge gate** | Is GitHub itself willing to merge this PR right now? | Nothing about finding decomposition |

**Only the merge gate's `ready` field determines merge-readiness.** Any `MERGE-READY` claim —
a human-facing report, a worker's return, or an autonomous merge decision — must cite a
merge-gate run whose `ready` is `true`, never `READINESS_OK` from the finding-classification
gate and never an agent's own reading of the PR. A PR can pass the classification gate and still
be unmergeable: the classification gate is blind to, for example, a `required_review_thread_resolution`
ruleset plus deliberately-open review threads, which blocks merge mechanically regardless of
severity or whether a human already replied. Reporting `MERGE-READY` off the classification gate
alone has produced a false human-facing report (`#601`).

The classification gate is a **pre-gate**, not a weaker merge gate: it must pass before an
iteration reports at all, and passing it says only that the findings were decomposed. Both gates
must be satisfied before a PR is called merge-ready, and only the merge gate can say so.

## Guarded Mutation Wrappers

The two guarded mutations run **only through their wrapper scripts** —
`source-control-babysit-merge` and `source-control-babysit-resolve-thread` — never through the
raw Python behind them (`python … babysit_merge.py`), which would bypass the wrapper's own guards
(such as the merge wrapper's `--allow-unpinned-head` rejection). The wrappers are this skill's own
deterministic authorization layer: they encode exactly what worker and autopilot are allowed to do.

Invoke each wrapper **by its bundled path**, the same form the read-only sibling scripts under
`${CLAUDE_PLUGIN_ROOT}/scripts/` use:

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" <args>
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" <args>
```

Launching the wrapper by path still runs the wrapper itself, so every wrapper guard stays intact
— it is not a guard-dodging re-spelling (only invoking the raw Python is). The bundled wrappers'
bare names are not on the Bash tool's `PATH`, so a bare `source-control-babysit-merge …` fails
`command not found`; the `${CLAUDE_PLUGIN_ROOT}/bin/` path — resolved exactly as the sibling
`${CLAUDE_PLUGIN_ROOT}/scripts/` invocations are — is the reliable form. Every command spelled
below as `source-control-babysit-<x> …` is launched this way.

Capture the wrapper's output first, then parse its JSON in a *separate* step — never pipe the
wrapper into an interpreter (`… | python`, `… | jq`): an interpreter-in-pipeline trips the
auto-mode safety classifier and blocks the call before the wrapper runs.

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
  overrides are human decisions, never passed autonomously. The held dependency-manager set is the
  built-in dependabot/renovate bots plus, when `babysit_extra_dependency_manager_logins` is
  configured (non-empty, not a literal unexpanded token), the logins appended via
  `--extra-dependency-manager-logins <extra-dependency-manager-logins>` — supply it on every merge
  command below, exactly as `--method` is, or those extra bots are not held.
- The merge wrapper's `--autopilot-merge-tier` flag layers the #476 tier criteria (issue-linked,
  lane-authored, no blocking label, a distinct-bot approval on the live head, no human blocking
  comment) onto the base gate. It is **fail-closed**: the umbrella flag refuses (exit `3`) unless
  `--lane-logins`, `--approver-bot-logins`, and `--block-labels` are all non-empty, and supplying
  any of those three without the umbrella is a usage error (exit `2`). Absent the flag the gate is
  exactly its prior self, so worker/autopilot's existing gate-proven merges are unchanged. This
  tier is only ever wired when `babysit_autopilot_merge_tier` is enabled.
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

## Autopilot Merge Tier: Enabled-Path Mechanics

Reachable only while `babysit_autopilot_merge_tier` is enabled; absent that flag none of this
section applies and autopilot's merge path is byte-for-byte its prior self. This is the single
home for the enabled-path merge command that autopilot's step 3 in `SKILL.md` points at, so the
base and enabled-tier merge paths never drift apart. The tier still ships **DISABLED**; enabling
it, and any later gate-off flip, is a separate announced operator step.

- **Enabled-path merge command.** After the worker's final push and a fresh post-push snapshot
  (or the exact pushed commit, vetted), merge on that post-push head by layering the tier flags
  onto the base gate command — this is the *only* autopilot merge path once the tier is enabled,
  never the four-flagless base command, which would ignore every tier criterion:

  ```text
  bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" owner/repo#N --allowed-owners <watched-owners> --self-logins @me,<self-logins> --merge --expected-head <post-push-head-sha> --autopilot-merge-tier --lane-logins <lane-logins> --approver-bot-logins <approver-bot-logins> --block-labels <merge-block-labels> --extra-dependency-manager-logins <extra-dependency-manager-logins>
  ```

  The umbrella `--autopilot-merge-tier` is fail-closed: it refuses (exit `3`) unless
  `--lane-logins`, `--approver-bot-logins`, and `--block-labels` are all supplied, and any of
  those three without the umbrella is a usage error (exit `2`). Add `--method <merge-method>` and
  `--extra-dependency-manager-logins <extra-dependency-manager-logins>` when configured, exactly as
  for the base merge readiness gate above (omit each when its value is empty or a literal
  unexpanded token).

- **Second-account approve mechanic.** The approving review the gate's distinct-bot criterion
  requires is submitted out-of-band by the agent — the gate only verifies one exists on the live
  head, it never creates it. Bind a **distinct** identity (one of the `<approver-bot-logins>`
  accounts, never the PR author or a lane identity), run a **genuine** review pass — through a
  review skill/plugin when one is installed, otherwise an equivalent thorough manual review (this
  skill declares no review-plugin dependency; the gate requires only that the resulting approval
  exists on the live head, not that a particular tool produced it) — and only when that pass is
  clean submit the approval under that identity:

  ```text
  GH_TOKEN=<approver-bot-token> gh pr review owner/repo#N --approve --body "<clean-review-summary>"
  ```

  `gh auth switch --user <approver-login>` before a plain `gh pr review … --approve` is the
  equivalent when the approver is a persisted gh account rather than a bound token. Submit on the
  live head so the gate's head-unchanged-since-review pin (`--expected-head`) still holds; any
  push after the approval invalidates it and the review pass must be re-run against the new head.
  Never approve on an unclean pass, and never under the author or a lane identity — either
  collapses author ≠ approver and the gate refuses the merge fail-closed.

- **Review-workflow requiredness precondition (enabling).** Enable the tier ONLY on a base branch
  whose ruleset makes the review workflow a **required status context** *and* whose review workflow
  always runs to a non-skipped conclusion on every PR to that base. The gate proves the review ran
  solely through `mergeStateStatus == CLEAN`, which guarantees only that *required* contexts passed;
  a review workflow that is present but not required can be absent, skipped, or failing while the PR
  still reads CLEAN, so the gate could green-light a merge the review never actually gated.
  Requiredness is necessary but not sufficient: a conditionally-skipped review job can report a
  `SKIPPED` conclusion that is counted as a passing state, so a required-but-skipped review still
  reads CLEAN without having run. Requiring the review workflow therefore closes that hole
  deterministically *only when* it cannot conditionally skip on the paths or conditions the tier's
  PRs hit — it must always execute and produce a non-skipped result on the pinned head. Where the
  review workflow is not a required context, or can skip on those PRs, do not enable the tier: this
  is an operator enabling precondition, verified before the flip, not something the merge gate can
  self-enforce.

- **Bot-review precision precondition (enabling).** Enable the tier ONLY after the fleet's bot-review
  lane has demonstrated recorded precision over a sustained window — the same earned-promotion trigger
  ADR 0002 sets for flipping an advisory review lane to a blocking gate. The tier lets a
  fleet-produced approval satisfy a required-review ruleset, which promotes that lane from advisory to
  merge-deciding, so it is earned on that same evidence bar: precision proven over a sustained window
  and ratified as a reviewed change citing that evidence — never a calendar flip, and operator
  discretion alone is insufficient. Absent a recorded precision window for the reviewing bot, do not
  enable the tier. The requiredness precondition above governs whether the review workflow ran; this
  one governs whether its verdicts have earned the authority to stand in for a human approval, and
  like requiredness it is an operator enabling precondition the merge gate cannot self-enforce.

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
fully-argument-pinned command for the operator to run — in the `bin/`-path wrapper form
(§Guarded Mutation Wrappers), which runs the wrapper with every guard intact — never a workaround,
and never a raw-Python re-spelling of the command that would dodge the wrapper's guards and the
narrow allow rule.

For a merge:

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" owner/repo#42 --allowed-owners <watched-owners> --merge --expected-head <post-push-head-sha> --method <merge-method> --extra-dependency-manager-logins <extra-dependency-manager-logins>
```

When the autopilot merge tier is enabled, this degraded handoff carries the tier flags too:
surface the enabled-path command from Autopilot Merge Tier: Enabled-Path Mechanics above, not this
flagless base form, so the operator's manual merge is held to the same tier criteria the blocked
gate would have enforced.

For a thread resolve, never surface a bare `--autonomous` or `--include-human` resolve: both
re-fetch the live thread list and re-evaluate every eligible thread at execution time, so an
unpinned command could resolve a thread this run never vetted — one opened or changed after its
assessment. Pin each vetted thread individually (the wrapper accepts exactly one `--thread-id`
per invocation; issue one pinned command per thread) with the thread-pin pair rule above:

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --autonomous --resolve --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the unattended-worker case, or

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --resolve --include-human --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the autopilot case. This degradation is a successful, material finding to report, not a
failure and not a blocker to resolve — continue the rest of the queue exactly as if the mutation
had been refused by the wrapper's own gate. Hand off the pinned command and move on: the
no-background-monitor clause (Worker Contract, `orchestration.md`) governs this point too, so a
harness-blocked merge is never a reason to arm a watch that sits waiting to retry it. When this
agent (or the operator) later checks
whether a deferred command actually acted, parse the JSON `action` field per Guarded Mutation
Wrappers above — never the exit code alone — before treating the thread as cleared or the merge
as done and re-running the gate.

## Never Do Automatically

- Merge in default (safe) mode, or merge through any path other than the pinned merge wrapper's
  gate. Worker and autopilot merge only a PR that gate proves 100% ready.
- Generate an approving review to satisfy a required-review ruleset, or merge on a review the
  fleet produced itself — **except** under the autopilot merge tier (#476), a deliberate,
  config-gated opt-in that ships **DISABLED**. It engages only when the operator sets
  `babysit_autopilot_merge_tier`; enabling that flag, and any later gate-off flip, is a
  separate, loudly-announced operator step, never a default and never a side effect of another
  change. When the tier is enabled, a second bot account (author ≠ approver) runs a **genuine**
  review pass and submits an approving review **only when it is clean**, and the pinned merge
  wrapper's `--autopilot-merge-tier` gate then merges **only when every criterion holds**, each
  enforced deterministically:
  - required checks green, including the review workflow, with the base ruleset satisfied
    (`mergeStateStatus` CLEAN — the ruleset itself is never bypassed);
  - the PR is issue-linked (carries a closing-issue reference);
  - the PR is authored by a configured pipeline lane;
  - no human `CHANGES_REQUESTED`, no human blocking comment, no unresolved review thread;
  - no configured do-not-merge label is present;
  - the PR's linked issue carries no unratified `Decision defaulted` marker — the triage lane
    records a defaulted (maintainer-vetoable) decision only as a `Decision defaulted: X — veto
    before merge` issue comment, invisible to the gate, so the default rides into an autopilot
    merge only once a maintainer has **ratified** it: a human `OWNER`/`MEMBER` comment posted
    after the marker carrying an explicit ratification signal — a closed, whole-word token set
    (`ratify`/`ratified`, `approve`/`approved`, `confirm`/`confirmed`), and not a
    withheld-approval negation (`not approved`, `cannot approve`). All maintainer comments
    after the marker are scanned and the **latest decisive signal wins**: a ratification token
    ratifies, while a revocation reusing the veto vocabulary (`not approved`, `do not merge`)
    re-holds, so a maintainer who ratifies and then revokes holds the PR. Matching is strict and
    fail-closed: an unrelated maintainer comment, a signal appearing before the marker, a
    ratify/revoke tie at the same timestamp, an unratified marker, or an issue whose comments
    cannot be read all hold the PR;
  - the approving review is by a **distinct bot identity** (author ≠ approver) and was
    submitted against the **live head** (head SHA unchanged since review), pinned as always by
    `--expected-head`.

  Any criterion failing falls back to today's behavior — the PR is reported on the human
  merge-ready list. The tier never routes around the gate and never rubber-stamps: the bot
  review is a real review pass, and the ruleset stays meaningful. Absent the enable flag this
  tier does not exist and the first bullet governs unchanged.
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
