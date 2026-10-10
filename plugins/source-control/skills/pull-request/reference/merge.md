# Phase 4: Merge (squash + worktree transition)

## 4.1 Pre-merge checks (readiness re-verification)

Resolve `<pr_number>` via `gh pr view --json number -q '.number'`. Pass it explicitly to every `gh` call in this phase.

**Re-run full [readiness checklist](readiness.md) before merge execution.** This is the second run (first was in monitor 3.4). Catches late-arriving comments, status changes between monitor completion and merge, and race condition where a comment-only actor posts after readiness was declared.

```bash
# 1. Re-check all check runs for any state changes
gh pr checks <pr_number> --json name,state,bucket

# 2. Re-check for new comments since monitoring completed (all 3 sources, paginated)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/reviews?per_page=100" | jq -r '.[].user.login'
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/comments?per_page=100" | jq -r '.[].user.login'
gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100" | jq -r '.[].user.login'
```

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
   paths before squash-merging. `gh pr view <pr_number> --json mergeStateStatus,baseRefName,headRefOid`
   plus `gh api repos/{owner}/{repo}/compare/<baseRefName>...<headRefOid>`. If
   `behind_by > 0`, update the branch (merge-forward / `gh pr update-branch`) and re-run
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

In a regular checkout:

```bash
gh pr merge <pr_number> --squash --delete-branch
```

In a linked worktree (`git rev-parse --git-dir` differs from `git rev-parse --git-common-dir`), omit `--delete-branch`: on older gh it tries to check out the default branch locally, which fails while another worktree holds it, and exits 1 even though the merge succeeded. Delete the remote head branch separately, only once the PR reads `MERGED` (a merge queue or auto-merge returns before the merge lands), and through the resolved push remote, never a hardcoded `origin`. The head branch name comes from GitHub: substitute it for `'<branch>'` only when it matches `^[A-Za-z0-9._/-]+$`, does not start with `-` and contains no `..`, and keep the single quotes. Any other name reaches no command: report it as data and leave the remote branch for the user to delete.

```bash
gh pr merge <pr_number> --squash && {
  if [ "$(gh pr view <pr_number> --json state -q .state)" = MERGED ]; then
    REMOTE=$(bash "<skill-dir>/scripts/resolve-remote.sh" --push '<branch>') && git push "$REMOTE" --delete --end-of-options '<branch>'
  else
    echo 'PR not merged yet (merge queue or auto-merge); delete the head branch once it reads MERGED' >&2
  fi
}
```

When the repo deletes head branches on merge, the push fails with "remote ref does not exist"; that is expected, and it is the only failure to ignore. 4.3 deletes the local branch. Verified 2026-09-29 against [cli/cli#14007](https://github.com/cli/cli/pull/14007), which ships in gh 2.99.0 and makes `gh pr merge --delete-branch` skip the local delete when the head is checked out in the current linked worktree; earlier gh, such as 2.98.0, fails as described. Recheck when the minimum gh this plugin supports is 2.99.0 or later, at which point the split is no longer needed.

**Through the async merge API.** Use it instead of `gh pr merge` when the session refuses GraphQL
(`gh pr merge` and `gh pr view` run over GraphQL; this is REST) or when the PR is a stack layer ([stacks.md](stacks.md)). `gh` has no command for it yet, so
call it with `gh api`, pinned to the head you verified in 4.1 and never with `bypass_rules` true:

```bash
HEAD_SHA=$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" --jq .head.sha)
gh api -X PUT "repos/{owner}/{repo}/pulls/<pr_number>/merge-async" \
  -f sha="$HEAD_SHA" -f merge_action=direct_merge -f merge_method=squash -F bypass_rules=false
```

For a merge queue send `-f merge_action=merge_queue` and drop `merge_method`. The response carries a
request `uuid` (a 409 means one is already pending and returns its `uuid`); poll
`gh api "repos/{owner}/{repo}/pulls/<pr_number>/merge-async/<uuid>" --jq .status` until it reads
`merged`, `enqueued`, or `failed`. `enqueued` means queued, not merged: delete the head branch only
once the PR reads `MERGED`. GitHub checks only basic PR state when it accepts the request and
applies the base's rules when the merge runs, so 4.1 still comes first. Request fields and
statuses:
[merge a pull request asynchronously](https://docs.github.com/rest/pulls/pulls?apiVersion=2026-03-10#merge-a-pull-request-asynchronously),
as of 2026-10-02; recheck when a `gh` release adds a command for it or that page changes a field or
status.

**Always use the explicit `<pr_number>` resolved at phase entry.** The PR title becomes the squash commit message. It is shaped to satisfy the resolved subject/title convention, per pull-request SKILL.md's "PR title format" ladder (Conventional Commits by default).

### 4.2.1 Merge after AI review

Merge or enqueue without asking only when every condition below holds; otherwise 4.1 step 4 waits
for the user. Never arm auto-merge (`--auto`): the AI review checks are not required checks, so
after arming, a push by anyone with write access would merge the new head on `ci-status` alone.

- The repository is in the melodic-software organization and the live ruleset for the base branch
  requires the `ci-status` status check (both asserted in the script below).
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

```bash
[ "$(gh repo view --json owner --jq .owner.login)" = melodic-software ] \
  || { echo 'not a melodic-software repository: wait for the user' >&2; exit 1; }
HEAD_SHA=$(gh api "repos/{owner}/{repo}/pulls/<pr_number>" --jq .head.sha)
RULES=$(gh api --paginate --slurp "repos/{owner}/{repo}/rules/branches/<baseRefName>" | jq 'add')
jq -e 'any(.[]; .type == "required_status_checks"
  and any(.parameters.required_status_checks[]; .context == "ci-status"))' <<<"$RULES" >/dev/null \
  || { echo 'base ruleset does not require ci-status: wait for the user' >&2; exit 1; }
RUNS=$(gh api --paginate --slurp "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs?per_page=100")
jq -e '[.[].check_runs[]] as $r
  | def lane($names): [$r[] | select(.name | IN($names[]))]
      | length > 0 and all(.status == "completed" and .conclusion == "success");
  ($r | length) == .[0].total_count
  and lane(["pr-review / claude-review-status"])
  and lane(["pr-review-security / security-review", "security-review / security-review",
            "claude-security-review-status"])' <<<"$RUNS" >/dev/null \
  || { echo 'AI review not complete on the pinned head: hold' >&2; exit 1; }
[ "$(gh pr view <pr_number> --json headRefOid,mergeStateStatus \
  --jq "select(.headRefOid == \"$HEAD_SHA\") | .mergeStateStatus")" = CLEAN ] \
  || { echo 'PR not CLEAN at the pinned head: hold' >&2; exit 1; }
if jq -e 'any(.[]; .type == "merge_queue")' <<<"$RULES" >/dev/null; then
  gh pr merge <pr_number> --match-head-commit "$HEAD_SHA"
else
  gh pr merge <pr_number> --squash --match-head-commit "$HEAD_SHA"
fi
```

Behind a merge queue (claude-code-plugins) the queue sets the strategy, so pass no strategy flag.
There `gh pr merge` enqueues and returns; had required checks not passed it would arm auto-merge
instead, which the `CLEAN` read rules out. Never pass `--auto`, `--admin`, `--merge`/`-m` or
`--rebase`/`-r`. After enqueueing, poll until the PR merges or leaves the queue (run the loop in the
background or under a monitor):

```bash
while :; do
  S=$(gh api graphql -F owner='{owner}' -F name='{repo}' -F number=<pr_number> -f query='
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) { pullRequest(number: $number) { state isInMergeQueue } } }' \
    --jq '.data.repository.pullRequest | "\(.state) \(.isInMergeQueue)"')
  case "$S" in
    MERGED*) break ;;
    'OPEN true') sleep 30 ;;
    *) echo "PR left the merge queue unmerged ($S)" >&2; exit 1 ;;
  esac
done
```

A PR that leaves the queue unmerged is reported to the user, not re-enqueued, and 4.3 does not run.
Delete the head branch per 4.2 only once the PR reads `MERGED`.

- **Pointer**: how `gh pr merge` behaves on a merge-queue base and what `--match-head-commit` does:
  [gh pr merge](https://cli.github.com/manual/gh_pr_merge); `isInMergeQueue`:
  [GraphQL PullRequest object](https://docs.github.com/graphql/reference/objects#pullrequest).
- **As of**: 2026-10-09
- **Recheck trigger**: a gh release that changes `gh pr merge` flags or merge-queue handling, or a
  rename of the AI review lanes' check names.

## 4.3 Worktree transition and next-task setup

This phase never removes a worktree; one left behind is a cleanup candidate for `/source-control:worktree cleanup`.

Detect if currently in a worktree (`git worktree list`).

**If in a worktree (primary pattern, worktree reuse):**

Reuse the worktree for next task by creating a new branch from the latest default branch. Faster than remove+recreate and preserves gitignored files.

```bash
# 0. Resolve the repo's default branch (repo-agnostic — not every repo uses main)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

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
2. `git checkout "$DEFAULT_BRANCH"` (resolve via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`)
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

**Post-merge CI health check.** Verify CI on main is green after the merge commit lands:

```bash
gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json conclusion,displayTitle \
  --jq '.[0] | "\(.conclusion): \(.displayTitle)"'
```

If latest run shows `failure`, flag it immediately: the merge may have introduced a regression on main. If run is still `in_progress`, note it and suggest checking back.

Report: merge complete, transition successful, state verified.

**Then offer next-task transition:**

> "PR merged and worktree ready for next task. What's next?"
>
> 1. **Continue in this session**: `/clear` for fresh context, then start the new task on the branch we just created
> 2. **End session**: close and start fresh next time
