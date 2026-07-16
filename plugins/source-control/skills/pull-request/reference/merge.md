# Phase 4: Merge (squash + cleanup)

## 4.1 Pre-merge checks (readiness re-verification)

Resolve `<pr_number>` via `gh pr view --json number -q '.number'`. Pass it explicitly to every `gh` call in this phase.

**Re-run full [readiness checklist](readiness.md) before merge execution.** This is the second run (first was in monitor 3.4). Catches late-arriving comments, status changes between monitor completion and merge, and race condition where a comment-only actor posts after readiness was declared.

```bash
# 1. Re-check all check runs for any state changes
gh pr checks <pr_number> --json name,state,bucket

# 2. Re-check for new comments since monitoring completed (all 3 sources, paginated)
gh api --paginate repos/{owner}/{repo}/pulls/<pr_number>/reviews | jq -r '.[].user.login'
gh api --paginate repos/{owner}/{repo}/pulls/<pr_number>/comments | jq -r '.[].user.login'
gh api --paginate repos/{owner}/{repo}/issues/<pr_number>/comments | jq -r '.[].user.login'
```

**If any readiness gate fails on re-verification:**

- New failing check → return to monitor (Phase 3)
- New unprocessed comment → process per 3.3, then re-verify
- New security finding → evaluate per 3.1.5, then re-verify

**Only after all 6 readiness gates pass on this re-verification:**

1. Present merge summary including:
   - Check run status (all classified)
   - Security scan disposition (all findings classified)
   - Comment coverage (all reviewers processed)
   - Any deferred items (tracked work items)
2. **Comprehension quiz (default-on, self-enforced)** — when the PR carries substantial work the user didn't author line-by-line (multi-file feature/refactor, or a long agent session outran the user's reading), generate a self-contained HTML change report + quiz before asking for merge approval: the report explains the change with context and intuition (what was done, why, which existing code paths it leans on); the quiz at the bottom tests exactly that. The user merges after passing — self-enforced, no tooling gate; "skip quiz" skips it explicitly. Exemption is calibrated by size and blast radius, NOT by file type: exempt only diffs the user can genuinely review at a glance (single-file, mechanical, or a handful of small localized edits). A large multi-file instruction-only change (skills, rules, agent instructions from a long session) gets the quiz even though it is docs-only — instruction surfaces steer future agent behavior, so unread changes there carry real blast radius
3. Wait for user approval — merge is an irreversible action

## 4.2 Squash merge

Default merge mode is squash — one squashed commit per PR onto the default branch. Follow the consuming project's convention when it differs (merge commit / rebase-merge).

```bash
gh pr merge <pr_number> --squash --delete-branch
```

**Always use the explicit `<pr_number>` resolved at phase entry.** The PR title — shaped to satisfy the resolved subject/title convention, see pull-request SKILL.md's "PR title format" ladder (Conventional Commits by default) — becomes the squash commit message.

## 4.3 Worktree transition and next-task setup

Detect if currently in a worktree (`git worktree list`).

**If in a worktree (primary pattern — worktree reuse):**

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

Worktree reuse (new branch from latest default branch in the same directory) is faster than remove+recreate and preserves gitignored files; the alternative is `ExitWorktree` + a fresh `EnterWorktree` for a clean slate.

**If on a regular branch (not in worktree):**

1. **Check for uncommitted changes BEFORE checkout** — `git status --porcelain`. If uncommitted changes exist, they will be lost on the default-branch checkout (conflicting changes fail, non-conflicting changes silently carry over — neither desirable). Stash first: `git stash push -u -m "pre-merge-cleanup: <branch-name>"` (`-u` includes untracked files — without it, new files are silently skipped). Stashes survive branch deletion (stored in `.git/refs/stash`, not tied to branches)
2. `git checkout "$DEFAULT_BRANCH"` (resolve via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`)
3. `git pull --ff-only`
4. `git branch -D <merged-branch>`
5. If a stash was created in step 1, inform user: "Stashed N uncommitted changes. Run `git stash list` to see them, `git stash pop` to restore on a new branch."

## 4.4 Run a session retrospective (optional)

If your environment provides a retrospective skill (e.g. a `/retro` command), invoke it **after the worktree transition (worktree reuse) or after merge (non-worktree)**. With worktree reuse, `CLAUDE_PROJECT_DIR` stays valid because the worktree directory persists — skills remain fully discoverable. If no such capability exists, skip this step.

If the user declines or says "skip", proceed to step 4.5. In `full` mode, run automatically without pausing.

**Exception:** if using `ExitWorktree` instead of worktree reuse (rare), run the retrospective BEFORE merge in Phase 4.1 — worktree removal orphans `CLAUDE_PROJECT_DIR` and breaks skill discovery.

## 4.5 Verify clean state and offer next action

```bash
git status              # should be clean
git worktree list       # should show only main + other active worktrees
git branch              # merged branch should be gone, new branch active
```

**Post-merge CI health check** — verify CI on main is green after merge commit lands:

```bash
gh run list --branch "$DEFAULT_BRANCH" --limit 1 --json conclusion,displayTitle \
  --jq '.[0] | "\(.conclusion): \(.displayTitle)"'
```

If latest run shows `failure`, flag it immediately — the merge may have introduced a regression on main. If run is still `in_progress`, note it and suggest checking back.

Report: merge complete, transition successful, state verified.

**Then offer next-task transition:**

> "PR merged and worktree ready for next task. What's next?"
>
> 1. **Continue in this session** — `/clear` for fresh context, then start the new task on the branch we just created
> 2. **End session** — close and start fresh next time
