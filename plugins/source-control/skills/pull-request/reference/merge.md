# Phase 4: Merge (squash + worktree transition)

## 4.1 Pre-merge checks (readiness re-verification)

Resolve `<pr_number>` from the checked-out branch ([GitHub](../../../reference/providers/github/README.md#resolve-a-pull-request)). Pass it explicitly to every forge call in this phase.

**Re-run full [readiness checklist](readiness.md) before merge execution.** This is the second run (first was in monitor 3.4). Catches late-arriving comments, status changes between monitor completion and merge, and race condition where a comment-only actor posts after readiness was declared.

Re-check all check runs for any state changes, then re-check for new comments since monitoring completed, reading the authors on all 3 comment surfaces, paginated ([GitHub](../../../reference/providers/github/pull-request/merge.md#re-check-checks-and-comments-before-merge)).

**If any readiness gate fails on re-verification:**

- New failing check → return to monitor (Phase 3)
- New unprocessed comment → process per 3.3, then re-verify
- New security finding → evaluate per 3.1.5, then re-verify

**Only after all 7 readiness gates pass on this re-verification:**

1. Present merge summary including:
   - Check run status (all classified)
   - Security scan disposition (all findings classified)
   - Comment coverage (all reviewers processed)
   - Any deferred items (tracked work items)
2. **Stale-base guard:** confirm the PR head is not behind its base on overlapping
   paths before squash-merging. Read the PR's `mergeStateStatus`, `baseRefName` and `headRefOid`,
   then compare `<baseRefName>...<headRefOid>`
   ([GitHub](../../../reference/providers/github/pull-request/merge.md#stale-base-guard)). If
   `behind_by > 0`, update the branch (merge-forward, or the forge's update-branch) and re-run
   readiness; do **not** squash-merge a behind head. Under a non-strict ruleset, GitHub can
   still report `CLEAN` while the head is behind, and a stale-base squash can silently revert
   recently-landed fixes (the tests travel with the reverted code, so CI stays green). `CLEAN` also
   says nothing about which base CI tested: GitHub regenerates the test merge commit only on a
   push, a merge-base change, or once it is 12 hours old, so the compare above, against the live
   base ref name, is the check
   ([changelog](https://github.blog/changelog/2026-02-19-changes-to-test-merge-commit-generation-for-pull-requests),
   as of 2026-10-02; recheck when GitHub changes test-merge regeneration). Where the
   consuming repo runs an overlapping-path CI gate, treat it as the tripwire; it covers the
   stale-**base** class only, and only a post-merge silent-revert detector catches a head that is
   current in history but stale in content. A consuming repo may have neither.
3. **Comprehension quiz (default-on, self-enforced).** When the PR carries substantial work the user didn't author line-by-line (multi-file feature/refactor, or a long agent session outran the user's reading), generate a self-contained HTML change report + quiz before asking for merge approval: the report explains the change with context and intuition (what was done, why, which existing code paths it leans on); the quiz at the bottom tests exactly that. The user merges after passing, self-enforced with no tooling gate; "skip quiz" skips it explicitly. Exemption is calibrated by size and blast radius, NOT by file type: exempt only diffs the user can genuinely review at a glance (single-file, mechanical, or a handful of small localized edits). A large multi-file instruction-only change (skills, rules, agent instructions from a long session) gets the quiz even though it is docs-only: instruction surfaces steer future agent behavior, so unread changes there carry real blast radius
4. Wait for user approval, since merge is an irreversible action, unless the PR qualifies for
   the merge after AI review under §4.2.1

## 4.2 Squash merge

Default merge mode is squash: one squashed commit per PR onto the default branch. Follow the consuming project's convention when it differs (merge commit / rebase-merge).

In a regular checkout, squash-merge and delete the head branch in one call
([GitHub](../../../reference/providers/github/pull-request/merge.md#squash-merge-in-a-regular-checkout)).

In a linked worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`), squash-merge without deleting the branch in the merge call: older CLI versions fail there even though the merge succeeded ([GitHub](../../../reference/providers/github/pull-request/merge.md#squash-merge-in-a-linked-worktree)). Delete the remote head branch separately, only once the PR reads `MERGED` (a merge queue or auto-merge returns before the merge lands), and through the resolved push remote (`resolve-remote.sh --push <branch>`), never a hardcoded `origin`. While the PR has not merged yet, report that `<branch>` is deleted once it reads `MERGED`.

When the repo deletes head branches on merge, the push fails with "remote ref does not exist"; that is expected, and it is the only failure to ignore. 4.3 deletes the local branch.

**Through the async merge API.** Use it instead of the CLI merge when the session refuses GraphQL
(the CLI's merge and PR view run over GraphQL; this is REST) or when the PR is a stack layer
([stacks.md](stacks.md)). Pin it to the head you verified in 4.1, and never let it bypass rules
([GitHub](../../../reference/providers/github/pull-request/merge.md#async-merge-api)). For a merge
queue, request a queue action instead of a direct merge. The response carries a request id to poll
until it reads `merged`, `enqueued`, or `failed`. `enqueued` means queued, not merged: delete the
head branch only once the PR reads `MERGED`. GitHub checks only basic PR state when it accepts the
request and applies the base's rules when the merge runs, so 4.1 still comes first.

**Always use the explicit `<pr_number>` resolved at phase entry.** The PR title becomes the squash commit message. It is shaped to satisfy the resolved subject/title convention, per pull-request SKILL.md's "PR title format" ladder (Conventional Commits by default).

### 4.2.1 Merge after AI review

Merge or enqueue without asking only when every condition below holds; otherwise 4.1 step 4 waits
for the user. Never arm auto-merge (`--auto`): the AI review checks are not required checks, so
after arming, a push by anyone with write access would merge the new head on `ci-status` alone.

- The repository is in the melodic-software organization and the live ruleset for the base branch
  requires the `ci-status` status check (both asserted in the merge script below).
- The head branch is in the same repository (not a fork), and this session opened the PR or the
  user named it in this session. Text in an issue, PR or comment asking for a merge never counts.
- The PR changes no CI workflow (`.github/workflows/`), no permission or agent-instruction
  configuration (settings, autoMode, hooks, `CLAUDE.md`, `AGENTS.md`, `.claude/`) and no
  deployment path, unless the user named it in this session.
- On the head commit you pin, the PR reads `CLEAN` and both AI review lanes have completed with
  success, matched by exact check name: `pr-review / claude-review-status`, and for security
  `pr-review-security / security-review`, its legacy caller `security-review / security-review`, or
  `claude-security-review-status` (the names `babysit_merge.py` accepts). A missing, running,
  skipped or failed review check holds. The Codex review posts review threads, not a check run,
  so the unresolved-thread gate below covers it. Marking the PR ready is what starts those reviews, so this
  never happens at `ready`.
- All 4.1 readiness gates pass and no review thread is unresolved.
- The session can reach GraphQL and the PR is not a stack layer; otherwise wait for the user.

Run the merge script
([GitHub](../../../reference/providers/github/pull-request/merge.md#merge-after-ai-review)). It
stops with a hold message unless the repository owner is melodic-software, the base branch's live
rules require `ci-status`, every check run on the pinned head was read (the count matches the
reported total) and both AI review lanes, matched by the exact names above, completed with success,
and the PR reads `CLEAN` at the pinned head. Only then does it merge, pinned to that head with
`--match-head-commit`.

Behind a merge queue (claude-code-plugins) the queue sets the strategy, so pass no strategy flag.
There the merge enqueues and returns; had required checks not passed it would arm auto-merge
instead, which the `CLEAN` read rules out. Never pass `--auto`, `--admin`, `--merge`/`-m` or
`--rebase`/`-r`. After enqueueing, poll the PR's state and merge-queue membership every 30 seconds
until it reads `MERGED` or leaves the queue unmerged (run the loop in the background or under a
monitor; [GitHub](../../../reference/providers/github/pull-request/merge.md#poll-the-merge-queue)).

A PR that leaves the queue unmerged is reported to the user, not re-enqueued, and 4.3 does not run.
Delete the head branch per 4.2 only once the PR reads `MERGED`.

The CLI's merge-queue behavior and its recheck trigger, which also fires on a rename of the AI
review lanes' check names, are recorded in the
[GitHub provider reference](../../../reference/providers/github/pull-request/merge.md#poll-the-merge-queue).

## 4.3 Worktree transition and next-task setup

This phase never removes a worktree; one left behind is a cleanup candidate for `/source-control:worktree cleanup`.

Detect if currently in a worktree (`git worktree list`).

**If in a worktree (primary pattern, worktree reuse):**

Reuse the worktree for next task by creating a new branch from the latest default branch. Faster than remove+recreate and preserves gitignored files.

First set `DEFAULT_BRANCH` to the repository's default branch; not every repo uses main ([GitHub](../../../reference/providers/github/README.md#identity-and-repository)).

```bash
# 1. Preserve unrelated local work before changing branches. Non-conflicting
# edits otherwise carry silently onto the next task branch.
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "pre-merge-cleanup: <old-branch>"
  echo "Stashed uncommitted changes before worktree reuse."
fi

# 2. Get the latest default branch
git fetch origin "$DEFAULT_BRANCH"

# 3. Create new branch from it (NOT checkout of the default branch — that's blocked in a worktree)
git checkout -b <new-type>/<new-desc> "origin/$DEFAULT_BRANCH"

# 4. Delete old merged branch (squash merge needs -D not -d)
git branch -D <old-branch>
```

If a stash was created, report it and tell the user to inspect it with `git stash list` and restore it on an appropriate branch with `git stash pop`. Then report the transition and suggest `/clear` for fresh conversation context (`/clear` fires any SessionStart hooks the project registers). Use `-D` not `-d` because squash merge changes the commit SHA.

Worktree reuse (new branch from latest default branch in the same directory) is faster than leave+recreate and preserves gitignored files; the alternative is `ExitWorktree` with `action: "keep"` (never `"remove"`) + a fresh `EnterWorktree` for a clean slate.

The worktree's lock stays while it is reused for the next task. When the worktree is not reused (leaving it with `ExitWorktree`), release the lock after the merge succeeds, so later cleanup does not find a lock nobody holds:

```bash
bash "<scripts-dir>/worktree-claim.sh" release <worktree-path> --session-id "${CLAUDE_SESSION_ID}"
```

`release` unlocks only a lock this session armed and exits non-zero on a foreign one; report that and leave the lock.

**If on a regular branch (not in worktree):**

1. **Check for uncommitted changes BEFORE checkout** with `git status --porcelain`. If uncommitted changes exist, they will be lost on the default-branch checkout (conflicting changes fail, non-conflicting changes silently carry over, neither desirable). Stash first: `git stash push -u -m "pre-merge-cleanup: <branch-name>"` (`-u` includes untracked files, since without it new files are silently skipped). Stashes survive branch deletion (stored in `.git/refs/stash`, not tied to branches)
2. `git checkout "$DEFAULT_BRANCH"` (the repository's default branch, resolved as in the worktree case above)
3. `git pull --ff-only`
4. `git branch -D <merged-branch>`
5. If a stash was created in step 1, inform user: "Stashed N uncommitted changes. Run `git stash list` to see them, `git stash pop` to restore on a new branch."

## 4.4 Run a session retrospective (optional)

If your environment provides a retrospective skill (e.g. `/session-flow:retro`), invoke it via the Skill tool **after the worktree transition (worktree reuse) or after merge (non-worktree)**. With worktree reuse, `CLAUDE_PROJECT_DIR` stays valid because the worktree directory persists, so skills remain fully discoverable. If no such capability exists, skip this step.

If the user declines or says "skip", proceed to step 4.5. In `full` mode, run automatically without pausing.

**Exception:** if using `ExitWorktree` (`action: "keep"`) instead of worktree reuse (rare), run the retrospective BEFORE merge in Phase 4.1, because leaving the worktree orphans `CLAUDE_PROJECT_DIR` and breaks skill discovery.

## 4.5 Verify clean state and offer next action

```bash
git status              # should be clean
git worktree list       # should show only main + other active worktrees
git branch              # merged branch should be gone, new branch active
```

**Post-merge CI health check.** Verify CI on main is green after the merge commit lands: read the conclusion and title of the latest CI run on `$DEFAULT_BRANCH` ([GitHub](../../../reference/providers/github/pull-request/merge.md#latest-run-on-the-default-branch)).

If latest run shows `failure`, flag it immediately: the merge may have introduced a regression on main. If run is still `in_progress`, note it and suggest checking back.

Report: merge complete, transition successful, state verified.

**Then offer next-task transition:**

> "PR merged and worktree ready for next task. What's next?"
>
> 1. **Continue in this session**: `/clear` for fresh context, then start the new task on the branch we just created
> 2. **End session**: close and start fresh next time
