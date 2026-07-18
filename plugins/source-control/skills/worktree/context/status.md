# Worktree `status` — data collection, classification, presentation

Full detail for the `/worktree status` action. SKILL.md carries the headline; this file carries the porcelain-parse fields, the staleness math, the 6-status classification table, and the output schema.

## Data collection

1. **Worktree list**: Run `git worktree list --porcelain` and parse entries. Each entry is separated by blank line and contains:
   - `worktree <path>` — filesystem path
   - `HEAD <sha>` — current commit
   - `branch refs/heads/<name>` — checked-out branch (absent if detached)
   - `detached` — flag if HEAD is detached
   - `locked` — flag if worktree is locked (optional reason on same line)
   - `prunable` — flag if worktree can be pruned (optional reason on same line)

   Always `| tr -d '\r'` on Windows/Git Bash to strip carriage returns.

   `git worktree list --porcelain` emits correct absolute paths for every layout (standard clone, bare-clone hub, `.claude/worktrees/`), so `status` and `audit` need no layout-specific detection here — unlike Smart Default / `create` / `cleanup`, which resolve the hub root (`git rev-parse --git-common-dir` ending in `.bare`) for path construction.

2. **PR cross-reference**: Run `gh pr list --state all --json number,title,state,headRefName` once (not per-branch — batch is more efficient). Match each worktree's branch name against `headRefName`. Graceful degradation: if `gh` fails, skip PR info and note "GitHub API unavailable."

3. **Last commit date**: For each worktree branch, get date of last commit:

   ```bash
   git log -1 --format='%ci' <branch> 2>/dev/null
   ```

4. **Staleness**: Compare last commit date to today. Default threshold: **14 days**. The configured override is `${user_config.worktree_stale_days}` — use that value when it is a positive number, falling back to 14 when it is empty, invalid, or a literal unexpanded `${user_config.worktree_stale_days}` token.

## Status classification

| Status | Condition |
|--------|-----------|
| `active` | Recent commits, no issues |
| `stale` | Last commit > threshold days ago, no open PR |
| `in-review` | Has an open PR (regardless of commit age) |
| `merged` | PR was merged but worktree/branch not cleaned up |
| `prunable` | Git flagged as prunable (directory missing or corrupted) |
| `locked` | Explicitly locked by user |

## Presentation

```markdown
## Worktree Status

| # | Path | Branch | PR | Last Commit | Status |
|---|------|--------|----|-------------|--------|
| 1 | <worktree-root>/feat-auth | feat/add-auth | #21 OPEN | 2d ago | in-review |
| 2 | <worktree-root>/old-fix | worktree-old-fix | — | 23d ago | stale |

**Summary:** 2 worktrees (1 active, 1 stale)
```

If issues are found, suggest actions: `/worktree cleanup` for stale/merged, `git worktree unlock` for locked.
