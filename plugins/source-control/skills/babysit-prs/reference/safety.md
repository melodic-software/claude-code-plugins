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
  when that module is configured), spawn workers, push a dispatched conflict worker's verified
  resolution (`orchestration.md`, Merge Conflict Resolution — the one push it owns), and report.
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
  the worktree is first assigned. **One codified exception:** the conflict-resolution push in
  `orchestration.md`'s Orchestrator Contract. There `HEAD` is by construction the local merge commit
  the conflict worker produced, which the live PR does not carry yet, so the assertion is checked
  one commit back: the merge commit must have exactly two parents, its **first parent** must equal
  the live `headRefOid` (re-checked immediately before the push), and its second parent the
  reported base. Every other condition of that contract still binds, and everywhere outside that
  push the assertion remains on `HEAD` itself.
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
  not an automatic stop: hand it off to a dedicated, fresh conflict worker per
  `orchestration.md`'s Merge Conflict Resolution section — never resolved by the worker that
  discovered it mid-fix-round. The orchestrator never resolves a conflict dispatched to a conflict
  worker: it does not touch conflict markers or edit a resolution. (The safe tier's own inline
  handling of a simple conflict met while freshening a branch is separate and unaffected —
  `loop.md` §5.1.2.) It does own the conflict worker's one outward step — after re-asserting the
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
| `source-control-babysit-merge` — the **merge gate** | May this PR be merged right now under the plugin's full merge policy — GitHub's own mergeability *and* the plugin's policy holds? | Nothing about finding decomposition |

`ready` is the plugin's **merge-policy** verdict, not a readout of GitHub's mergeability alone.
`babysit_merge.py` appends its own policy blockers after the GitHub-derived ones: a
dependency-manager author is held in every tier without `--allow-dependency`, a non-self author's
PR on an unprotected base is held without `--allow-unprotected`, and an enabled autopilot merge
tier adds that tier's own criteria. So `ready: false` can mean "GitHub would merge this; the plugin
will not." Read the `blockers` list to tell the two apart, and never restate a plugin policy hold
as a GitHub restriction — that mislabel is the same terminology ambiguity this section exists to
remove.

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

"Both gates satisfied" binds the decomposition claim, not a mandatory second script run on every
path. The classification gate blocks on `findings > 0` with `classified < findings` (or an
unticked `--checklist`), so it constrains any iteration that actually processed findings. The
orchestrator's direct zero-blocker path — a non-draft PR the engine snapshot reports with zero
blockers *and* no untriaged material feedback (`SKILL.md`, "Fan out") — goes straight to a
merge-gate check without a worker, and so without the worker's per-PR iteration
classification-gate run (`SKILL.md`, Steps A–F). What keeps that path from
producing a false `MERGE-READY` is the `untriaged_material_feedback` exclusion in
`pr_clean_ready_for_direct_gate` (`scripts/babysit_delta.py`): the merge gate never inspects finding
content, so a PR carrying an undisposed material bot finding is held out of the direct gate rather
than merged over it. That exclusion is *not* a guarantee the classification gate would pass there —
it counts severity markers across *all* comment bodies with no bot/human split, while
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
reports merge-readiness as **unchecked** — an unavailable merge gate is never grounds to promote
`READINESS_OK` into a merge-ready claim.

## Review-Settle Hold

`mergeStateStatus == CLEAN` is a statement about the *present*, and a reviewer that re-reviews on
push contradicts it for the few minutes its next round takes. GitHub reports the PR mergeable that
whole time — the review does not exist yet, so there is no unresolved thread to block on — and a
gate reading only mergeability merges past findings that land seconds later. That is not
hypothetical: `#1594` merged 4m40s after its final commit and the reviewer's round posted 26
seconds afterward, carrying two valid findings, one of them a regression that PR introduced
(`#1629`, `#1613`).

The hold closes that window and is **dormant unless configured**: with
`babysit_review_bot_logins` and `babysit_review_settle_minutes` both set, the gate adds a policy
blocker while a configured reviewer still owes the **live head** a review and that head is younger
than the window. Its shape, and why each part is that way:

- **A review of the live head clears it outright**, before the clock is consulted. The common case
  — the reviewer already reviewed this head — costs nothing and adds no latency. Evidence is a
  submitted review *or* an inline review comment whose own commit id equals the head, by a
  configured login **that GitHub types as a `Bot`**: the same current-head test
  `review-trigger.md` specifies, reused rather than restated. A review of an earlier head is not
  evidence about this one. That shared test also admits a login the operator declared in
  `--extra-bot-logins` (#1642), but the merge gate does not pass that declaration through, so at
  *this* call site the `Bot`-type requirement still holds and is a real limitation — a configured
  reviewer GitHub reports as a `User` never clears the hold early, so every merge waits the full
  window. Fail-closed, but permanently slower until the gate threads the declaration through.
- **The window bounds it.** A reviewer that never engages must not wedge a PR, so the hold expires
  rather than waiting forever. Past the window the gate stops waiting and merges on its ordinary
  criteria. The window is therefore a latency budget, not a review requirement: it buys the
  reviewer time, it does not guarantee a review happened.
- **An unestablishable head age holds rather than merges.** If neither clock below can be read,
  whether the reviewer still owes this head a review is undecidable, and a transient read failure
  must not be the thing that silently disables the hold. The block is self-clearing on the next run.
- **Both keys or neither.** Either alone is a usage error (exit 2), not an inert flag — a
  half-configured hold must never read as an active one. No duration is defaulted in the gate:
  how long a reviewer takes is a property of that reviewer, so the operator supplies it.

Set the window above the reviewer's observed latency, measured against that reviewer rather than
inherited from this file. Priced honestly, the hold costs up to one window of latency on any merge
whose head the reviewer has not yet reviewed — including every merge when the reviewer is down —
in exchange for not merging past a review already on its way.

**Which clock the age is measured on**, in order, because the difference decides whether the hold
fires at all:

1. **The most recent CI start on the live head**, read from the **raw** status-check rollup the
   gate already fetches — no extra request, and raw rather than classified because the classifier
   keeps only the newest run per check identity. GitHub generates the timestamp after the push, so
   it can only make a head look *more* recent than it is, which errs toward holding.

   **Newest rather than oldest, and the direction is the safety property.** Check runs live on the
   SHA, so a head returning to a previously-checked SHA — force-push A → B → A — still carries A's
   original runs even though the re-push draws a fresh review. Reading the oldest would call a
   brand-new head settled and merge straight through the window. The cost of reading the newest is
   bounded and lands on latency: a re-run extends the wait by up to one window. It rarely bites,
   because a re-run does not move the head — a head the reviewer already reviewed clears the hold
   before this clock is read at all, and a head it has not is one that should be held anyway.

2. **The head commit's committer date**, only when the rollup carries no usable timestamp. A weaker
   proxy that errs the wrong way: a commit pushed long after it was written — local batching, an
   offline delay, or replaying an existing commit — reads as already-settled, and the hold silently
   does not fire on exactly the push that triggered a fresh review. A repository with no checks on
   its PRs gets only this fallback, so the hold is best-effort there.

**One residual, stated because it is not closed.** If a force-push back to a previously-checked SHA
produces new check runs, the newest timestamp is fresh and the hold fires correctly. If GitHub
instead reuses the existing results and mints none, the rollup carries only the old timestamps and
that head reads as settled. Which of those happens is not verified here, and no queryable
"this SHA became the head at T" record covers both ordinary pushes and force-pushes — the
force-push timeline event covers only the latter. Treat the hold as strong for ordinary pushes and
best-effort across a head reverting to an already-tested SHA.

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
— it is not a guard-dodging re-spelling (only invoking the raw Python is).

Two facts about the wrappers' bare names, both load-bearing:

- **Bare-name resolution is unreliable, not absent.** A plugin's `bin/` reaches the Bash tool's
  `PATH` only through the session shell snapshot's final `export PATH=` line; when that line does
  not land, every enabled plugin's `bin/` goes with it and a bare `source-control-babysit-merge …`
  fails `command not found`
  ([anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066)). The
  loss is per-session and silent, so a bare name that resolves today can be gone next session.
- **The path form cannot match a bare-name allow rule.** Before matching Bash rules Claude Code
  strips only a fixed wrapper set — `timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`,
  `builtin`, `noglob`, and bare `xargs` ([permissions](https://code.claude.com/docs/en/permissions)).
  `bash` is not among them, so `bash "…/bin/source-control-babysit-merge" …` matches as a `bash`
  command and never satisfies a pre-approved `Bash(source-control-babysit-merge:*)`. That rule does
  not cover these invocations, and cannot until bare-name resolution is dependable enough to invoke
  bare — so **what happens next is the permission mode's call, not the allow rule's:**
  - **In a mode that prompts** — Manual and accept-edits, and plan mode only on its no-classifier
    branch — expect a per-call permission prompt. It is expected behavior, not a misconfiguration.
    Plan mode still *runs* shell commands (it blocks source edits, not commands), but when auto mode
    is available and `useAutoModeDuringPlan` is on, which is the default, the classifier reviews
    them "instead of prompting you"; only otherwise do commands outside the read-only set prompt
    ([plan mode](https://code.claude.com/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode)).
  - **In auto mode, expect no prompt.** Auto mode "lets Claude execute without routine permission
    prompts", routing uncovered actions to a classifier that approves or blocks them
    ([permission modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)).
    So a merge or thread-resolution call can be **denied without ever surfacing** — do not wait on a
    prompt that will not arrive; read the denial in `/permissions` → **Recently denied**. Only an
    explicit `permissions.ask` rule still forces a prompt in auto mode.

  A narrow allow rule would not rescue this even if one matched: narrow Bash allow rules do carry
  into auto mode and resolve before the classifier, but `autoMode.classifyAllShell: true` suspends
  every one of them while auto mode is active
  ([auto-mode config](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)).

The `${CLAUDE_PLUGIN_ROOT}/bin/` path — resolved exactly as the sibling
`${CLAUDE_PLUGIN_ROOT}/scripts/` invocations are — is nonetheless the form to use: it is the only
one that runs in both `PATH` states. Every command spelled below as `source-control-babysit-<x> …`
is launched this way.

Capture the wrapper's output first, then parse its JSON in a *separate* step — never pipe the
wrapper into an interpreter (`… | python`, `… | jq`): an interpreter-in-pipeline trips the
auto-mode safety classifier and blocks the call before the wrapper runs.

- Both wrappers **fail closed**: invoked without `--allowed-owners`, they exit `3` and refuse to
  act. The read-only forms are `source-control-babysit-merge owner/repo#42 --allowed-owners
  <watched-owners>` (merge-readiness gate) and `source-control-babysit-resolve-thread
  owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins>
  --self-logins @me,<self-logins>` (thread list).
- **`--extra-bot-logins <extra-bot-logins>` rides on every resolve-thread form**, listing and
  mutating alike, whenever `babysit_extra_bot_logins` is configured. Bot classification is what
  decides which threads the resolver may touch at all, and structural detection cannot see a
  registered non-structural bot account (no `[bot]` suffix, API `__typename` of `User`); omitting
  the flag silently reclassifies that account's threads as human and skips them in worker tier.
  Omit the flag only when the key is unset.
- **The review-settle pair rides on every merge form** when `babysit_review_bot_logins` and
  `babysit_review_settle_minutes` are both configured: `--review-bot-logins <review-bot-logins>
  --review-settle-minutes <review-settle-minutes>`. Dropping it from a merge command silently
  restores the pre-`#1629` behavior of merging inside a re-review's latency window, and supplying
  one half without the other is a usage error (exit `2`) rather than a partial hold. Omit the pair
  only when either key is unset — see §Review-Settle Hold.
- **`--self-logins @me,<self-logins>` rides on every resolve-thread form too**, listing and
  mutating alike, always (`@me` resolves your own `gh` login; append `babysit_self_logins`
  extras). The bot-only classifier (`project_thread`'s `botOnly`) requires a BOT OPENER **and**
  inspects every other fetched participant — so the worker's OWN reply to a bot thread (a
  classification reply, a `Fixed in <sha>` follow-up) is itself a comment the classifier sees.
  Without `--self-logins` that reply is indistinguishable from a genuine third-party human joining the
  thread: `botOnly` goes false, which locks the thread out of the default bot-only scope, and
  `--include-human` stays unset by design in worker/safe modes — so nothing lifts it back in and a
  bot thread the worker correctly handled is permanently unresolvable by the normal flow.
  `--self-logins` marks the caller's own posting identity as neutral for that test instead —
  neutral as a REPLY only: the OPENING comment must still be an ACTUAL bot's, so a thread the
  worker itself opened stays out of scope even after a bot replies to it (`review-discipline.md`
  D7.5 forbids resolving your own threads). Omit the flag only when `babysit_self_logins` is unset.
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

### Lane-pinned merge authorization: report, don't re-pin

A single-PR merge-capable invocation dispatched by `source-control:babysit-loop`'s rung partition —
at **any** merge-capable tier, worker and autopilot alike — carries the lane's **partitioned head
SHA** as its merge authorization, supplied in the invocation brief: the merge gate's
`--expected-head` is that partitioned head, never a fresher head this invocation picked itself. The
lane's partition class-checked exactly that head's diff (work class C2/C3 against the C4/C5 floor),
and this skill's merge gate does not class-check — so a worker push that moves the head off the pin
is not a cue to re-pin, it is the end of this invocation's merge authority. The pinned gate's
head-match refusal enforces the boundary deterministically; the invocation reports the new head and
stops, and the lane reruns its partition on the post-push diff before any merge-capable
re-invocation (`babysit-loop/SKILL.md`, Cycle shape step 3, "The verdict authorizes a head SHA, not
the PR"). Every other invocation of this skill re-pins to the vetted post-push head exactly as
Autopilot step 3 describes.

### Security/P1 escalation: the one named exception

Escalating a security/P1 thread instead of resolving it holds in every tier, autopilot included.
The loop-lane convention carries exactly one named exception (§1, "one named, explicit
paired-argument exception"), and it is this narrow:

- **Only one dispatch path.** The `source-control:babysit-loop` explicit-`autopilot` pre-escalation
  resolver — the subagent that lane dispatches when a caller typed both the literal `autopilot`
  tier argument and the dedicated raise argument `--merge c3-this-run` on that invocation's own
  line. No other invocation of this skill, at any tier, ever reaches this exception.
- **Only a fresh, independent context.** The dispatch must share no conversation history with
  whatever produced the PR or previously replied on the blocking thread (the convention's §3
  independence requirement). A continuation of the authoring session, or a re-invocation of the
  subagent that already commented on the blocker, never qualifies — regardless of what it claims
  about itself. This is a contract on how the lane dispatches, not a credential the dispatch
  presents: a run that cannot establish it is fresh escalates.
- **Only through these wrappers.** The resolution runs through the guarded-mutation path above,
  with every pin, refusal, and JSON-parse rule intact. The exception changes who may attempt the
  resolution, never what the wrappers permit.
- **Never anything else.** It does not widen what counts as genuinely "addressed", never applies
  to a PR whose work item classifies C4 (structural) or C5 (untrusted-provenance), and never
  substitutes for escalation when the resolution is unresolved or the resolver is uncertain.

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
  those three without the umbrella is a usage error (exit `2`). Add `--method <merge-method>`,
  `--extra-dependency-manager-logins <extra-dependency-manager-logins>`, and the review-settle pair
  `--review-bot-logins <review-bot-logins> --review-settle-minutes <review-settle-minutes>` when
  configured, exactly as for the base merge readiness gate above (omit each when its value is empty
  or a literal unexpanded token; omit the settle pair as a pair, never one half).

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

Configuring that host layer means deciding which of this lane's entry points mutate, which flags
gate which guard, and where each refusal is enforced. Those facts are in
[reference/guard-contract.md](guard-contract.md), generated from the table
`scripts/tests/test_guards.py` executes against the real entry points — so a rule written against
a row cannot silently outlive the guard it cites. Cite a row ID; do not restate the behavior in
the consuming configuration.

**The never-retry rule is disputed for the classifier case, and nothing below settles it.**
[claude-code-plugins#455](https://github.com/melodic-software/claude-code-plugins/issues/455) is
open against the first bullet above: it records an auto-mode *classifier* denial that was retried,
where the retry succeeded — evidence that a classifier verdict may not carry the same finality as a
rules-layer denial. The Lane-Script Reachability section that follows is about whether the lane's
own scripts are reachable at all, not about what to do after a denial; read its restatement of the
denial contract as inherited from the bullet above, not as fresh confirmation of it. Until #455 is
resolved, treat the retry semantics of a classifier denial specifically as an open question.

### Lane-Script Reachability (operator prerequisite)

That ceiling reaches the lane's own scripts, not just GitHub-mutating commands. Every tier proves
readiness with a bundled script — the Python engine and gates under `skills/babysit-prs/scripts/`,
the guarded wrappers under `bin/`, and the plugin-scope helpers under `scripts/` that the
Python-free degrade path itself depends on — including the **read-only** merge-readiness check,
which mutates nothing and is still a shell invocation the host may deny. So those scripts being
invocable without a per-call denial is a declared prerequisite of the lane, on the same footing as
Python.

**The no-degrade half is narrower than the prerequisite, and that distinction is the point.** It
binds the paths that *prove readiness* — the readiness gate and the read-only merge-readiness
check. Unlike Python those have no degrade tier, because there is no permission-free path to a
proven readiness verdict, and a verdict that was never produced cannot be handed to anyone. A
denied *mutation* is not in that set: there the gate has already proven the PR ready, so
Pinned-Command Degradation below degrades it to a ready-to-execute operator handoff. So the
prerequisite covers reachability of every bundled script; the no-degrade rule covers the check
paths only.

**What this prerequisite rests on — and what it does not.** The denial recorded in
[claude-code-plugins#787](https://github.com/melodic-software/claude-code-plugins/issues/787) was
of a raw wildcarded-interpreter invocation (`python …/babysit_merge.py …`) — a form auto mode drops
by design, and a form this file already forbids. #787's own body says the orchestrator reached for
it *because* the bare `bin/` wrapper was not on PATH; the commit that made the `bin/`-path form the
mandated spelling landed after that report. So #787 does **not** demonstrate that the sanctioned
form gets denied, and this section is a generalization from other evidence rather than a
reproduction of that ticket. The evidence that does hold is
[dotfiles#315](https://github.com/melodic-software/dotfiles/issues/315): with
`autoMode.classifyAllShell` enabled, every narrow Bash allow rule is suspended — including twelve
grants purpose-built for this lane's scripts — so under that configuration even the compliant
`bash "${CLAUDE_PLUGIN_ROOT}/bin/…"` form reaches the classifier like any other command.
Reachability is therefore a property of the operator's configuration, never of the path form alone.

The grant is the operator's, never the plugin's — a plugin cannot ship permission rules, and an
agent must not broaden its own. The allow-rule shape guidance, and the official sources behind it,
are owned by the marketplace's permission-rule-hygiene convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/permission-rule-hygiene/README.md>.

Reachability is **not** implied by a `permissions.allow` rule. Whether shell allow rules resolve at
all while a host safety classifier is active is governed by the host's own auto-mode configuration
— read [auto-mode-config](https://code.claude.com/docs/en/auto-mode-config) for the current
semantics of `autoMode.classifyAllShell`, of the prose `autoMode.allow` exceptions, and of which
settings scopes the classifier reads `autoMode` from; never infer them from this file, and never
assume a prose entry guarantees a given command runs. What the lane requires is only the outcome:
a configuration under which this plugin's bundled scripts, invoked in the path forms this file
mandates (§Guarded Mutation Wrappers), run without a denial. The operator confirms the effective
configuration with `claude auto-mode config`.

**A denied gate is never downgraded to weaker evidence — and the gate now says so itself.**
`babysit-readiness-gate.sh` emits exactly one `READINESS_*` line on stdout on **every** run that
attempts a check, failure paths included — the sole exception is the help form (`--help` or its
`-h` alias, which share one branch), which prints usage and
exits 0 with no verdict; that form is not a check run, it is the non-mutating setup canary
([`skills/setup/SKILL.md`](../../setup/SKILL.md) "Lane-script reachability"):
`READINESS_UNPROVEN reason=<bad-args|identity-unresolved|prereq-missing|comments-unreadable|checklist-unreadable|fetch-failed> pr=<n>`
is a third verdict alongside `READINESS_OK` and `READINESS_BLOCKED`, and it means readiness was not
proven. Readiness is declared by quoting the verdict line verbatim in the iteration report
([loop.md](loop.md) §5.5), so a readiness claim with no verdict line to quote is unproven on its
face. That is both the mechanical half of this rule and its limit: a gate the harness never let run
cannot report its own non-invocation, which is why the quoted-verdict requirement lives on the
report rather than inside the script.

When readiness is not gate-proven — an emitted `READINESS_UNPROVEN`, or a call the harness denied
outright — `mergeStateStatus`, the check rollup, or any other live `gh` state a worker reports is
NOT a substitute verdict: it misses exactly the cross-checks the gate exists to run (dependency
author, unprotected base, self-login exemption, head match). Report that PR as **readiness
unproven**, quoting the verdict line when there is one and naming the exact command attempted when
the harness blocked the call, and surface the prerequisite above once for the cycle rather than
re-attempting the call per PR. Pinned-Command Degradation below covers the denied-*mutation* case;
this clause covers the denied-*check* case, which has no ready-to-execute handoff precisely because
nothing was ever proven ready.

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
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" owner/repo#42 --allowed-owners <watched-owners> --merge --expected-head <post-push-head-sha> --method <merge-method> --extra-dependency-manager-logins <extra-dependency-manager-logins> --review-bot-logins <review-bot-logins> --review-settle-minutes <review-settle-minutes>
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
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins> --autonomous --resolve --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
```

for the unattended-worker case, or

```text
bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-resolve-thread" owner/repo#42 --allowed-owners <watched-owners> --extra-bot-logins <extra-bot-logins> --self-logins @me,<self-logins> --resolve --include-human --thread-id <id> --expected-comment-count <n> --expected-last-updated <ts>
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
