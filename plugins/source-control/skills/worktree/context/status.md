# Worktree `status`: data collection, classification, presentation

`<scripts-dir>` is the scripts directory resolved in SKILL.md. This file is read as raw bytes, so substitute that resolved absolute path for `<scripts-dir>` before a command reaches Bash.

Full detail for the `/source-control:worktree status` action. SKILL.md carries the headline; this file carries the porcelain-parse fields, the staleness math, the stranded-work axis, the classification table, and the output schema.

## Data collection

1. **Worktree list**: Run `bash "<scripts-dir>/lib/worktree-facts.sh" list <repo>`. Do not parse porcelain by hand. It prints a header and one TSV row per worktree: `path head branch bare linked locked lock_reason prunable`, with `-` for an empty column. `locked` is `yes` for a lock with no reason too.

   `git worktree list --porcelain` emits correct absolute paths for every layout (standard clone, bare-clone hub, `.claude/worktrees/`), so `status` and `audit` need no layout-specific detection here, unlike Smart Default / `create` / `cleanup`, which resolve the hub root (`git rev-parse --git-common-dir` ending in `.bare`) for path construction.

2. **PR cross-reference**: Run `gh pr list --state all --json number,title,state,headRefName` once (not per-branch, since batch is more efficient). Match each worktree's branch name against `headRefName`. Graceful degradation: if `gh` fails, skip PR info and note "GitHub API unavailable."

3. **Last commit date**: For each worktree branch, get date of last commit:

   ```bash
   git log -1 --format='%ci' <branch> 2>/dev/null
   ```

4. **Staleness**: Compare last commit date to today. Default threshold: **14 days**. The configured override is `${user_config.worktree_stale_days}`. Use that value when it is a positive number, falling back to 14 when it is empty, invalid, or a literal unexpanded `${user_config.worktree_stale_days}` token.

5. **Stranded-work record**: age and PR state answer *is anyone still working here*; neither answers *would removing this destroy a commit*. Run the detection engine once per repository. It enumerates the worktrees itself and emits one TSV row per registered worktree:

   ```bash
   bash "<scripts-dir>/landed-work.sh" --repo-dir <repo-toplevel> --merged-refs-file <file>
   ```

   Write the merged `headRefName` values from step 2 to `<file>`, one per line. That is what marks a row as a likely *superseded draft* (a pull request carrying this branch NAME merged, so the base may already hold a later revision of the same change). Name-only evidence: a branch name reused after that merge still matches, so `superseded` narrows the reading of a row but never authorizes removing it. Omit the flag when `gh` was unavailable.

   Join rows to worktrees on the `path` column. The columns this file consumes: `unpushed`, `landed`, `base`, `peers`, `risk`, `reason`.

   Graceful degradation: on a non-zero exit, note "stranded-work detection unavailable: the Work column is unproven" and set every Work cell to `unknown`. Do not fall back to a hand-rolled probe: `--branches` reports other branches' commits rather than this worktree's, `@{upstream}..HEAD` returns nothing for a branch with no upstream, and a per-commit patch-id cannot see a multi-commit squash-merge. An unproven column is honest; a wrong one is not.

## Status classification

Two independent axes. **Work** answers whether removal would destroy a commit and is read straight from the engine's `risk` column; **Status** answers what should happen next. Classify Work first: it outranks age and PR state, because `stale` describes attention and `stranded` describes loss.

| Work | Engine `risk` | Meaning |
|------|---------------|---------|
| `safe` | `landed`, `ok`, `bare` | Nothing unpushed, or every unpushed commit's content is already on `base` |
| `stranded N` | `STRANDED` | N unpushed commits whose content is not on the base. Removal plus the branch deletion that follows it destroys them |
| `superseded` | `superseded` | Not landed, but a MERGED PR carried this branch's NAME, probably a draft the base moved past. **Treat exactly as `stranded`**: the match is on the name, so a name reused after that merge carries new commits that are still the only copy |
| `unknown` | `UNKNOWN` | No base resolved, or a probe failed. **Treat exactly as `stranded`**: the engine reports `?` rather than `no` precisely so an ambiguity is never read as safe |
| `in-progress` | `in-progress` | A merge, rebase, cherry-pick, or revert is paused here. Nothing is unpushed, but the conflict resolutions in the working tree are not recorded anywhere and the sequencer state dies with the directory |
| `dirty` | `dirty` | Uncommitted edits with nothing unpushed, **or** a working tree whose status could not be read at all, which the count columns show as `-`. The two are not distinguished, and neither is removable unattended |
| `notgit` | `notgit` | Path is not a work-tree root. Probing it with `git -C` reports the *containing* repository's clean state |

**Any risk value not in this table maps to `unknown`.** The mapping is closed on the safe side only: a value this file does not recognize is one it cannot vouch for, and the fail-closed rule that governs the engine governs its consumers too.

Every field the engine emits is non-empty: an absent value is the literal `-`, because a blank field collapses under tab-splitting and shifts every later column. Render `-` as "not resolved", never verbatim.

A `stranded` row whose `peers` column names another worktree is recoverable from that peer. Present it as `stranded N (peer: <path>)`, a materially different disposition from stranded with no peer.

| Status | Condition |
|--------|-----------|
| `stranded` | Work is `stranded`, `unknown`, or `superseded`. Outranks every row below |
| `notgit` | Work is `notgit` |
| `active` | Recent commits, no issues |
| `stale` | Last commit > threshold days ago, no open PR, **and** Work is `safe` |
| `in-review` | Has an open PR (regardless of commit age) |
| `merged` | PR was merged, **or** every unpushed commit landed on the base (`landed=yes`). The branch's content is on the base either way |
| `prunable` | Git flagged as prunable (directory missing or corrupted) |
| `locked` | Explicitly locked by user |
| `unclaimed` | Linked worktree whose row has `locked=yes` with `lock_reason=-`. A plain `git worktree add` that bypassed the helper. `scripts/worktree-claim.sh report` is the check; `claim <path>` arms a session-distinct reason. Not the same as `locked`: there is no claim text for another session to read |

## Presentation

```markdown
## Worktree Status

| # | Path | Branch | PR | Last Commit | Work | Status |
|---|------|--------|----|-------------|------|--------|
| 1 | <worktree-root>/feat-auth | feat/add-auth | #21 OPEN | 2d ago | safe | in-review |
| 2 | <worktree-root>/old-fix | worktree-old-fix | none | 23d ago | safe | stale |
| 3 | <worktree-root>/spike | spike/idea | none | 31d ago | stranded 4 | stranded |

**Summary:** 3 worktrees (1 in-review, 1 stale, 1 stranded with 4 commits at risk)
```

Report the at-risk commit total in the summary whenever it is non-zero; a stranded row that reads as one line among many is how the commits get swept.

If issues are found, suggest actions: `/source-control:worktree cleanup` for stale/merged, `/source-control:worktree cleanup` also for a locked worktree whose PR is merged or whose work has landed (`worktree-claim.sh stale <path>` exits 0), which cleanup treats as a stale lock; a locked worktree without that evidence is left alone. For `stranded` and `unknown`, suggest pushing the branch first with `git -C <path> push -u origin HEAD`, which converts the row to `safe` without a judgment call.
