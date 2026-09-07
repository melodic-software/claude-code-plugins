# The `git` action — branch audit + classification + deletion

Full detail for the `git` action's branch-audit half (§4.2–§4.7). SKILL.md keeps the §4 framing, the §4.1 prune/gc step, and the branch-deletion safety rule; this file carries classification semantics, the report shape, and interactive deletion.

## 4.2–4.4 Collect branch facts (script)

Run the branch-audit script — do not reimplement collection inline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-audit.sh
```

**Output contract** (per branch): `Branch:`, `Tip:`, `Tier:`, `Age days:`, `PR:`, `Unpushed:`, `Reason:`; then exactly one of `TipCapture: <path>` or `TipCaptureError: <why>`; trailing `Summary: protected=… worktree=… safe=… likely-safe=… review=…`.

**`Tip:` line and the tip capture.** Every branch carries its tip commit id as its own field, whatever its verdict: a verdict can be wrong in either direction, and the tip is what makes a wrongly deleted branch restorable. The same facts are written to a durable TSV, the **tip capture**, and its path is printed as `TipCapture:`. Path convention: `<git-common-dir>/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv`, i.e. the main checkout's `.git/repo-hygiene/branch-tips/` even when the audit ran in a linked worktree (`--capture-file PATH` overrides). Columns: `branch`, `tip`, `tier`, `pr`, `upstream`, `ahead`, `behind`, `not_on_default`, `captured_at`, with header lines naming the repository, its common dir, the default branch, and the restore command. The file is sealed only when every row landed; otherwise the audit prints `TipCaptureError:` and no path. **A `TipCaptureError:` means no deletion can proceed from this run**: fix the cause (or pass `--capture-file` to a writable location) and re-run the audit. Capture files are small and are never removed by this skill; delete old ones by hand if they accumulate.

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
| main | PROTECTED | 0d | — | 0 ahead of origin/<default> | default branch |
| feat/parked | WORKTREE | 3d | — | 0 ahead of origin/feat/parked | checked out in worktree — clean up the worktree first |
| feat/old-thing | SAFE | 45d | #123 MERGED | 0 ahead of origin/feat/old-thing | PR merged |
| refactor/x | LIKELY-SAFE | 12d | — | no upstream (no origin/<default> to compare) | upstream gone |
| draft/local | REVIEW | 4d | — | no upstream, 5 commits not on origin/<default> | no upstream, 5 commits not on origin/<default> |
| experiment | REVIEW | 120d | — | 0 ahead of origin/experiment | stale (120d), orphaned |

**Summary:** N protected, W worktree, M safe, P likely-safe, Q review
**Deletion candidates (M+P):** <SAFE + LIKELY-SAFE branches only — never WORKTREE or REVIEW>
**Worktree cleanup first:** <WORKTREE branches — route to the worktree-management tool>
```

## 4.7 Interactive deletion

If SAFE or LIKELY-SAFE branches exist, present options via the [confirmation gate](../SKILL.md#confirmation-gate):

- "Delete all SAFE branches"
- "Delete SAFE + LIKELY-SAFE"
- "Skip (audit only)" — no deletion

**Every deletion goes through the deletion script, never a bare `git branch -d`/`-D`.** The script is the enforcement point for tip capture: it refuses the whole batch (exit 3, nothing deleted) unless it is given the audit's `TipCapture:` file, every branch in the batch has a row in it, and every captured tip still equals the branch's current tip. Dry-run first, with exactly the set the user is about to confirm:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-delete.sh --capture <TipCapture path> --dry-run <branch>...
```

Show the `Planned:` lines (branch, tip, tier, and whether it is a safe delete, admitted only because the tip is merged into `origin/<default>`, or a force delete) in the confirmation. After the user confirms that exact set:

```bash
CLEAN_GUARD_ACK=1 bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-delete.sh --capture <TipCapture path> --apply <branch>...
```

Per branch the script, in this order, re-checks the tip against the capture, pins it under `refs/repo-hygiene/deleted/<branch>` (so a later `gc` cannot prune the commits the record points at), appends the deletion to the ledger `<capture>.deleted.tsv` (beside the capture's real file, symlinks resolved), and only then deletes, with `git update-ref -d refs/heads/<branch> <captured tip>`: an atomic compare-and-delete inside git's ref lock, which refuses when the tip is no longer the captured one. The re-check closes the window between the batch check and the pin; the conditional delete closes the window between the pin and the delete, which a plain `git branch -D` leaves open. A SAFE-by-ancestry branch is a safe delete, admitted at the batch check only when its tip is merged into `origin/<default>` (the check `git branch -d` would have made); SAFE with a merged PR (a squash merge changes the SHA, so that check would refuse a branch whose merge `gh pr list` already confirmed) and LIKELY-SAFE are force deletes. A failure in any step before the delete aborts the batch there (exit 1): branches already deleted keep their pin and ledger row, the failing branch and everything after it are untouched, and the `Summary:` line counts each. A delete refused because the tip moved also aborts the batch: the branch stays at its new tip, its pin stays (harmless; it records the tip the audit saw), and the ledger gains a `# not deleted:` note. A refusal (a branch whose tip moved since the audit, a branch with no captured tip, a SAFE-by-ancestry row whose tip is not merged, a foreign or unreadable capture) stops the batch before the first deletion; re-run the audit for a fresh capture rather than deleting against a stale identifier. REVIEW branches need `--force-review`, and only after the user has confirmed the loss named in their `Unpushed:`/`Reason:` lines; PROTECTED and WORKTREE branches are never deletable here.

The script reports one line per branch:

```
Deleted: feat/old-thing <tip> (was SAFE) restore: git branch feat/old-thing <tip>
Aborted: some-branch (tip moved between pin and delete: captured <tip>, now <sha>; branch left intact, pin refs/repo-hygiene/deleted/some-branch still records <tip>)
Summary: planned=N refused=0 deleted=N failed=0 aborted=1 untouched=U
Restore: git branch <branch> <tip> (tips in <capture> and <ledger>; pinned under refs/repo-hygiene/deleted/<branch>)
```

Relay the `Restore:` line to the user verbatim after every deletion batch.

After deletion, run `bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-prune.sh --apply` to prune orphaned worktree metadata and compact loose objects. The pinned refs keep every deleted tip reachable through that step.

## 4.8 Restore a deleted branch

Everything needed is in the repository's main `.git`, so recovery needs no memory of how the run was invoked:

1. Find the tip. Newest capture and ledger: `ls -t .git/repo-hygiene/branch-tips/` (the ledger `<stamp>.deleted.tsv` lists only branches actually deleted; the capture `<stamp>.tsv` lists every branch the audit saw, deleted or not). Or read the pin directly: `git rev-parse refs/repo-hygiene/deleted/<branch>`.
2. Recreate the branch: `git branch <branch> <tip>` (or `git branch <branch> refs/repo-hygiene/deleted/<branch>`).
3. Optionally drop the pin once the branch is back or is no longer wanted: `git update-ref -d refs/repo-hygiene/deleted/<branch>`. Pins are never removed by this skill; `git for-each-ref refs/repo-hygiene/deleted/` lists them. A pin keeps its commits out of `gc`, so dropping pins is how that space is eventually reclaimed.

A branch deleted, recreated under the same name, and deleted again overwrites its pin; the earlier tip stays in the earlier capture and ledger but is no longer protected from `gc`.
