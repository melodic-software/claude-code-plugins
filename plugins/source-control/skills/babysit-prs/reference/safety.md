# Safety Rules

## Contents

- [Role Boundaries](#role-boundaries)
- [Checkout And Push Invariants](#checkout-and-push-invariants)
- [Allowed Without Asking](#allowed-without-asking)
- [Stop And Ask](#stop-and-ask)
- [Verify Before Escalating Non-Convergence](#verify-before-escalating-non-convergence)
- [Two Gates, One Merge-Ready Authority](#two-gates-one-merge-ready-authority)
- [Review-Settle Hold](#review-settle-hold)
- [Guarded Mutation Wrappers](#guarded-mutation-wrappers)
- [Autopilot Merge Tier: Enabled-Path Mechanics](#autopilot-merge-tier-enabled-path-mechanics)
- [Harness Permission Layer](#harness-permission-layer)
- [Never Do Automatically](#never-do-automatically)
- [Human Comments](#human-comments)
- [Comment Policy](#comment-policy)

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
  when that module is configured), spawn workers, push a dispatched conflict worker's verified
  resolution (`orchestration.md`, Merge Conflict Resolution, the one push it owns), and report.
- A worker may only inspect and fix the single PR assigned to it.
- A worker must not refresh branches, post review triggers, merge, enable auto-merge, force-push,
  change GitHub settings, spawn more workers, or resolve any thread outside the constrained
  pre-push-outdated rule in `orchestration.md`'s Worker Contract.
- If two workers would touch the same checkout, source-of-truth repo, or shared generated file,
  the orchestrator must sequence the work or ask the user.

## Checkout And Push Invariants

- Reuse an existing clean worktree for a PR rather than creating a second checkout. Reuse only
  when `git status --porcelain` is clean and its `HEAD` is the true PR head (the head assertion
  below), whether it is checked out on the PR branch or in detached HEAD because the branch is
  locked elsewhere; otherwise report it (`worktrees.md`).
- **Assigned-worktree head assertion.** Before any merge, edit, or push, resolve the assigned
  worktree's `HEAD` to a commit and assert it equals the true PR head, `gh pr view <N> --json
  headRefOid` (authoritative for same-repo and fork PRs; equal to a freshly re-fetched
  `origin/<headRefName>` for a same-repo PR). This holds whether the worktree is on the PR branch,
  in **detached HEAD** (the branch is checked out in a sibling worktree, or lives in a foreign dev
  worktree outside `<worktree-root>`), or on a **stale local branch tip** behind the PR head. If
  `HEAD` differs from that head, **stop**. Never merge, edit, or push onto a stale tip: a naive
  `git merge origin/<baseRefName>` + push from a behind-head tip silently reverts the newest branch
  commit(s). Safety comes from this assertion, not from the assigned `HEAD` happening to match. The
  assertion is also on **identity, not just the commit**: a clean worktree whose tip merely equals
  `headRefOid` while checked out on some OTHER local branch must not enter full mode. A fix committed
  there advances that unrelated branch while only the refspec push lands on the PR branch, leaving the
  other branch locally carrying this PR's work. Require the checkout to be on the PR branch or in
  detached HEAD (a coincidental same-tip match on another branch heals via `gh pr checkout`). This
  extends the head-SHA re-check below, which covered only the head moving *mid-work*, to the moment
  the worktree is first assigned. **One codified exception:** the conflict-resolution push in
  `orchestration.md`'s Orchestrator Contract. There `HEAD` is by construction the local merge commit
  the conflict worker produced, which the live PR does not carry yet, so the assertion is checked
  one commit back: the merge commit must have exactly two parents, its **first parent** must equal
  the live `headRefOid` (re-checked immediately before the push), and its second parent the
  reported base. Every other condition of that contract still binds, and everywhere outside that
  push the assertion remains on `HEAD` itself.
- Re-check the PR head SHA immediately before editing and again immediately before pushing. Stop
  if it changed unexpectedly. Someone else moved the branch.
- **Refspec push to the branch's upstream, never branch checkout.** Do not depend on `git checkout
  <headRefName>` to reach the branch: when it is locked by a sibling worktree that command dead-ends
  (`fatal: '<branch>' is already used by worktree at ...`). Once the head assertion holds, push the
  integrated work with an explicit refspec to the remote `gh pr checkout` configured for the branch:
  `git push "$PUSH_REMOTE" HEAD:<headRefName>`, where `PUSH_REMOTE` resolves **fail-closed**. Decide
  same-repo vs fork from `gh pr view --json isCrossRepository`, never by whether `git config` happens
  to resolve: `origin` for a same-repo head; for a write-allowed cross-repo (in-owner fork) head, the
  fork destination from `branch.<headRefName>.pushRemote` or `branch.<headRefName>.remote`, validated
  by URL and gated on the trust boundary. First require the cross-repo head's OWNER to be within
  `<watched-owners>`, else read-only (Stop And Ask, below). An external-fork head with maintainer
  edits enabled must not receive a push just because its URL matches. Then, because a named remote can
  carry separate `pushurl`(s) that `git push` honors and writes to ALL of, resolve the actual push URLs
  (`git remote get-url --push --all`) and canonicalize EACH (a remote name, a bare URL, or those
  `pushurl`s) to **host + owner/repo**, then require EVERY one to equal the head repo's own canonical
  URL (`gh api repos/<nameWithOwner> --jq .html_url`; `gh pr view --json headRepository` exposes no
  URL), not merely reject the literal `origin` name or match `owner/repo` on any host. Never hardcode
  `origin`, and never fall back to it when the destination cannot be validated. A fork head reached via
  `--detach` leaves no branch config, and a remote named `upstream` (or any name), a same-`owner/repo`
  path on a different host, a fork fetch URL masking a base-repo `pushurl`, or an extra base/attacker
  `pushurl` past a matching first one, can point at the base repo, so pushing there silently writes a
  same-named branch on base instead of updating the fork head; **stop (read-only) instead**. Known
  limitation: this validates the push URLs resolvable at guard time; git's own push-time URL rewrites
  (`url.<base>.pushInsteadOf` and similar) are outside the static guard's threat model, as they do not
  arise from the documented `gh pr checkout` flow. Because `HEAD` equaled the PR head and you only added
  commits on top, this push is a fast-forward; never `--force` or `--force-with-lease`. A rejected
  non-fast-forward push means the assertion no longer holds. Re-fetch and stop, never force past it.
  (An external-fork head outside `<watched-owners>` remains the read-only stop-and-ask case below.)
- Honor `mutation_policy.branch_write_allowed`: never push, and never create a write-capable
  worker or refresh a PR head, when it is false.
- Head-ref uniqueness guard: two open PRs sharing one head repository/branch is a stop-and-ask.
  Escalate, never guess which PR a push would update.
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
- Prune worktrees exactly per `worktrees.md`: global prune only for unleased clean merged/closed
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
- The worktree is dirty, the head SHA changes while working, or permissions are missing,
  including a harness/runtime permission denial; see Harness Permission Layer below for how to
  tell that apart from a script-level gate denial before deciding how to react.
- A merge conflict appears. In default (safe) mode this is always a stop: report it as a blocker
  and take no resolution action. In worker or autopilot mode only, a textual/mechanical conflict
  (formatting, adjacent unrelated changes, both sides adding different items to the same list) is
  not an automatic stop: hand it off to a dedicated, fresh conflict worker per
  `orchestration.md`'s Merge Conflict Resolution section, never resolved by the worker that
  discovered it mid-fix-round. The orchestrator never resolves a conflict dispatched to a conflict
  worker: it does not touch conflict markers or edit a resolution. (The safe tier's own inline
  handling of a simple conflict met while freshening a branch is separate and unaffected, per
  `loop.md` §5.1.2.) It does own the conflict worker's one outward step. After re-asserting the
  live head against the merge commit's first parent and re-running the affected-file verification
  itself, it performs the push, which the conflict worker never does (same section, Orchestrator
  Contract). In worker or
  autopilot, stop and ask only when that fresh conflict worker finds the conflict genuinely
  semantically ambiguous (both sides made incompatible design/behavioral decisions about the same
  logic, not just textually overlapping edits) or when the same conflict recurs across repeated
  resolution attempts.
- A change would alter secrets, branch protection, repo settings, GitHub Apps, runners, billing,
  or organization policy.
- A branch refresh returns `403` or `422`, conflicts, lacks permissions, remains unchanged, or
  would require rebasing or force-updating.
- Durable review-trigger state is missing or ambiguous, or the configured reviewer does not
  engage after the one request allowed for a head SHA (`review-trigger.md`).
- Whether to merge a green dependency-manager PR; dependency acceptance is human judgment in
  every tier (`feedback.md`; the invariant is stated in `SKILL.md`).

## Verify Before Escalating Non-Convergence

Before reporting a blocker as real, and before raising a "this PR is not converging," "should
rounds be capped," or "should we pause the loop" question to the user, re-query GitHub and read
the actual content of every currently-unresolved review thread on the PR(s) in question. Never
escalate on unresolved-thread count or round number alone. This section binds every escalation of
that shape regardless of which skill's escalation path carries it. A lane escalating through a
loop's own escalation contract is not outside it.

- Classify each unresolved thread: (a) a genuine duplicate: the same finding recurring after a
  fix that should have addressed it, real evidence of non-convergence; (b) a new, distinct,
  code/line-cited finding: expected depth on complex or security-sensitive logic, not churn; or
  (c) a self-inflicted finding: new and distinct, but against text this lane's own prior fix on
  this PR introduced. Provenance decides (c), never severity. <!-- contract-restatement-begin: D4.6-deferral-provenance -->
- Fix (c) like any other in-scope defect, but count it. It is never deferrable, because it is a
  defect this change is shipping (`<plugin-root>/reference/review-discipline.md`,
  D4.6). <!-- contract-restatement-end: D4.6-deferral-provenance --> A (b) finding follows D4.6's
  scope test, which places a small or medium fix and files and defers only a structural,
  urgent-but-cannot-land, or fix-blocked-on-research one. A second consecutive **advisory** round whose findings are *all* (c) means incremental
  patching is injecting defects about as fast as it removes them; that is the non-convergence
  signal a round count only approximates. The test is scoped to advisory rounds because those are
  the rounds the ledger records. A blocking-defect round in between neither counts nor resets it.
  It survives context rollover because the classification itself is durable, and two duties follow:
  - **Classify at record time on EVERY advisory round, not only when an escalation is already
    being prepared.** This section's heading scopes when to *escalate*; the classification itself
    is a per-round duty, because a round that runs it only at escalation time has already lost the
    history the tripwire consumes. Run the (a)/(b)/(c) taxonomy over the round's findings before
    recording it, and pass one `--finding-class` per finding to `manage_feedback_ledger.py
    record-advisory-round` (`feedback.md`); the helper refuses an unclassified round, so no silent
    path leaves the tripwire nothing to read. Also stamp the literal marker `(class (a))`, `(class
    (b))`, or `(class (c))` beside the disposition in the D5 reply row for every finding
    classified. The canonical D5 vocabulary (VALID/INCORRECT/UNCERTAIN) does not carry this
    taxonomy, and the markers are what let a human reading the PR check the ledger's arithmetic
    against the threads themselves.
  - **Read the verdict; never re-derive it.** One computation, two reads, and they answer
    different questions. The snapshot's `advisory_fix_rounds.non_convergence_tripwire`, `armed`
    plus the `basis` it was decided on, covers the rounds already recorded, so at round start it
    reports whether the lane arrived here already non-converging. The **decisive** read for the
    round about to be dispatched is the verdict `record-advisory-round` returns once this round's
    own classes are recorded: that is what answers "is THIS round all-(c) after an all-(c)
    predecessor", and it is why the classification is recorded before the fix is dispatched rather
    than after it. Either read is a field a fresh worker with no prior context can just read,
    instead of reconstructing the previous round's composition from GitHub threads. A round
    recorded before per-finding classes were persisted reads as UNKNOWN, not (a)/(b), and the
    tripwire **fails closed** on it: a current all-(c) round following an UNKNOWN round arms, and
    the escalation says so rather than silently resetting the count. Armed means change METHOD
    rather than stopping: rewrite the contested section whole in one commit, or report it for a
    human decision. It is never a license to ship a known defect.
- Escalate a bounding/cap-policy question only when verification shows (a), a second consecutive
  all-(c) advisory round, or a finding that is structurally impossible to resolve (the check
  itself is external or non-deterministic). If every unresolved thread is (b) or (c) and each is
  individually fixable, a mechanical fix or a clearly-scoped judgment call, fix directly
  instead. A high round count alone is not evidence of non-convergence.
- This verification is required even when a sub-agent, advisor, or other second opinion reads
  round-count or metadata as a non-convergence pattern. That read is a hypothesis to test
  against actual thread content, never a conclusion to act on or escalate over.
- See the Fix-Round Cap in `orchestration.md` for the mechanical cap this verification gates.

## Two Gates, One Merge-Ready Authority

Two different scripts produce a verdict that is easy to call "readiness".
They answer different questions and are not interchangeable:

| Script | Question it answers | What it never checks |
| --- | --- | --- |
| `<plugin-root>/scripts/babysit-readiness-gate.sh`, the **finding-classification gate** | Did this iteration individually classify every source finding, and is the iteration checklist complete? | Branch rules, review decision, unresolved threads, required checks, head match. Nothing about GitHub's merge state |
| `source-control-babysit-merge`, the **merge gate** | May this PR be merged right now under the plugin's full merge policy, where GitHub's own mergeability *and* the plugin's policy both hold? | Nothing about finding decomposition |

`ready` is the plugin's **merge-policy** verdict, not a readout of GitHub's mergeability alone.
`babysit_merge.py` appends its own policy blockers after the GitHub-derived ones: a
dependency-manager author is held in every tier without `--allow-dependency`, a PR on an
unprotected base is held without `--allow-unprotected` (a self author is exempt only when that base
is the repository's default branch), and an enabled autopilot merge
tier adds that tier's own criteria. So `ready: false` can mean "GitHub would merge this; the plugin
will not." Read the `blockers` list to tell the two apart, and never restate a plugin policy hold
as a GitHub restriction. That mislabel is the same terminology ambiguity this section exists to
remove.

**Only the merge gate's `ready` field determines merge-readiness.** Any `MERGE-READY` claim,
whether a human-facing report, a worker's return, or an autonomous merge decision, must cite a
merge-gate run whose `ready` is `true`, never `READINESS_OK` from the finding-classification
gate and never an agent's own reading of the PR. A PR can pass the classification gate and still
be unmergeable: the classification gate is blind to, for example, a `required_review_thread_resolution`
ruleset plus deliberately-open review threads, which blocks merge mechanically regardless of
severity or whether a human already replied.

The classification gate is a **pre-gate**, not a weaker merge gate: it must pass before an
iteration reports at all, and passing it says only that the findings were decomposed. Both gates
must be satisfied before a PR is called merge-ready, and only the merge gate can say so.

"Both gates satisfied" binds the decomposition claim, not a mandatory second script run on every
path. The classification gate blocks on `findings > 0` with `classified < findings` (or an
unticked `--checklist`), so it constrains any iteration that actually processed findings. The
orchestrator's direct zero-blocker path, a non-draft PR the engine snapshot reports with zero
blockers *and* no untriaged material feedback (`SKILL.md`, "Fan out"), goes straight to a
merge-gate check without a worker, and so without the worker's per-PR iteration
classification-gate run (`SKILL.md`, Steps A–F). What keeps that path from
producing a false `MERGE-READY` is the `untriaged_material_feedback` exclusion in
`pr_clean_ready_for_direct_gate` (`scripts/babysit_delta.py`): the merge gate never inspects finding
content, so a PR carrying an undisposed material bot finding is held out of the direct gate rather
than merged over it. That exclusion is *not* a guarantee the classification gate would pass there.
It counts severity markers across *all* comment bodies with no bot/human split, while
`collect_feedback` routes a top-level human comment or `COMMENTED` review carrying only a
`SUGGESTION`/`CRITICAL`/`IMPORTANT` marker into `feedback["human"]` (non-blocking, and not material
feedback), so such a PR can reach the direct gate while a classification-gate run would report
`READINESS_BLOCKED`. Nor does the exclusion by itself force a worker: a *new* material item does
(`unsuppressible_delta`, absent a refresh or foreign-activity hold), but an already-known,
still-undisposed one re-dispatches a worker only through `quiet_recheck_due`'s periodic fallback,
so such a PR may get neither a worker nor the direct gate that cycle. That path is gated on the engine's deterministic `needs_worker` delta, never
on an agent's own reading that a PR has nothing outstanding, and merge-readiness on it still comes
only from the merge gate's `ready` field.

The merge gate is Python, so the Python-free degrade (`loop.md`) cannot run it at all. That path
reports merge-readiness as **unchecked**. An unavailable merge gate is never grounds to promote
`READINESS_OK` into a merge-ready claim.

## Review-Settle Hold

`mergeStateStatus == CLEAN` is a statement about the *present*, and a reviewer that re-reviews on
push contradicts it for the few minutes its next round takes. GitHub reports the PR mergeable that
whole time, because the review does not exist yet and there is no unresolved thread to block on,
and a gate reading only mergeability merges past findings that land seconds later. A reviewer round can
land within a minute of the final commit and carry a regression the PR itself introduced.

The hold closes that window and is **dormant unless configured**: with
`babysit_review_bot_logins` and `babysit_review_settle_minutes` both set, the gate adds a policy
blocker while a configured reviewer still owes the **live head** a review and that head is younger
than the window. The pair is `userConfig`-only (`--review-bot-logins`, `--review-settle-minutes`):
a repository's default-branch declaration of either key is ignored with a note, because a listed
reviewer that a repository could add would clear the hold before the operator's reviewer reviewed.
Its shape, and why each part is that way:

- **A review of the live head clears it outright**, before the clock is consulted. The common case
  where the reviewer already reviewed this head costs nothing and adds no latency. Evidence is a
  submitted review *or* an inline review comment whose own commit id equals the head, by a
  configured login **that GitHub types as a `Bot`**: the same current-head test
  `review-trigger.md` specifies, reused rather than restated. A review of an earlier head is not
  evidence about this one. That shared test also admits a login the operator declared in
  `--extra-bot-logins`, but the merge gate does not pass that declaration through, so at *this*
  call site the `Bot`-type requirement still holds: a configured reviewer GitHub reports as a
  `User` never clears the hold early, so every merge waits the full window. Fail-closed, but
  slower.
- **The window bounds it.** A reviewer that never engages must not wedge a PR, so the hold expires
  rather than waiting forever. Past the window the gate stops waiting and merges on its ordinary
  criteria. The window is therefore a latency budget, not a review requirement: it buys the
  reviewer time, it does not guarantee a review happened.
- **An unestablishable head age holds rather than merges.** If neither clock below can be read,
  whether the reviewer still owes this head a review is undecidable, and a transient read failure
  must not be the thing that silently disables the hold. The block is self-clearing on the next run.
- **Both keys or neither.** Either alone is a usage error (exit 2), not an inert flag. A
  half-configured hold must never read as an active one. No duration is defaulted in the gate:
  how long a reviewer takes is a property of that reviewer, so the operator supplies it.

Set the window above the reviewer's observed latency, measured against that reviewer rather than
inherited from this file. Priced honestly, the hold costs up to one window of latency on any merge
whose head the reviewer has not yet reviewed, including every merge when the reviewer is down,
in exchange for not merging past a review already on its way.

**Which clock the age is measured on**, in order, because the difference decides whether the hold
fires at all:

1. **The most recent CI start on the live head**, read from the **raw** status-check rollup the
   gate already fetches: no extra request, and raw rather than classified because the classifier
   keeps only the newest run per check identity. GitHub generates the timestamp after the push, so
   it can only make a head look *more* recent than it is, which errs toward holding.

   **Newest rather than oldest, and the direction is the safety property.** Check runs live on the
   SHA, so a head returning to a previously-checked SHA, force-push A → B → A, still carries A's
   original runs even though the re-push draws a fresh review. Reading the oldest would call a
   brand-new head settled and merge straight through the window. The cost of reading the newest is
   bounded and lands on latency: a re-run extends the wait by up to one window, and a head the
   reviewer has not reviewed is one that should be held anyway.

   **The same timestamp is also the review-recency floor.** GitHub keeps a review against the SHA,
   not against the head position, so the earlier occurrence's review of A still matches `commit_oid`
   when A returns as head, and matching on the SHA alone let that stale review clear the hold
   before any clock was read, restoring the race through the short-circuit rather than through the
   clock. A review clears the hold only when it postdates the newest CI start on the live head; one
   that cannot be dated does not clear it. A check start cannot distinguish a restored head from a
   re-run on the standing head, so a re-run minted after the review re-arms the hold for up to one
   window instead of short-circuiting past it. That is the fail-closed direction, paying latency to
   refuse the safety failure.

2. **The head commit's committer date**, only when the rollup carries no usable timestamp. A weaker
   proxy that errs the wrong way: a commit pushed long after it was written, whether from local
   batching, an offline delay, or replaying an existing commit, reads as already-settled, and the hold silently
   does not fire on exactly the push that triggered a fresh review. A repository with no checks on
   its PRs gets only this fallback, so the hold is best-effort there.

**One residual, stated because it is not closed.** If a force-push back to a previously-checked SHA
produces new check runs, the newest timestamp is fresh: the head is aged from it, and any earlier
review of that SHA falls below the recency floor, so the hold fires correctly whether or not that
review exists. If GitHub instead reuses the existing results and mints none, the rollup carries only
the old timestamps, there is no floor above them, and that head reads as settled. Which of those
happens is not verified here, and no queryable "this SHA became the head at T" record covers both
ordinary pushes and force-pushes. The force-push timeline event covers only the latter. Treat the
hold as strong for ordinary pushes and best-effort across a head reverting to an already-tested SHA
that mints no new checks.

## Guarded Mutation Wrappers

The two guarded mutations run **only through their wrapper scripts**,
`source-control-babysit-merge` and `source-control-babysit-resolve-thread`, never through the
raw Python behind them (`python … babysit_merge.py`), which would bypass the wrapper's own guards
(such as the merge wrapper's `--allow-unpinned-head` rejection). The wrappers are this skill's own
deterministic authorization layer: they encode exactly what worker and autopilot are allowed to do.

Invoke each wrapper **by its bundled path**, the same form the read-only sibling scripts under
`<plugin-root>/scripts/` use:

```text
bash "<plugin-root>/scripts/source-control-babysit-merge" <args>
bash "<plugin-root>/scripts/source-control-babysit-resolve-thread" <args>
```

Launching the wrapper by path still runs the wrapper itself, so every wrapper guard stays intact.
It is not a guard-dodging re-spelling (only invoking the raw Python is).

Two facts decide the invocation form:

- **The wrappers have no bare name.** A plugin's top-level `bin/` is the only way to put one on
  the Bash tool's `PATH`, and the plugin keeps none: its presence blocks claude.ai organization
  plugin sync (#5850), and its delivery is unreliable, since a plugin's `bin/` reaches `PATH` only
  through the session shell snapshot's final `export PATH=` line
  ([anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066)).
- **The path form cannot match a bare-name allow rule.** Before matching Bash rules Claude Code
  strips only a fixed wrapper set: `timeout`, `time`, `nice`, `nohup`, `stdbuf`, the shell
  builtins `command` and `builtin`, and zsh's `noglob`
  ([permissions](https://code.claude.com/docs/en/permissions#process-wrappers)).
  `bash` is not among them, so `bash "…/scripts/source-control-babysit-merge" …` matches as a `bash`
  command and never satisfies a pre-approved `Bash(source-control-babysit-merge:*)`. That rule does
  not cover these invocations, and cannot while the wrappers have no bare name, so **what happens next is the permission mode's call, not the allow rule's.** Six modes
  exist, named by the config values hooks and settings use: `default`, `acceptEdits`, `plan`,
  `auto`, `dontAsk`, and `bypassPermissions`. `default` is the mode the CLI, `claude --help`, the
  VS Code and JetBrains extensions, and the desktop app display as **Manual**, and from v2.1.200 the
  CLI also accepts `manual` as an alias wherever the value is typed
  ([permission modes](https://code.claude.com/docs/en/permission-modes#available-modes)). An
  uncovered wrapper call lands three ways:
  - **`default` and `acceptEdits` prompt.** `acceptEdits` auto-approves file edits and common
    filesystem commands (`mkdir`, `touch`, `mv`, `cp`, and others) that `bash` is not among; every
    other Bash command outside the built-in read-only set still prompts. A per-call
    permission prompt is expected behavior here, not a misconfiguration.
  - **`plan` prompts only on its no-classifier branch.** Plan mode still *runs* shell commands (it
    blocks source edits, not commands). When auto mode is available and `useAutoModeDuringPlan` is
    on, which is the default, the classifier reviews them "instead of prompting you"; in a session
    with bypass permissions available plan mode's blocks are not enforced at all and the command
    runs unprompted; only otherwise do commands outside the read-only set prompt
    ([plan mode](https://code.claude.com/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode)).
  - **`auto`, `dontAsk`, and `bypassPermissions` resolve the call without a prompt.** Auto mode
    "lets Claude execute without routine permission prompts", routing uncovered actions to a
    classifier that approves or blocks them; `dontAsk` auto-denies every call that would otherwise
    have prompted, so an uncovered wrapper invocation is refused outright with no classifier and no
    prompt; `bypassPermissions` executes it immediately
    ([permission modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)).
    **`--permission-prompts none` is the unattended form that keeps the mode.** From Claude Code
    v2.1.259, `claude -p --permission-mode auto --permission-prompts none` leaves auto mode and its
    classifier in place and denies only a call that would have prompted. It is not `dontAsk` (which
    denies every uncovered call with no classifier) and not `bypassPermissions`. Denials are
    readable from stream-json `permission_denials`. **Claim, basis, as of, recheck:** that
    sentence, [headless](https://code.claude.com/docs/en/headless#turn-off-permission-prompts-in-unattended-runs)
    and [changelog](https://code.claude.com/docs/en/changelog) 2.1.259, 2026-09-28, and that
    headless section dropping the flag or changing what it denies.
    So a merge or thread-resolution call can be **denied without ever surfacing**. Do not wait on a
    prompt that will not arrive; under auto mode read the denial in `/permissions` → **Recently
    denied**. An explicit `permissions.ask` rule still forces a prompt in `auto` and
    `bypassPermissions`; in `dontAsk` it is denied instead.

  A narrow allow rule would not rescue this even if one matched: narrow Bash allow rules do carry
  into auto mode and resolve before the classifier, but `autoMode.classifyAllShell: true` suspends
  every one of them while auto mode is active
  ([auto-mode config](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)).

**Verification record for this block.** The claims above are verified 2026-09-06 against Claude
Code 2.1.263. The wrapper-strip list and the read-only carve-out come from
[permissions](https://code.claude.com/docs/en/permissions#process-wrappers), which states that the
list "is built in and is not configurable". `xargs` is not on it, so a bare `xargs` prefix is not
stripped and a rule written for the inner command does not match. The mode names, the `manual` alias from v2.1.200, the `acceptEdits`
filesystem set, and the plan-mode branch on `useAutoModeDuringPlan` being on by default come from
[permission modes](https://code.claude.com/docs/en/permission-modes#available-modes). The plugin
`bin/` PATH claim rests on
[anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066), which
`gh api repos/anthropics/claude-code/issues/68066` reports closed as not planned, so the behavior
stands unfixed. Recheck when either docs page stops
carrying the quoted spans, when a release note names permission modes, `classifyAllShell`, plugin
`bin/` PATH handling, or the wrapper-strip list, or when that issue reopens or closes as completed.

The `<plugin-root>/scripts/` path is the only invocation form. Every command spelled below as
`source-control-babysit-<x> …` is launched this way.

Capture the wrapper's output first, then parse its JSON in a *separate* step. Never pipe the
wrapper into an interpreter (`… | python`, `… | jq`): an interpreter-in-pipeline trips the
auto-mode safety classifier and blocks the call before the wrapper runs.

- Both wrappers **fail closed**: invoked without `--allowed-owners`, they exit `3` and refuse to
  act. The read-only forms are `source-control-babysit-merge owner/repo#42 --allowed-owners
  <watched-owners> --self-logins @me,<self-logins> --state-dir <state-dir>` (merge-readiness gate) and
  `source-control-babysit-resolve-thread
  owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins>
  --self-logins @me,<self-logins>` (thread list).
- **What the merge gate actually evaluates.** It gates on GitHub's own `mergeStateStatus == CLEAN`
  plus explicit cross-checks of its own: branch rules, review decision, unresolved threads, the
  check rollup keyed by check type and name, and head match. It reports the exact `blockers` list.
  React to those blockers; never bypass the gate. One reading caveat: a `ready: false` immediately
  following a `ready: true` on the same expected head is often GitHub's own mergeability recompute
  lag, so re-run the read-only check once before treating it as a real block.
- **`CLEAN` is not proof the PR was tested against the live base.** GitHub regenerates a PR's test
  merge commit only on a push, a merge-base change, or once the last one is 12 hours old, and
  states that this leaves mergeability checks, conflict reporting, and rule enforcement unchanged.
  So the gate keeps trusting `CLEAN` for mergeability; what can be up to 12 hours behind the base
  is the merge commit `pull_request` CI ran against. Only a strict up-to-date rule (`BEHIND`) proves
  the head is current at merge; under a non-strict base the stale-base rule in
  [freshness.md](freshness.md) is the guard, and the gate adds no hold of its own. **Claim, basis,
  as of, recheck:** that regeneration rule,
  [changes to test merge commit generation](https://github.blog/changelog/2026-02-19-changes-to-test-merge-commit-generation-for-pull-requests),
  2026-10-02, and a GitHub changelog entry that changes test-merge regeneration or says it now
  affects mergeability.
- **`--self-logins @me,<self-logins>` rides on every merge form too**, read-only and mutating
  alike. `@me` resolves to your own `gh` login and the `babysit_self_logins` extras follow it; drop
  the trailing `,<self-logins>` when that value is empty. On the merge gate this flag is what
  exempts your own PRs from the unprotected-base hold, and only **on the default branch** (see the
  unprotected-base bullet below). Without it your own PR is classified as a non-self author and
  held.
- **`--extra-bot-logins <extra-bot-logins>` rides on every resolve-thread form**, listing and
  mutating alike, whenever `babysit_extra_bot_logins` is configured. Bot classification is what
  decides which threads the resolver may touch at all, and structural detection cannot see a
  registered non-structural bot account (no `[bot]` suffix, API `__typename` of `User`); omitting
  the flag silently reclassifies that account's threads as human and skips them in worker tier.
  Omit the flag only when the key is unset.
- **The review-settle pair rides on every merge form** when `babysit_review_bot_logins` and
  `babysit_review_settle_minutes` are both configured: `--review-bot-logins <review-bot-logins>
  --review-settle-minutes <review-settle-minutes>`. Dropping it from a merge command silently
  merges inside a re-review's latency window, and supplying
  one half without the other is a usage error (exit `2`) rather than a partial hold. Omit the pair
  only when **both** keys are unset: the pair is `userConfig`-only, and a repository's declaration
  of either key never supplies or changes it. See §Review-Settle Hold.
- **`--stacked-prs` rides on every merge form, read-only and mutating alike, when
  `babysit_stacked_prs` is `true`**, and is omitted otherwise. A read-only check without it reports
  a stack layer held while the merge with it would land the stack, so the two must agree.
- **`--state-dir <state-dir>` rides on every merge form, read-only and mutating alike.** It is how
  a merge request left pending on GitHub stays visible to later runs (§Async Merge Path); the gate
  writes nothing else there.
- **`babysit_review_settle_minutes` set with `babysit_review_bot_logins` unset is a configuration
  error, and it must be refused HERE rather than rendered away.** Omitting both flags because one
  key is missing is the one case the CLI's exit `2` cannot catch: the lone flag never reaches it,
  so the merge proceeds with the hold silently dormant under a setting that looks active. Stop and
  report the misconfiguration instead of constructing the merge command. The converse is not an
  error. `babysit_review_bot_logins` alone is the review-trigger module's own configuration and
  leaves the settle hold correctly dormant.
- **`--self-logins @me,<self-logins>` rides on every resolve-thread form too**, listing and
  mutating alike, always (`@me` resolves your own `gh` login; append `babysit_self_logins`
  extras). The bot-only classifier (`project_thread`'s `botOnly`) requires a BOT OPENER **and**
  inspects every other fetched participant, so the worker's OWN reply to a bot thread (a
  classification reply, a `Fixed in <sha>` follow-up) is itself a comment the classifier sees.
  Without `--self-logins` that reply is indistinguishable from a genuine third-party human joining the
  thread: `botOnly` goes false, which locks the thread out of the default bot-only scope, and
  `--include-human` stays unset by design in worker/safe modes, so nothing lifts it back in and a
  bot thread the worker correctly handled is permanently unresolvable by the normal flow.
  `--self-logins` marks the caller's own posting identity as neutral for that test instead, and
  neutral as a REPLY only: the OPENING comment must still be an ACTUAL bot's, so a thread the
  worker itself opened stays out of scope even after a bot replies to it (`review-discipline.md`
  D7.5 forbids resolving your own threads). Omit the flag only when `babysit_self_logins` is unset.
- The merge wrapper mutates only with `--merge --expected-head <post-push-head-sha> --method
  <merge-method>`, and rejects `--allow-unpinned-head` outright. There is no unpinned merge. A
  missing pin, or a pin that no longer matches the live head, refuses the merge: re-snapshot and
  reassess the new head rather than reaching for an override, so no unattended unpinned merge
  exists. The pin is carried through to GitHub's own server-side head match (the async merge API's
  `sha`, or `gh pr merge --match-head-commit`), so the refusal holds on GitHub's side as well as in
  the wrapper. Which API merges is in §Async Merge Path below.
- The merge wrapper never uses `--admin`, and it cannot resolve threads, post replies, or
  force-push. It merges or it refuses.
- The merge CLI refuses a dependency-manager-authored PR absent `--allow-dependency`, and refuses
  to merge on an unprotected base, meaning zero required reviews AND zero required status contexts,
  when the PR author is not one of `<self-logins>`, or when a `<self-logins>` author's base is not
  the repository's default branch, absent `--allow-unprotected`. The self exemption covers the
  solo-owner repository whose default branch carries no rules; it does not cover a merge onto
  another branch (a stack layer, or any other feature-onto-feature merge), where the default
  branch's required checks never governed the merge. `--stacked-prs` changes this for a native
  stack layer only (§Async Merge Path). Both
  overrides are human decisions, never passed autonomously. The held dependency-manager set is the
  built-in dependabot/renovate bots plus, when `babysit_extra_dependency_manager_logins` is
  configured (non-empty, not a literal unexpanded token), the logins appended via
  `--extra-dependency-manager-logins <extra-dependency-manager-logins>`. Supply it on every merge
  command below, exactly as `--method` is, or those extra bots are not held.
- The merge wrapper's `--autopilot-merge-tier` flag layers the tier criteria (issue-linked,
  lane-authored, no blocking label, a distinct-bot approval on the live head, no human blocking
  comment) onto the base gate. It is **fail-closed**: the umbrella flag refuses (exit `3`) unless
  `--lane-logins` and `--approver-bot-logins` are non-empty and the effective block labels are
  non-empty (the `--block-labels` fallback plus the target repository's `babysit_merge_block_labels`;
  the gate checks that set after it reads the repository's policy). Supplying any of those three
  flags without the umbrella is a usage error (exit `2`). Absent the flag the gate is
  exactly its prior self, so worker/autopilot's existing gate-proven merges are unchanged. This
  tier is only ever wired when `babysit_autopilot_merge_tier` is enabled.
- The resolve wrapper's mutating forms are `--autonomous --resolve` (worker tier, constrained by
  the pre-push-outdated rule in `orchestration.md`), `--resolve --include-human` (autopilot's
  addressed-thread widening), and `--independent-resolver --resolve` (the evidence-gated third
  mode below). `--autonomous` admits only threads GitHub marks `isOutdated`. The worker must
  additionally confine its resolves to threads already outdated in the PRE-push snapshot; that
  pre-push-outdated rule is agent discipline, not machine-enforced, so a thread a worker's own push
  merely displaced (`isOutdated` flipped while both comment pins still match) is still resolvable by
  the script. Under `--resolve --include-human` the script still cannot merge, post replies, or
  dismiss reviews.
- **`--independent-resolver` is a third mode, not a widening of `--autonomous`.** `--autonomous`
  admits only `isOutdated` threads, and `isOutdated` means the referenced code MOVED, so on a
  prose or documentation PR, where a finding is normally addressed by rewriting elsewhere in the
  file, the anchor never moves and the guard refuses a genuinely addressed finding forever. That
  left an autonomous prose lane with no sanctioned route to zero unresolved threads. This mode
  replaces `isOutdated` with two other properties. The first is **independence**: it is dispatched
  to a fresh context that is neither the merging worker nor the author of the fix, so the actor
  resolving is not the actor whose permission slip it is. That is a property of the dispatch and
  cannot be checked by the script, which is precisely why the second half is machine-checked
  here. **Who dispatches it, and the D7.5 ledger the dispatched agent owes before calling the
  wrapper, live in [`independent-resolution.md`](independent-resolution.md)**; this bullet is the
  wrapper's half of the contract, not the route's. Everything `--autonomous` guards besides
  `isOutdated` is retained: bot-only authorship, a
  single pinned `--thread-id` with both TOCTOU pins, and the security/P1 bright line, because this
  is still an unattended path. `--autonomous`, `--include-human`, and `--allow-unpinned-thread`
  are each refused alongside it (exit `2`): the first because the two modes answer for different
  actors, the second because widening authorship in the same call that drops `isOutdated` is the
  combination nothing would guard, the third because there is no unpinned unattended resolve.
  Bulk is refused in **every** mode here, list included: evidence is a claim about one finding.
- **The disposition evidence contract, validated against the world.** `--disposition` names the
  claim and carries exactly its own evidence flag. A mismatched or surplus flag is a usage error,
  so the script always validates what was actually asserted:
  - `fixed` + `--fix-commit <sha>`: the SHA must be **reachable from the PR's current head
    commit**, resolved through the head repository so a fork PR compares correctly. Existence
    elsewhere in the repository is not evidence that this PR carries the fix.
  - `deferred` + `--tracker-item <owner/repo#N|#N|N>`: the item must exist and still be **open**.
    A closed follow-up is not a deferral; it is the finding disappearing. The script cannot check
    D4.6's scope test, so claim `deferred` only for a structural, urgent-but-cannot-land, or
    fix-blocked-on-research finding; a small or medium one is never `deferred`.
  - `linked-pr` + `--linked-pr <N>`: the fix D4.6's scope test placed in a separate PR. `N` must
    be a different, non-draft PR whose head is in the same repository, cited (`#N` or its URL) in a
    **reply** on the thread by someone other than the opener, and **open or merged**: a PR closed
    without merging is the fix disappearing.
  - `incorrect` + `--counter-evidence <text>`: the text must already appear in a **reply** on the
    thread, posted by **someone other than the thread's opener**. Excluding the opening comment
    alone is not enough: the mandated classification reply restates the finding's own text, so a
    finding bot that also replies on its own thread would supply the very words asserted as the
    rebuttal, the finding rebutting itself. A *different* bot's reply and the caller's own reply
    under a `--self-logins` identity both stay admissible, because those are the independent
    parties the disposition is about. The rebuttal has to be visible where the finding is, not
    only on the command line of the process resolving it.

  Missing, unparsable, or unverifiable evidence **refuses**: refusing leaves the thread
  unresolved, which is the recoverable direction, while a suppressed finding is not. Each refusal
  is its own per-thread `action`: `refused-fix-commit-not-on-head`,
  `refused-tracker-item-not-found`, `refused-tracker-item-not-open`,
  `refused-counter-evidence-not-found`, `refused-linked-pr-not-cited`,
  `refused-linked-pr-not-found`, `refused-linked-pr-closed`, `refused-linked-pr-fork`, `refused-linked-pr-draft`, and `refused-evidence-unverifiable` for an API that could
  not be consulted, kept distinct so an outage is never reported as a false claim. **Only a
  confirmed HTTP 404 earns an evidence-specific refusal.** Every other operational failure, whether
  403, 429, 5xx, a timeout, an unreachable API, or no HTTP response at all, reports
  `refused-evidence-unverifiable`, because telling a caller to replace evidence that may be
  perfectly valid is the wrong instruction when the real fix is to retry. Evidence is validated in
  list mode too, so a dry run proves the evidence rather than predicting the resolve, and a
  `--thread-id` whose pins have already drifted reports `refused-stale-pin` in list mode as well.
  A dry run predicts what `--resolve` would actually do, in every mode.
- **A multi-finding thread is refused outright** (`skipped-multi-finding-thread`). One
  `--disposition` is a claim about ONE finding, while `resolveReviewThread` clears the whole
  thread and drops every comment it carries out of the readiness denominator, so evidence for
  finding A would suppress an unaddressed finding B and let the merge gate pass over it. This is
  the D7.5 whole-thread eligibility rule (`reference/review-discipline.md`) enforced
  mechanically rather than left to the caller. The count comes from the shared severity
  vocabulary over the thread's own comments, with a self classification reply's table rows
  stripped so the worker's own echo of a finding is not counted twice, and it fails closed: a
  truncated comment page could hide another finding, so an unknown count refuses too. Such a
  thread escalates. The guard is scoped to this mode alone. `--autonomous` rests on `isOutdated`,
  which GitHub computes for the thread as a whole rather than per finding, so it carries no
  per-finding claim to under-cover.
- **Thread-pin pair rule.** Any `--thread-id` resolve must also pin both
  `--expected-comment-count <n>` and `--expected-last-updated <ts>`, read from that thread's
  `commentCount` and `lastCommentUpdatedAt` in the same list output used to vet it. The wrapper
  refuses a target whose live comment count or latest comment-edit timestamp no longer matches
  either pin, so a reply added or a comment edited after vetting blocks that thread instead of
  being silently swept in. A thread id alone is never enough (the live thread is re-fetched at
  execution time), and a comment count alone is never enough (an edit leaves the count
  unchanged). The pins enforce **comment state only**: drift in the comment count or the latest
  comment-edit timestamp blocks the thread, and nothing else about the thread is pinned. A
  `--resolve --thread-id` missing either pin is refused before anything is fetched or resolved,
  unless the caller supplies the explicit `--allow-unpinned-thread` override, which belongs to no
  unattended path (`--independent-resolver` refuses it outright).
- **Parse JSON, never trust exit codes alone.** Both wrappers emit structured JSON; confirm what
  actually happened from each target's `action` field. For a resolve, exit `10` is a reliable
  "nothing was resolved" signal (a stale pin refused, the thread was skipped, or the mutation
  failed), but exit `0` is not by itself proof of success for a given thread. It also covers
  list mode and a multi-thread run where some other thread resolved while this one did not.
  Treat a thread as cleared only when its own entry shows `"action": "resolved"`, and a merge as
  performed only when the merge output's `action` field says so and `merged` is true;
  `"action": "auto-merge"` means armed, not merged, and `"action": "enqueue"` with
  `enqueued: true` means queued, not merged. The resolve action vocabulary is
  `resolved` against `skipped-*`, the `refused-*` family (`refused-stale-pin` and the evidence
  refusals above), and `resolve-failed`; read the run's `resolvedCount`/`eligibleCount` summary
  alongside the per-thread entries before reporting or re-checking the merge gate.

### Async Merge Path

A ready PR merges through GitHub's async merge API, called with `gh api` (`gh` has no subcommand for
it): a `PUT` to the PR's `merge-async` endpoint, then a `GET` on the request's UUID.

- **Which API.** Async when the base is the default branch, when it requires a merge queue, or when
  the PR is a native stack member under `--stacked-prs`, the bottom layer on any trunk included:
  GitHub documents the async API as the required API for merging a stacked PR. Any other base keeps
  `gh pr merge`, and so does every `--auto` arm: the async API has no auto-merge form. Without
  `--stacked-prs` the gate never reads stack membership, so a bottom layer on a non-default trunk
  goes to `gh pr merge`, which GitHub refuses for a stacked PR; that fails closed. On the default
  branch a 404 from the endpoint (a host that lacks it) falls back to `gh pr merge` with the same
  pin; a queue or a stack member has no other API and holds.
- **Request.** `sha` is always the head the gate just evaluated: `--allow-unpinned-head` waives only
  the `--expected-head` argument, never the pin, and `gh pr merge` carries the same head as
  `--match-head-commit`. `merge_method` is sent for a direct merge only,
  `merge_action` is `direct_merge` or `merge_queue`, and `bypass_rules` is always `false`. No
  API-version header is sent: the endpoint is documented under the default version as well.
- **Result.** The gate polls for up to 60 seconds; a 200 means already merged or already queued. A
  409 means a request is already pending, possibly another actor's. When its body states that
  request's `expected_head_sha` or `merge_action`, each must equal this run's pin and action;
  otherwise the gate does not poll it, reports it as `merge.conflictingRequest` with exit `10`, and
  records it as pending, since it can still merge. A reported merge is confirmed by reading the PR
  back, merged and at the pinned head: a contradiction is not counted; a merge at another head
  reports `merged: true`, `merge.mergedHead`, and exit `10` for a human; a failed read reports
  `merged: false`, `mergeUnconfirmed: true`, and exit `10`, so re-run the read-only check rather
  than call it merged. A 400 is basic PR state only: GitHub does not evaluate rules when it accepts
  the request, which is why the readiness gate always runs first.
- **A request still pending at the bound stays live.** GitHub documents no route to cancel one, so
  it can still merge after a hold appears that would refuse a new request. The gate records its UUID
  under `--state-dir` and every later run, read-only or merging, reads it first: while it is
  pending, or cannot be read, the run reports `action: merge-pending` with that hold first in
  `blockers`, exit `10`, and sends nothing. A record whose request id is not GitHub's UUID shape is
  corrupt: it is never put in an API path or cleared, and holds the same way until a human inspects
  it. A finished request, or one GitHub no longer returns (404; GitHub keeps a result 24 hours
  after its latest update), clears the record and shows as `pendingMergeRequest`; the gate keeps no
  local age limit of its own. A request that finished merged is first checked against every head
  the gate evaluated, the PR's and, for a stack, each lower layer's, recorded with it
  (`pendingMergeRequest.verification`). A mismatch puts an escalation first in `blockers` with exit
  `10`; heads that cannot be read back keep the record, hold the same way, and are re-checked next
  run. When every head matches, the run reports the merge even though the gate now reads a closed
  PR: `merged: true`, `ready: true`, empty `blockers`, `merge.source: pendingMergeRequest`, exit
  `0`, with `action` unchanged. Report a merge-pending PR as "merge may still land", never as held. Without `--state-dir`
  nothing is recorded and a later run cannot see the request, so `--state-dir <state-dir>` rides on
  every merge form.
- **Merge queue.** A default-branch base that requires a merge queue is no longer a blocker. Once
  every other condition holds, the merge enqueues (`action: enqueue`). `enqueued` is final for the
  request and is not a merge. Enqueueing is a merge, so only a tier that may merge enqueues, and
  auto-merge is never armed over a queue. A queue on any other base keeps the hold.
- **A `gh pr merge` the queue took.** `gh pr merge` adds a PR to the queue on any base that has
  one, `--auto` or not, and exits `0`, so a queue the branch-rules read did not report would read
  as a merge or an arm. After every successful `gh pr merge` the gate reads the PR's queue state
  back over GraphQL. In the queue, it reports `action: enqueue`, `enqueued: true`,
  `autoMergeEnabled: false`, `merged: false`, and `mergeQueue` with the entry's `state` and
  `position`. Not yet in the queue but armed to enter it, it stays `action: auto-merge` with
  `mergeQueue.entersWhenReady: true`. Neither queued, armed, nor merged, the read may simply
  trail the merge, so the gate re-reads it a few times at the async poll interval, well inside
  that path's 60-second bound. Still unseen, it reports `action: merge-pending`, `ready: false`,
  `mergeQueue.unconfirmed: true`, and exit `10`, and records the success under `--state-dir` as
  an unconfirmed queue entry. A base without a queue keeps the report it had; a failed read keeps
  it too and names the failure in `merge.queueReadError`.
- **A queued PR is confirmed on later runs.** With `--state-dir`, an enqueue from either path is
  recorded with the vetted head, and every later run reads the entry first. Still in the queue: the
  run reports `action: merge-pending`, `enqueued: true`, and `mergeQueue`, with the queue hold first
  in `blockers`, exit `10`, and sends nothing. Merged: the head is checked as for a pending
  request, and a match reports `merged: true` from `pendingMergeRequest`, exit `0`. Out of the
  queue unmerged: the run reports `dequeued: true` with that hold first in `blockers`, exit `10`,
  clears the record, and the next run gates it again. Armed to enter the queue, it holds as merge
  pending with `mergeQueue.entersWhenReady: true`. An unreadable queue keeps the record and holds
  as merge pending. An unconfirmed entry that reads back queued, armed, or merged is confirmed and
  reported that way; one still unseen holds as merge pending with `mergeQueue.unconfirmed: true`,
  sending nothing, and the second later run that finds it unseen reports it `dequeued`.
- **Stacks (`--stacked-prs`).** Only a native stack qualifies: the PR's REST `stack` object. A PR
  merely based on another PR's branch keeps the non-default-base hold. The layer is judged against
  the stack's trunk, every open layer below it runs the same gate pinned to the head the stack
  listing reports, and the chain must link each layer to the head of the one below and the lowest
  to the trunk. A blocker on any layer holds the whole merge, and under `--auto` so does a layer's
  missing AI review check. A trunk that requires a merge queue holds. The request's `sha` pins the
  top layer only, so the gate re-reads the stack immediately before the request and refuses if any
  open lower layer was pushed, added, or closed since evaluation. After a reported merge it checks
  that every lower layer merged at the head it evaluated; a mismatch reports
  `stackVerification.verified: false` with exit `10` (`merged` stays true) and goes to a human. A
  request that completes in a later run gets the same check from its pending record. What remains
  is the window from the request to its completion: a lower-layer push in that window is not pinned
  by GitHub and lands unvetted, caught only after the fact. `--stacked-prs` therefore assumes only
  trusted actors can push to the lower layers' branches; leave it off where anyone else can.

**Claim, basis, as of, recheck:** the endpoint's request fields, statuses, a pending request's
`details` (`expected_head_sha`, `merge_action`), 409, 200, and 400 semantics, its 24-hour result
retention, the absence of any route to cancel a request (the page documents only the `PUT` and the
`GET`), its listing under the default API version, and its inclusion of every open downstack PR,
[merge a pull request asynchronously](https://docs.github.com/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request-asynchronously)
and [async merge API GA](https://github.blog/changelog/2026-10-01-github-async-merge-api-generally-available/);
stack membership, trunk rules, and merge behavior,
[about stacked pull requests](https://docs.github.com/en/pull-requests/get-started/about-stacked-prs)
and [stacked pull request endpoints](https://docs.github.com/en/rest/pulls/stacks); 2026-10-02.
Recheck when a `gh` release adds an async-merge command, when either REST page changes a status or
field, or when stacked pull requests leave public preview or GitHub announces merge-queue support
for stacks.

**Claim, basis, as of, recheck:** that `gh pr merge` adds a PR to a required merge queue, or
enables auto-merge until its checks pass, and exits `0` for a PR already queued,
[merging a pull request with a merge queue](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/merging-a-pull-request-with-a-merge-queue),
the [`gh pr merge` manual](https://cli.github.com/manual/gh_pr_merge), and
[`pkg/cmd/pr/merge/merge.go`](https://github.com/cli/cli/blob/trunk/pkg/cmd/pr/merge/merge.go);
the queue fields read back (`isInMergeQueue`, `isMergeQueueEnabled`, `mergeQueueEntry`,
`autoMergeRequest`), the
[`PullRequest` GraphQL object](https://docs.github.com/en/graphql/reference/objects#pullrequest);
why a PR leaves the queue, the first page's removal section; 2026-10-04. Recheck when a `gh`
release changes how `gh pr merge` treats a queue base, or the GraphQL schema changes a queue field.

### Lane-pinned merge authorization: report, don't re-pin

A single-PR merge-capable invocation dispatched by `source-control:babysit-loop`'s rung partition,
at **any** merge-capable tier, worker and autopilot alike, carries the lane's **partitioned head
SHA** as its merge authorization, supplied in the invocation brief: the merge gate's
`--expected-head` is that partitioned head, never a fresher head this invocation picked itself. The
lane's partition class-checked exactly that head's diff (work class C2/C3 against the C4/C5 floor),
and this skill's merge gate does not class-check, so a worker push that moves the head off the pin
is not a cue to re-pin. It is the end of this invocation's merge authority. The pinned gate's
head-match refusal enforces the boundary deterministically; the invocation reports the new head and
stops, and the lane reruns its partition on the post-push diff before any merge-capable
re-invocation (`babysit-loop/SKILL.md`, Cycle shape step 3, "The verdict authorizes a head SHA, not
the PR"). Every other invocation of this skill re-pins to the vetted post-push head exactly as
Autopilot step 3 describes.

### Merge-lane auto-merge

Only a lane-pinned invocation (above) adds `--auto` to its merge gate command. The lane's
partition is the only class check, so the PR is already C2 (mechanical) or C3 (scoped); a C4
(structural) or C5 PR never reaches a merge-capable invocation and waits for the user. With
`--auto`, a PR that is ready except for running checks gets
`gh pr merge <N> --auto --squash --match-head-commit <pin>` instead of a hold, and only when:

- both AI review checks, `review / claude-review-status` and the security lane's
  `security-review / security-review` (matched by its whole name, never by the job segment alone),
  report success on the live head, which is the pinned head (a missing, skipped, failed, or
  running check holds, and so does a head that moved off the pin). Any
  `claude-security-review-status` check the rollup also carries must succeed as well;
- no review thread is unresolved, and every other gate blocker is clear.

The gate's check names follow the lane jobs the ci-workflows reusables define.

- **Pointer**: when a lane check name in a rollup does not match the gate's, fetch the job keys
  in [claude-review.yml](https://github.com/melodic-software/ci-workflows/blob/main/.github/workflows/claude-review.yml)
  and [claude-security-review.yml](https://github.com/melodic-software/ci-workflows/blob/main/.github/workflows/claude-security-review.yml)
  live.
- **As of**: 2026-10-03
- **Recheck trigger**: a ci-workflows release that renames or adds a job in either reusable.

Any other running check does not hold the arm: GitHub waits out a running required check
(`ci-status`) itself, and a non-required check never holds a merge.

To retry an AI review check that failed on a rate limit (HTTP 429), rerun the whole workflow run
with `gh run rerun <run-id>`, never `gh run rerun --failed`. `--failed` reruns only the failed
`-status` job, which re-reads the cached rate-limit output of the `review` job that succeeded and
fails again.

The reason: `ci-status` is the only required check and does not wait on the review workflows, so
auto-merge enabled earlier could merge before AI review posts. A fully ready PR still merges in
the same run, through §Async Merge Path. A base that requires a merge queue, and a stack layer, are
never armed: they wait until fully ready and then enqueue or land. The gate's JSON reports `autoMerge.ready` and `autoMerge.blockers`; a successful
arm exits `0` with `"action": "auto-merge"`, `autoMergeEnabled: true` and `merged: false`, so it
is reported as armed, not merged, and the PR stays in the queue with its worktree kept. An arm
GitHub put straight into a merge queue the rules read missed reports `"action": "enqueue"`
instead (§Async Merge Path, "A `gh pr merge` the queue took"). Nothing
else enables auto-merge: not a Worker Contract subagent (`orchestration.md`), not a work-items
worker lane, not a standalone invocation, not `/source-control:pull-request`. The `worker` tier
name is unrelated: a lane-pinned invocation at that tier is the merge lane.

A push by a writer leaves auto-merge armed, and the new head would merge on `ci-status` alone.
Verified 2026-09-26 against GitHub's [Automatically merging a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request),
which disables auto-merge only when "someone without write permissions pushes new changes to the
head branch or switches the base branch". Recheck when that page names another event that disables
auto-merge, or a GitHub changelog entry changes auto-merge behavior on push.
So every push path disarms it: `refresh_pr_branch.py` before updating the branch, `lane_push`
before and after each lane push in [loop.md](loop.md), and in
[orchestration.md](orchestration.md) the fix worker (Worker Contract and Worker Prompt Template)
and the orchestrator's conflict-resolution push (Orchestrator Contract) before and after pushing.
The lane re-arms once both review checks pass on the new head.

### Security/P1 escalation has no exception; the pre-escalation resolver is bound by it too

Escalating a security/P1 thread instead of resolving it holds in every tier and every mode,
autopilot and `--independent-resolver` included. The wrappers refuse a severity-flagged thread
whoever asks, so no dispatch path can reach past it (`--independent-resolver` above, "the security/P1
bright line, because this is still an unattended path"). The loop-lane convention's one named
paired-argument exception (§1) widens the **merge rung** for a single run; it never widens the
severity bright line, and reading it as an exception to this rule would describe an unreachable
path.

What the paired-argument invocation *does* unlock is the pre-escalation resolution dispatch, and
that path is this narrow:

- **Only one dispatch path.** The `source-control:babysit-loop` explicit-`autopilot` pre-escalation
  resolver, the subagent that lane dispatches when a caller typed both the literal `autopilot`
  tier argument and the dedicated raise argument `--merge c3-this-run` on that invocation's own
  line. No other invocation of this skill, at any tier, ever reaches it. The
  orchestrator-side independent resolution dispatch
  ([`independent-resolution.md`](independent-resolution.md)) is **not** a second path to it: the
  wrapper's severity bright line refuses a security/P1 thread on that route
  (`skipped-severity-marked`), so it escalates exactly as it did before.
- **Only a fresh, independent context.** The dispatch must share no conversation history with
  whatever produced the PR or previously replied on the blocking thread (the convention's §3
  independence requirement). A continuation of the authoring session, or a re-invocation of the
  subagent that already commented on the blocker, never qualifies, regardless of what it claims
  about itself. This is a contract on how the lane dispatches, not a credential the dispatch
  presents: a run that cannot establish it is fresh escalates.
- **Only through these wrappers.** The resolution runs through the guarded-mutation path above,
  with every pin, refusal, and JSON-parse rule intact. The dispatch changes who may attempt the
  resolution, never what the wrappers permit, which is exactly why the severity refusal above
  still lands on it.
- **Never anything else.** It does not widen what counts as genuinely "addressed", never applies
  to a PR whose work item classifies C4 (structural) or C5 (untrusted-provenance), and never
  substitutes for escalation when the resolution is unresolved or the resolver is uncertain.

## Autopilot Merge Tier: Enabled-Path Mechanics

Reachable only while `babysit_autopilot_merge_tier` is enabled; absent that flag none of this
section applies and autopilot merges through the base path. This is the single home for the
enabled-path merge command that autopilot's step 3 in `SKILL.md` points at, so the base and
enabled-tier merge paths never drift apart. The tier is off by default; enabling it is a separate
announced operator step.

- **Enabled-path merge command.** After the worker's final push and a fresh post-push snapshot
  (or the exact pushed commit, vetted), merge on that post-push head by layering the tier flags
  onto the base gate command. This is the *only* autopilot merge path once the tier is enabled,
  never the four-flagless base command, which would ignore every tier criterion:

  ```text
  bash "<plugin-root>/scripts/source-control-babysit-merge" owner/repo#N --allowed-owners <watched-owners> --self-logins @me,<self-logins> --merge --expected-head <post-push-head-sha> --autopilot-merge-tier --lane-logins <lane-logins> --approver-bot-logins <approver-bot-logins> --block-labels <merge-block-labels> --extra-dependency-manager-logins <extra-dependency-manager-logins> --state-dir <state-dir>
  ```

  The umbrella `--autopilot-merge-tier` is fail-closed: it refuses (exit `3`) unless
  `--lane-logins` and `--approver-bot-logins` are supplied and the effective block labels are
  non-empty, and any of those three flags without the umbrella is a usage error (exit `2`).
  `--block-labels` is the deprecated `userConfig` fallback: omit it when `babysit_merge_block_labels`
  is unset and the target repository declares the key, and the gate refuses (exit `3`) when neither
  source supplies a label. Add `--method <merge-method>`,
  `--extra-dependency-manager-logins <extra-dependency-manager-logins>`, and the review-settle pair
  `--review-bot-logins <review-bot-logins> --review-settle-minutes <review-settle-minutes>` when
  configured, exactly as for the base merge readiness gate above (omit each when its value is empty
  or a literal unexpanded token; omit the settle pair as a pair, never one half), and
  `--stacked-prs` when `babysit_stacked_prs` is `true`.

- **Second-account approve mechanic.** The approving review the gate's distinct-bot criterion
  requires is submitted out-of-band by the agent. The gate only verifies one exists on the live
  head and never creates it. Bind a **distinct** identity (one of the `<approver-bot-logins>`
  accounts, never the PR author or a lane identity), run a **genuine** review pass, through a
  review skill/plugin when one is installed and otherwise an equivalent thorough manual review (this
  skill declares no review-plugin dependency; the gate requires only that the resulting approval
  exists on the live head, not that a particular tool produced it), and only when that pass is
  clean submit the approval under that identity:

  ```text
  GH_TOKEN=<approver-bot-token> gh pr review owner/repo#N --approve --body "<clean-review-summary>"
  ```

  `gh auth switch --user <approver-login>` before a plain `gh pr review … --approve` is the
  equivalent when the approver is a persisted gh account rather than a bound token. Submit on the
  live head so the gate's head-unchanged-since-review pin (`--expected-head`) still holds; any
  push after the approval invalidates it and the review pass must be re-run against the new head.
  Never approve on an unclean pass, and never under the author or a lane identity. Either
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
  PRs hit. It must always execute and produce a non-skipped result on the pinned head. Where the
  review workflow is not a required context, or can skip on those PRs, do not enable the tier: this
  is an operator enabling precondition, verified before the flip, not something the merge gate can
  self-enforce.

- **Bot-review precision precondition (enabling).** Enable the tier ONLY after the fleet's bot-review
  lane has demonstrated recorded precision over a sustained window, the same earned-promotion trigger
  ADR 0002 sets for flipping an advisory review lane to a blocking gate. The tier lets a
  fleet-produced approval satisfy a required-review ruleset, which promotes that lane from advisory to
  merge-deciding, so it is earned on that same evidence bar: precision proven over a sustained window
  and ratified as a reviewed change citing that evidence. It is never a calendar flip, and operator
  discretion alone is insufficient. Absent a recorded precision window for the reviewing bot, do not
  enable the tier. The requiredness precondition above governs whether the review workflow ran; this
  one governs whether its verdicts have earned the authority to stand in for a human approval, and
  like requiredness it is an operator enabling precondition the merge gate cannot self-enforce.

## Harness Permission Layer

A permission denial can come from two different layers. Tell them apart before deciding how to
react. Never retry or route around either one.

- **Harness/runtime permission denial.** The host runtime's own permission layer (its rules plus,
  in some runtimes, an auto-mode safety classifier) blocks a tool call before any skill script
  even runs; this is a policy decision made by the harness, not by this skill. Treat it as the
  "permissions are missing" Stop And Ask case above: do not retry the call, do not route around
  it with a different tool or approach, and report exactly what was attempted and that the
  harness blocked it.
- **Script-level gate denial.** A skill script or wrapper runs to completion and itself returns a
  deliberate non-ready or refused result: the merge wrapper reporting `ready: false` with a list
  of blockers, or the lease helper exiting `3` because the requested lease is already held by
  another run. This is expected, structured output from the script's own gate, not a permissions
  problem. React to the reported blockers or exit code per the relevant reference file; never
  bypass the gate and never retry as if it were a transient failure.

The harness layer is independent of, and sits above, the wrapper gates: it can deny a mutation
the wrapper gate has already proven ready and in-tier. That denial is an environment-level
ceiling this skill's own contract has no authority over. It is a normal, expected outcome to plan
for, not a bug in this skill, a stalled worker, or a reason to retry with broader permissions.

Configuring that host layer means deciding which of this lane's entry points mutate, which flags
gate which guard, and where each refusal is enforced. Those facts are in
[reference/guard-contract.md](guard-contract.md), generated from the table
`scripts/tests/test_guards.py` executes against the real entry points, so a rule written against
a row cannot silently outlive the guard it cites. Cite a row ID; do not restate the behavior in
the consuming configuration.

**Classifier denials are not settled.** A classifier verdict may not carry the same finality as a
rules-layer denial: a retried classifier denial can succeed. Nothing in this file resolves whether
that makes a retry appropriate, so follow the never-retry bullet above for classifier denials too,
and report the denial rather than reasoning about the classifier. The Lane-Script Reachability
section that follows is about whether the lane's own scripts are reachable at all, not about what
to do after a denial; read its restatement of the denial contract as inherited from the bullet
above, not as fresh confirmation of it.

### Lane-Script Reachability (operator prerequisite)

That ceiling reaches the lane's own scripts, not just GitHub-mutating commands. Every tier proves
readiness with a bundled script: the Python engine and gates under `skills/babysit-prs/scripts/`,
the guarded wrappers and the plugin-scope helpers under `scripts/` that the
Python-free degrade path itself depends on, including the **read-only** merge-readiness check,
which mutates nothing and is still a shell invocation the host may deny. So those scripts being
invocable without a per-call denial is a declared prerequisite of the lane, on the same footing as
Python.

**The no-degrade half is narrower than the prerequisite, and that distinction is the point.** It
binds the paths that *prove readiness*: the readiness gate and the read-only merge-readiness
check. Unlike Python those have no degrade tier, because there is no permission-free path to a
proven readiness verdict, and a verdict that was never produced cannot be handed to anyone. A
denied *mutation* is not in that set: there the gate has already proven the PR ready, so
Pinned-Command Degradation below degrades it to a ready-to-execute operator handoff. So the
prerequisite covers reachability of every bundled script; the no-degrade rule covers the check
paths only.

**What this prerequisite rests on.** With `autoMode.classifyAllShell` enabled, every narrow Bash
allow rule is suspended, including grants purpose-built for this lane's scripts, so under that
configuration even the compliant `bash "<plugin-root>/scripts/…"` form reaches the classifier
like any other command. Reachability is therefore a property of the operator's configuration, never
of the path form alone. A denial of a raw interpreter invocation (`python …/babysit_merge.py …`)
says nothing about the sanctioned form; that spelling is forbidden by this file regardless.

The grant is the operator's, never the plugin's. A plugin cannot ship permission rules, and an
agent must not broaden its own. The allow-rule shape guidance, and the official sources behind it,
are owned by the marketplace's permission-rule-hygiene convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/permission-rule-hygiene/README.md>.

Reachability is **not** implied by a `permissions.allow` rule. Whether shell allow rules resolve at
all while a host safety classifier is active is governed by the host's own auto-mode configuration.
Read [auto-mode-config](https://code.claude.com/docs/en/auto-mode-config) for the current
semantics of `autoMode.classifyAllShell`, of the prose `autoMode.allow` exceptions, and of which
settings scopes the classifier reads `autoMode` from; never infer them from this file, and never
assume a prose entry guarantees a given command runs. What the lane requires is only the outcome:
a configuration under which this plugin's bundled scripts, invoked in the path forms this file
mandates (§Guarded Mutation Wrappers), run without a denial. The operator confirms the effective
configuration with `claude auto-mode config`.

**A denied gate is never downgraded to weaker evidence, and the gate says so itself.**
`babysit-readiness-gate.sh` emits exactly one `READINESS_*` line on stdout on **every** run that
attempts a check, failure paths included. The sole exception is the help form (`--help` or its
`-h` alias, which share one branch), which prints usage and
exits 0 with no verdict; that form is not a check run, it is the non-mutating setup canary
([`skills/setup/SKILL.md`](../../setup/SKILL.md) "Lane-script reachability").
`READINESS_UNPROVEN reason=<bad-args|identity-unresolved|prereq-missing|comments-unreadable|checklist-unreadable|fetch-failed> pr=<n>`
is a third verdict alongside `READINESS_OK` and `READINESS_BLOCKED`, and it means readiness was not
proven. Readiness is declared by quoting the verdict line verbatim in the iteration report
([loop.md](loop.md) §5.5), so a readiness claim with no verdict line to quote is unproven on its
face. That is both the mechanical half of this rule and its limit: a gate the harness never let run
cannot report its own non-invocation, which is why the quoted-verdict requirement lives on the
report rather than inside the script.

When readiness is not gate-proven, whether an emitted `READINESS_UNPROVEN` or a call the harness
denied outright, `mergeStateStatus`, the check rollup, or any other live `gh` state a worker reports is
NOT a substitute verdict: it misses exactly the cross-checks the gate exists to run (dependency
author, unprotected base, self-login exemption, head match). Report that PR as **readiness
unproven**, quoting the verdict line when there is one and naming the exact command attempted when
the harness blocked the call, and surface the prerequisite above once for the cycle rather than
re-attempting the call per PR. Pinned-Command Degradation below covers the denied-*mutation* case;
this clause covers the denied-*check* case, which has no ready-to-execute handoff precisely because
nothing was ever proven ready.

### Pinned-Command Degradation

When the runtime denies a guarded mutation that this skill's own gate already proved ready,
degrade that one PR to the same outcome default (safe) mode reports for a ready PR: mark it
**"ready, awaiting human execution"** and surface the exact, fully-argument-pinned command for the
operator to run, in the `scripts/`-path wrapper form (§Guarded Mutation Wrappers), which runs the
wrapper with every guard intact. The case is distinguishable because the wrapper itself never ran,
so there is no wrapper exit code and no `blockers` output to react to. Never surface a workaround,
and never a raw-Python re-spelling of the command that would dodge the wrapper's guards and the
narrow allow rule.

For a merge:

```text
bash "<plugin-root>/scripts/source-control-babysit-merge" owner/repo#42 --allowed-owners <watched-owners> --merge --expected-head <post-push-head-sha> --method <merge-method> --extra-dependency-manager-logins <extra-dependency-manager-logins> --review-bot-logins <review-bot-logins> --review-settle-minutes <review-settle-minutes> --state-dir <state-dir>
```

When the autopilot merge tier is enabled, this degraded handoff carries the tier flags too:
surface the enabled-path command from Autopilot Merge Tier: Enabled-Path Mechanics above, not this
flagless base form, so the operator's manual merge is held to the same tier criteria the blocked
gate would have enforced.

For a thread resolve, never surface a bare `--autonomous` or `--include-human` resolve: both
re-fetch the live thread list and re-evaluate every eligible thread at execution time, so an
unpinned command could resolve a thread this run never vetted, one opened or changed after its
assessment. Pin each vetted thread individually (the wrapper accepts exactly one `--thread-id`
per invocation; issue one pinned command per thread) with the thread-pin pair rule above:

```text
bash "<plugin-root>/scripts/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins> --autonomous --resolve --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the unattended-worker case, or

```text
bash "<plugin-root>/scripts/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins> --resolve --include-human --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the autopilot case. This degradation is a successful, material finding to report, not a
failure and not a blocker to resolve. Continue the rest of the queue exactly as if the mutation
had been refused by the wrapper's own gate. Hand off the pinned command and move on: the
no-background-monitor clause (Worker Contract, `orchestration.md`) governs this point too, so a
harness-blocked merge is never a reason to arm a watch that sits waiting to retry it. When this
agent (or the operator) later checks
whether a deferred command actually acted, parse the JSON `action` field per Guarded Mutation
Wrappers above, never the exit code alone, before treating the thread as cleared or the merge
as done and re-running the gate.

## Never Do Automatically

- Merge in default (safe) mode, or merge through any path other than the pinned merge wrapper's
  gate. Worker and autopilot merge only a PR that gate proves 100% ready, or arm auto-merge
  through it under Merge-lane auto-merge.
- Generate an approving review to satisfy a required-review ruleset, or merge on a review the
  fleet produced itself, **except** under the autopilot merge tier, a deliberate, config-gated
  opt-in that is off by default. It engages only when the operator sets
  `babysit_autopilot_merge_tier`; enabling that flag is a separate, announced operator step,
  never a default and never a side effect of another change. When the tier is enabled, a second
  bot account (author ≠ approver) runs a **genuine**
  review pass and submits an approving review **only when it is clean**, and the pinned merge
  wrapper's `--autopilot-merge-tier` gate then merges **only when every criterion holds**, each
  enforced deterministically:
  - required checks green, including the review workflow, with the base ruleset satisfied
    (`mergeStateStatus` CLEAN, and the ruleset itself is never bypassed);
  - the PR is issue-linked (carries a closing-issue reference);
  - the PR is authored by a configured pipeline lane;
  - no human `CHANGES_REQUESTED`, no human blocking comment, no unresolved review thread;
  - no configured do-not-merge label is present;
  - the PR's linked issue carries no unratified `Decision defaulted` marker. The triage lane
    records a defaulted (maintainer-vetoable) decision only as a
    `Decision defaulted: X — veto before merge` issue comment, invisible to the gate, so the
    default rides into an autopilot
    merge only once a maintainer has **ratified** it: a human `OWNER`/`MEMBER` comment posted
    after the marker carrying an explicit ratification signal, a closed, whole-word token set
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

  Any criterion failing falls back to the base behavior: the PR is reported on the human
  merge-ready list. The tier never routes around the gate and never rubber-stamps: the bot
  review is a real review pass, and the ruleset stays meaningful. Absent the enable flag this
  tier does not exist and the first bullet governs unchanged.
- Enable auto-merge outside Merge-lane auto-merge above. Armed earlier, a review round landing
  after `--auto` can merge ahead of AI review or leave the PR unmergeable while the lane has
  already moved on. Otherwise merge synchronously against a `ready: true` merge-gate run, or
  report the PR as merge-ready and leave it in the queue.
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
(`<plugin-root>/reference/review-discipline.md`), and surface it in the report. Never
auto-fix human feedback, and never resolve a human-authored thread, outside autopilot's
addressed-thread widening. `CHANGES_REQUESTED`, explicit blocking language, and unresolved inline
human threads are stop-and-ask conditions until GitHub state resolves them (`feedback.md`).

## Comment Policy

Beyond the classification replies and follow-ups the shared review discipline requires, prefer
commits and concise reports over additional GitHub comments. The one-shot review-trigger comment
(`review-trigger.md`, when configured) is the only other proactive comment. Never impersonate
another tool or identity in a comment.
