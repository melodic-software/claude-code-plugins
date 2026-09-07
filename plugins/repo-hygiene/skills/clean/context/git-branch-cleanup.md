# The `git` action — branch audit + classification + deletion

Full detail for the `git` action's branch-audit half (§4.2–§4.7). SKILL.md keeps the §4 framing, the §4.1 prune/gc step, and the branch-deletion safety rule; this file carries classification semantics, the report shape, and interactive deletion.

## 4.2–4.4 Collect branch facts (script)

Run the branch-audit script — do not reimplement collection inline:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-audit.sh
```

**Output contract**: a leading PR-map status line, exactly one of `PRCount: <n>` or `PRDataUnavailable: <why>`, optionally followed by `PRDataTruncated: <why>`; then per branch `Branch:`, `Tip:`, `Tier:`, `Age days:`, `PR:`, `Unpushed:`, `Loss:`, `Reason:`; then the loss block, `LossBlock: <n> ...` through `LossBlockEnd: <n>` (always present, `0` when no branch loses work), with one `LossBranch:` per LOSSY branch followed by its `LossCommit:` lines; then exactly one of `TipCapture: <path>` or `TipCaptureError: <why>`; trailing `Summary: protected=… worktree=… safe=… likely-safe=… lossy=… review=…`.

**PR-map status line**, the trustworthiness of every PR-derived verdict below. `PRCount: 0` is a repository with no pull requests, which is a real and complete answer. `PRDataUnavailable:` is a repository whose pull requests could not be read at all (no `gh`, no `jq`, unauthenticated, no GitHub remote, unparsable output, or the map file could not be created): squash-merge detection never ran, priority 5 cannot fire, and a landed branch falls through to REVIEW. `PRDataTruncated:` means the returned count equalled the requested cap and rows may have been discarded, with the same effect for whichever branches are missing from the map. Surface either line in the confirmation gate; underneath one, the tier split is not complete evidence.

**`Loss:` line**, what a deletion would lose, measured as the commits on the branch reachable from no remote-tracking ref and no tag (`git rev-list <branch> --not --remotes --tags`). Values: `<n> commits only on this branch` (the branch is LOSSY); the same count with a trailing annotation (`PR open, stays REVIEW` or `PR merged; count unreliable after a squash, stays REVIEW`); `none (every commit is on a remote ref or a tag)`; `undetermined (<why>)` when the tip, `origin/<default>`, or the count itself is unavailable; `not assessed (<tier>)` for PROTECTED, WORKTREE, SAFE and LIKELY-SAFE, whose verdicts do not depend on it. Other local branches are deliberately not counted as a place the work persists: a sibling in the same deletion batch is not somewhere else.

**`Tip:` line and the tip capture.** Every branch carries its tip commit id as its own field, whatever its verdict: a verdict can be wrong in either direction, and the tip is what makes a wrongly deleted branch restorable. The same facts are written to a durable TSV, the **tip capture**, and its path is printed as `TipCapture:`. Path convention: `<git-common-dir>/repo-hygiene/branch-tips/<utc-stamp>-<pid>.tsv`, i.e. the main checkout's `.git/repo-hygiene/branch-tips/` even when the audit ran in a linked worktree (`--capture-file PATH` overrides). Columns: `branch`, `tip`, `tier`, `pr`, `upstream`, `ahead`, `behind`, `not_on_default`, `captured_at`, with header lines naming the repository, its common dir, the default branch, and the restore command. The file is sealed only when every row landed; otherwise the audit prints `TipCaptureError:` and no path. **A `TipCaptureError:` means no deletion can proceed from this run**: fix the cause (or pass `--capture-file` to a writable location) and re-run the audit. Capture files are small and are never removed by this skill; delete old ones by hand if they accumulate.

**`Unpushed:` line** — commits at risk of loss. With an upstream: `N ahead of <upstream>`. With no upstream: `no upstream, M commits not on origin/<default>` (or `no upstream (no origin/<default> to compare)` when the default branch is unfetched). Never-pushed local work is invisible to `@{upstream}`-based ahead reporting, so this line is the only signal that a no-upstream branch carries unmerged commits — surface it before offering any deletion.

**Default branch resolution** (inside script): `origin/HEAD` symbolic ref → `gh repo view --json defaultBranchRef` → `main`.

**PR map** (inside script): single batched `gh pr list --state all --json headRefName,state,number,headRefOid`, not per-branch loops, via the shared `clean_pr_map` helper the stash audit also uses. The cap is a high explicit `--limit` (`gh` has no unlimited sentinel and rejects `--limit 0`), and truncation is detected by comparing the returned count against that limit. Override the cap with `CLEAN_PR_LIST_LIMIT`.

## 4.5 Classify each branch (tier algorithm)

The script applies rules in priority order (first match wins), then refines a REVIEW verdict into LOSSY when the loss is measured and positive (see the refinement below the table). Agent interprets output; do not duplicate the bash loop.

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

**LOSSY refinement (after the table).** A REVIEW verdict becomes LOSSY, "deletable, and deleting it loses work", when every condition below holds; the `Reason:` keeps the chain's text and the `Loss:` line carries the count. The boundary is a conjunction of checkable facts, not a judgement:

| Condition | If it fails |
|-----------|-------------|
| The chain above said REVIEW | SAFE / LIKELY-SAFE / PROTECTED / WORKTREE keep their verdict; `Loss: not assessed` |
| The tip resolved | REVIEW, `Loss: undetermined (tip unresolved)` |
| `origin/<default>` exists locally, so "landed" can be evaluated | REVIEW, `Loss: undetermined (no origin/<default> to compare against)` |
| `git rev-list <branch> --not --remotes --tags` succeeded | REVIEW, `Loss: undetermined (could not count ...)` |
| That count is positive | REVIEW, `Loss: none (...)` (the work exists on a remote ref or a tag; nothing is lost, but nothing says it landed either) |
| The PR state is not MERGED | REVIEW (priority 5b): a squash lands the work under a new SHA, so the count overstates the loss; annotated |
| The PR state is not OPEN | REVIEW: an open PR is an active claim on the branch; annotated |

Every missing or failed signal therefore lands in REVIEW, never in LOSSY and never in SAFE: doubt about the loss is resolved toward the verdict that asks more of the operator. The other direction is closed by construction, since SAFE and LIKELY-SAFE are never re-examined here and the refinement only ever moves a branch from REVIEW to LOSSY. A PR map that is unavailable (no `gh`) does not withhold the tier: the loss is a git fact and the block still names it; only the MERGED and OPEN demotions cannot fire, so under `PRDataUnavailable:` treat the block's branches as possibly carrying an open PR.

**WORKTREE tier (priority 4)** — a branch checked out in a linked worktree is a real cleanup candidate (it may be merged or gone), but `git branch -d` on it fails or, forced, breaks the worktree. It is therefore its own bucket, distinct from PROTECTED: never offer it for deletion here — route the user to the worktree-management tool to remove the worktree first (after which a later audit reclassifies the branch on its merge/PR state). Priority 4 sits below the protected checks so a `release/*` or default branch that also happens to be checked out stays PROTECTED.

**No-upstream class (priority 9).** A never-pushed branch with commits not on `origin/<default>` is unmerged local work; it ranks above the generic stale/orphaned REVIEW reasons so the unpushed-commit count is the headline. Never SAFE or LIKELY-SAFE: with a measured positive loss it is LOSSY and appears in the loss block with its own confirmation; otherwise it stays REVIEW.

**Protected branch patterns (priority 3):** exact names and globs that MUST NEVER be offered for deletion — `main`, `master`, `develop`, `release/*`, `hotfix/*`. Matched via bash `case` in `clean_branch_matches_protected_pattern`. Extend with repo-specific long-lived branches if needed (e.g. `staging`, `production`, `deploy/*`).

**Squash-merge handling:** `git branch --merged` (priority 6) misses squash-merged branches because squash creates a new combined commit. `gh pr list` (priority 5) correctly detects these via PR state. When the PR map is unavailable or truncated, the affected squash-merged branches land in REVIEW tier, which is safe-conservative handling only because the audit says so out loud: that is what the `PRDataUnavailable:` and `PRDataTruncated:` lines are for. A silently short map produces the same REVIEW verdicts with nothing to distinguish them from a genuine one.

## 4.6 Present report

Map script output to a table:

```markdown
## Branch Audit

| Branch | Tier | Age | PR | Unpushed | Loss | Reason |
|--------|------|-----|----|----------|------|--------|
| main | PROTECTED | 0d | none | 0 ahead of origin/<default> | not assessed | default branch |
| feat/parked | WORKTREE | 3d | none | 0 ahead of origin/feat/parked | not assessed | checked out in worktree, clean up the worktree first |
| feat/old-thing | SAFE | 45d | #123 MERGED | 0 ahead of origin/feat/old-thing | not assessed | PR merged |
| refactor/x | LIKELY-SAFE | 12d | none | no upstream (no origin/<default> to compare) | not assessed | upstream gone |
| draft/local | LOSSY | 4d | none | no upstream, 5 commits not on origin/<default> | 5 commits only on this branch | no upstream, 5 commits not on origin/<default> |
| experiment | REVIEW | 120d | none | 0 ahead of origin/experiment | none | stale (120d), orphaned |

**Summary:** N protected, W worktree, M safe, P likely-safe, L lossy, Q review
**Deletion candidates (M+P):** <SAFE + LIKELY-SAFE branches only, never WORKTREE, LOSSY or REVIEW>
**Worktree cleanup first:** <WORKTREE branches — route to the worktree-management tool>
```

Then, as its own section and immediately before the confirmation question, the loss block. Render the script's `LossBranch:` and `LossCommit:` lines for each LOSSY branch, not a summary of them:

```markdown
## Deleting these loses work (L branches, own decision)

- **draft/local** loses 5 commits that exist on no remote ref and no tag (no upstream, 5 commits not on origin/<default>), tip <sha>
  - <sha7> <subject>
  - ... (and K more, when the block capped the listing)
```

The block must appear even when the table already shows the tier: a column value is not a decision surface, because a prose flag beside a binary verdict is easy to skim past when confirming deletion. When the block is empty (`LossBlock: 0`), say so in one line rather than omitting the section.

## 4.7 Interactive deletion

If SAFE or LIKELY-SAFE branches exist, present options via the [confirmation gate](../SKILL.md#confirmation-gate):

- "Delete all SAFE branches"
- "Delete SAFE + LIKELY-SAFE"
- "Skip (audit only)" — no deletion

None of those answers covers a LOSSY branch. If the loss block is non-empty, ask about it **separately**, after the loss block has been shown and after the question above has been answered, naming the branches and what each loses:

- "Also delete the L lossy branches, losing the commits listed above"
- "Keep them"

An answer to the first question is never carried over to the second, and a general "delete everything" is not an answer to either. Run the LOSSY set as its own `git-branch-delete.sh` batch with `--accept-loss`; the script refuses a batch that contains a LOSSY branch without that flag, and `--force-review` does not stand in for it.

**Every deletion goes through the deletion script, never a bare `git branch -d`/`-D`.** The script is the enforcement point for tip capture: it refuses the whole batch (exit 3, nothing deleted) unless it is given the audit's `TipCapture:` file, every branch in the batch has a row in it, and every captured tip still equals the branch's current tip. Dry-run first, with exactly the set the user is about to confirm:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-delete.sh --capture <TipCapture path> --dry-run <branch>...
```

Show the `Planned:` lines (branch, tip, tier, and whether it is a safe delete, admitted only because the tip is merged into `origin/<default>`, or a force delete) in the confirmation. After the user confirms that exact set:

```bash
CLEAN_GUARD_ACK=1 bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/git-branch-delete.sh --capture <TipCapture path> --apply <branch>...
```

Per branch the script, in this order, re-checks the tip against the capture, pins it under `refs/repo-hygiene/deleted/<branch>` (so a later `gc` cannot prune the commits the record points at), appends the deletion to the ledger `<capture>.deleted.tsv` (beside the capture's real file, symlinks resolved), and only then deletes, with `git update-ref -d refs/heads/<branch> <captured tip>`: an atomic compare-and-delete inside git's ref lock, which refuses when the tip is no longer the captured one. The re-check closes the window between the batch check and the pin; the conditional delete closes the window between the pin and the delete, which a plain `git branch -D` leaves open. A SAFE-by-ancestry branch is a safe delete, admitted at the batch check only when its tip is merged into `origin/<default>` (the check `git branch -d` would have made). A SAFE row is a force delete only when its captured `pr` matches the audit's exact merged-PR format (`#<n> MERGED` or `#<n> MERGED (tip drift)`): a squash merge changes the SHA, so the ancestry check would refuse a branch whose merge `gh pr list` already confirmed, but both `tier` and `pr` are untrusted capture text, so a `pr` that merely contains the substring MERGED still takes the ancestry check. LIKELY-SAFE is a force delete. A capture whose `# common_dir:` is missing or the literal `unknown` is refused: that field is the only check that the capture describes this repository, so an unresolved value is a refusal, not a skipped check. A failure in any step before the delete aborts the batch there (exit 1): branches already deleted keep their pin and ledger row, the failing branch and everything after it are untouched, and the `Summary:` line counts each. A delete refused because the tip moved also aborts the batch: the branch stays at its new tip, its pin stays (harmless; it records the tip the audit saw), and the ledger gains a `# not deleted:` note. A refusal (a branch whose tip moved since the audit, a branch with no captured tip, a captured non-LOSSY row whose commits now exist on no remote ref and no tag, a SAFE-by-ancestry row whose tip is not merged, a foreign, unreadable, or unresolved-`common_dir` capture) stops the batch before the first deletion; re-run the audit for a fresh capture rather than deleting against a stale identifier. LOSSY branches need `--accept-loss`, and only after the user has confirmed the loss block as its own decision (the dry-run's `Planned:` line for a LOSSY branch restates the live count: `(LOSSY, force delete, loses N commits only on this branch)`); REVIEW branches need `--force-review`, and only after the user has confirmed the loss named in their `Unpushed:`/`Reason:` lines; neither flag admits the other tier. PROTECTED and WORKTREE branches are never deletable here.

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
