# The `git` action — branch audit + classification + deletion

Full detail for the `git` action's branch-audit half (§4.2–§4.7). SKILL.md keeps the §4 framing, the §4.1 prune/gc step, and the branch-deletion safety rule; this file carries classification semantics, the report shape, and interactive deletion.

## 4.2–4.4 Collect branch facts (script)

Run the branch-audit script — do not reimplement collection inline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-audit.sh
```

**Output contract** (per branch): `Branch:`, `Tier:`, `Age days:`, `PR:`, `Unpushed:`, `Reason:`; trailing `Summary: protected=… worktree=… safe=… likely-safe=… review=…`.

**`Unpushed:` line** — commits at risk of loss. With an upstream: `N ahead of <upstream>`. With no upstream: `no upstream, M commits not on origin/<default>` (or `no upstream (no origin/<default> to compare)` when the default branch is unfetched). Never-pushed local work is invisible to `@{upstream}`-based ahead reporting, so this line is the only signal that a no-upstream branch carries unmerged commits — surface it before offering any deletion.

**Default branch resolution** (inside script): `origin/HEAD` symbolic ref → `gh repo view --json defaultBranchRef` → `main`.

**PR map** (inside script): single batched `gh pr list --state all --json headRefName,state,number,headRefOid` — not per-branch loops.

## 4.5 Classify each branch (4-tier algorithm)

The script applies rules in priority order (first match wins). Agent interprets output; do not duplicate the bash loop.

| Priority | Condition | Tier | Reason |
|----------|-----------|------|--------|
| 1 | Branch = current | PROTECTED | current branch |
| 2 | Branch = default | PROTECTED | default branch |
| 3 | Branch glob-matches protected pattern (see list below) | PROTECTED | protected pattern |
| 4 | Branch checked out in a linked worktree | WORKTREE | checked out in worktree — clean up the worktree first |
| 5 | `PR` = MERGED and local tip matches PR headRefOid | SAFE | PR merged |
| 5b | `PR` = MERGED and local tip differs from headRefOid | REVIEW | PR merged but branch has commits since merge |
| 6 | Branch in git `--merged` ancestry | SAFE | merged (non-squash) |
| 7 | `PR` = CLOSED | REVIEW | PR closed without merge |
| 8 | Upstream gone (`: gone]` in `branch -vv`) | LIKELY-SAFE | upstream deleted |
| 9 | No upstream, M commits not on origin/default | REVIEW | no upstream, M commits not on origin/<default> |
| 10 | Age > 90 days | REVIEW | stale |
| 11 | No PR, no tracking, not merged | REVIEW | orphaned |

Stale threshold: 90 days (`CLEAN_STALE_BRANCH_DAYS` in `cleanup-paths.sh`). Branch can match multiple REVIEW reasons — list all in report.

**WORKTREE tier (priority 4)** — a branch checked out in a linked worktree is a real cleanup candidate (it may be merged or gone), but `git branch -d` on it fails or, forced, breaks the worktree. It is therefore its own bucket, distinct from PROTECTED: never offer it for deletion here — route the user to the worktree-management tool to remove the worktree first (after which a later audit reclassifies the branch on its merge/PR state). Priority 4 sits below the protected checks so a `release/*` or default branch that also happens to be checked out stays PROTECTED.

**No-upstream class (priority 9)** — a never-pushed branch with commits not on `origin/<default>` is unmerged local work; it ranks above the generic stale/orphaned REVIEW reasons so the unpushed-commit count is the headline. Stays REVIEW (never a deletion candidate) — confirm the commit loss explicitly before any deletion.

**Protected branch patterns (priority 3):** exact names and globs that MUST NEVER be offered for deletion — `main`, `master`, `develop`, `release/*`, `hotfix/*`. Matched via bash `case` in `clean_branch_matches_protected_pattern`. Extend with repo-specific long-lived branches if needed (e.g. `staging`, `production`, `deploy/*`).

**Squash-merge handling:** `git branch --merged` (priority 6) misses squash-merged branches because squash creates a new combined commit. `gh pr list` (priority 5) correctly detects these via PR state. When `gh` is unavailable, squash-merged branches land in REVIEW tier — safe-conservative handling.

## 4.6 Present report

Map script output to a table:

```markdown
## Branch Audit

| Branch | Tier | Age | PR | Unpushed | Reason |
|--------|------|-----|----|----------|--------|
| main | PROTECTED | 0d | — | 0 ahead of origin/main | default branch |
| feat/parked | WORKTREE | 3d | — | 0 ahead of origin/feat/parked | checked out in worktree — clean up the worktree first |
| feat/old-thing | SAFE | 45d | #123 MERGED | 0 ahead of origin/feat/old-thing | PR merged |
| refactor/x | LIKELY-SAFE | 12d | — | no upstream (no origin/main to compare) | upstream gone |
| draft/local | REVIEW | 4d | — | no upstream, 5 commits not on origin/main | no upstream, 5 commits not on origin/main |
| experiment | REVIEW | 120d | — | 0 ahead of origin/experiment | stale (120d), orphaned |

**Summary:** N protected, W worktree, M safe, P likely-safe, Q review
**Deletion candidates (M+P):** <SAFE + LIKELY-SAFE branches only — never WORKTREE or REVIEW>
**Worktree cleanup first:** <WORKTREE branches — route to the worktree-management tool>
```

## 4.7 Interactive deletion

If SAFE or LIKELY-SAFE branches exist, present options via `AskUserQuestion`:

- "Delete all SAFE branches" — `git branch -D` for squash-merged (PR MERGED), `git branch -d` for others (safe delete, refuses if unmerged). Squash merge changes SHA so `-d` refuses even when PR is merged — `-D` is safe because PR merge is already confirmed via `gh pr list`
- "Delete SAFE + LIKELY-SAFE" — same as above for SAFE; `git branch -D` for LIKELY-SAFE (force delete — upstream gone)
- "Skip (audit only)" — no deletion

For each deletion, report result:

```
Deleted: feat/old-thing (was SAFE — PR #123 merged)
Deleted: refactor/x (was LIKELY-SAFE — upstream gone)
Failed: some-branch — has unmerged changes (use -D to force)
```

After deletion, run `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-prune.sh --apply` to prune orphaned worktree metadata and compact loose objects.
