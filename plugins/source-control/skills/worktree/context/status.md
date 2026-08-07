# Worktree `status` — data collection, classification, presentation

Full detail for the `/worktree status` action. SKILL.md carries the headline; this file carries the porcelain-parse fields, the staleness math, the stranded-work axis, the classification table, and the output schema.

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

5. **Stranded-work record**: age and PR state answer *is anyone still working here*; neither answers *would removing this destroy a commit*. Run the detection engine once per repository — it enumerates the worktrees itself and emits one TSV row per registered worktree:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/landed-work.sh" --repo-dir <repo-toplevel> --merged-refs-file <file>
   ```

   Write the merged `headRefName` values from step 2 to `<file>`, one per line — that is what separates a *superseded draft* (the base already holds a later revision of the same change) from genuinely stranded work. Omit the flag when `gh` was unavailable.

   Join rows to worktrees on the `path` column. The columns this file consumes: `unpushed`, `landed`, `base`, `peers`, `risk`, `reason`.

   Graceful degradation: on a non-zero exit, note "stranded-work detection unavailable — the Work column is unproven" and set every Work cell to `unknown`. Do not fall back to a hand-rolled probe: `--branches` reports other branches' commits rather than this worktree's, `@{upstream}..HEAD` returns nothing for a branch with no upstream, and a per-commit patch-id cannot see a multi-commit squash-merge. An unproven column is honest; a wrong one is not.

## Status classification

Two independent axes. **Work** answers whether removal would destroy a commit and is read straight from the engine's `risk` column; **Status** answers what should happen next. Classify Work first — it outranks age and PR state, because `stale` describes attention and `stranded` describes loss.

| Work | Engine `risk` | Meaning |
|------|---------------|---------|
| `safe` | `landed`, `ok`, `bare` | Nothing unpushed, or every unpushed commit's content is already on `base` |
| `stranded N` | `STRANDED` | N unpushed commits whose content is not on the base. Removal plus the branch deletion that follows it destroys them |
| `superseded` | `superseded` | Not landed, but its branch is the head ref of a MERGED PR — a draft the base moved past |
| `unknown` | `UNKNOWN` | No base resolved, or a probe failed. **Treat exactly as `stranded`** — the engine reports `?` rather than `no` precisely so an ambiguity is never read as safe |
| `notgit` | `notgit` | Path is not a work-tree root. Probing it with `git -C` reports the *containing* repository's clean state |

A `stranded` row whose `peers` column names another worktree is recoverable from that peer — present it as `stranded N (peer: <path>)`, a materially different disposition from stranded with no peer.

| Status | Condition |
|--------|-----------|
| `stranded` | Work is `stranded` or `unknown` — outranks every row below |
| `notgit` | Work is `notgit` |
| `superseded` | Work is `superseded` |
| `active` | Recent commits, no issues |
| `stale` | Last commit > threshold days ago, no open PR, **and** Work is `safe` |
| `in-review` | Has an open PR (regardless of commit age) |
| `merged` | PR was merged, **or** every unpushed commit landed on the base (`landed=yes`) — the branch's content is on the base either way |
| `prunable` | Git flagged as prunable (directory missing or corrupted) |
| `locked` | Explicitly locked by user |

## Presentation

```markdown
## Worktree Status

| # | Path | Branch | PR | Last Commit | Work | Status |
|---|------|--------|----|-------------|------|--------|
| 1 | <worktree-root>/feat-auth | feat/add-auth | #21 OPEN | 2d ago | safe | in-review |
| 2 | <worktree-root>/old-fix | worktree-old-fix | — | 23d ago | safe | stale |
| 3 | <worktree-root>/spike | spike/idea | — | 31d ago | stranded 4 | stranded |

**Summary:** 3 worktrees (1 in-review, 1 stale, 1 stranded — 4 commits at risk)
```

Report the at-risk commit total in the summary whenever it is non-zero; a stranded row that reads as one line among many is how the commits get swept.

If issues are found, suggest actions: `/worktree cleanup` for stale/merged, `git worktree unlock` for locked. For `stranded` and `unknown`, suggest pushing the branch first — `git -C <path> push -u origin HEAD` — which converts the row to `safe` without a judgement call.
