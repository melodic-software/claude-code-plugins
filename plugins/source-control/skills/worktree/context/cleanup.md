# Worktree `cleanup` — full 5-step procedure

Full detail for the `/source-control:worktree cleanup [--dry-run]` action. SKILL.md carries the headline plus the safety invariants; this file carries the complete step-by-step (prune → identify → present → execute → verify), including the Windows file-lock handling and the user-emitted branch deletion.

Remove stale worktrees, orphaned metadata, and branches from merged PRs.

## Step 1: Prune orphaned metadata

```bash
git worktree prune
```

Cleans up worktree administrative records for directories that no longer exist on disk (e.g., manually deleted via `rm -rf`).

In `--dry-run` mode this step runs `git worktree prune --dry-run` instead — it reports what would be pruned without touching worktree metadata, keeping the whole dry-run pass mutation-free.

## Step 2: Identify cleanup candidates

Run `status` logic internally and identify candidates:

| Reason | Detection method |
|--------|-----------------|
| **Orphaned directory** | Directory exists under a worktree root but NOT in `git worktree list` output. Scan every root your project uses — common layouts: (1) `<repo-root>/.worktrees/`; (2) Claude Code's default `<repo-root>/.claude/worktrees/`; (3) bare-clone hub `<hub-root>/<name>/` — siblings of `.bare/`, found by detecting the hub (`git rev-parse --git-common-dir` ends in `.bare`) and resolving `<hub-root>` as its parent (same detection the Smart Default + `create` pre-flight already use). Empty shells are left when Claude Code's built-in cleanup removes worktree contents but the directory husk persists — from terminal kill without clean exit, OR a file lock blocking deletion (release per Step 4a first). Safe to remove once unlocked |
| **Prunable** | `git worktree list --porcelain` shows `prunable` flag |
| **PR merged** | `gh pr list --state merged --head <branch>` returns non-empty result |
| **Stale** | Last commit > threshold days, no open PR, no locked flag |
| **Stranded** | `landed-work.sh` reports `risk=STRANDED` or `risk=UNKNOWN` — **not a cleanup candidate.** Listed here because it is the row most easily mistaken for `Stale`: both are old and quiet, but this one holds unpushed commits whose content is not on the base |

Extract actual branch name from porcelain output (`branch refs/heads/<name>`), not from directory name — they may differ if branch was renamed.

Collect the stranded-work record in the same pass, per `status.md`'s data-collection step 5 — one run per repository, joined on `path`. Every guard below reads its `risk` column, so a candidate list built without it cannot be executed safely.

## Step 3: Present candidates

```markdown
## Cleanup Candidates

| # | Worktree | Branch | Reason |
|---|----------|--------|--------|
| 1 | <worktree-root>/old-fix | fix/old-thing | PR #18 merged 5d ago |
| 2 | <worktree-root>/moonlit-popping-pike | — | Orphaned directory (empty, no git ref) |
| 3 | (orphaned metadata) | — | Directory no longer exists |

**Action:** Remove these 3 items? (yes/no/select)
```

## Step 4: Execute or report

- **`--dry-run`**: Report candidates only, take no action. Exit.
- **Otherwise**: Ask for confirmation. On "yes", run each candidate through phases 4a → 4b → 4c.

### Step 4a: Release file locks first (Windows-critical)

`git worktree remove --force` overrides git's dirty/locked-worktree check but does NOT release OS file handles. On Windows, any process holding a file under the worktree blocks directory deletion ("Permission denied" / "being used by another process") — `--force` then unregisters the worktree from git but leaves a husk on disk. Before removing a candidate, stop the processes rooted in its path:

- **Build servers** holding compiled output — e.g. `dotnet build-server shutdown` (.NET / VBCSCompiler + MSBuild), Gradle `--stop`, or your stack's equivalent. They hold bin/output DLLs open.
- **Long-lived daemons / MCP servers** started inside the worktree — identify processes whose executable path or command line is under the candidate directory, and stop ONLY those (never processes belonging to other live worktrees).

Skipping 4a is the usual reason a previous `/source-control:worktree cleanup` left husks behind — Step 5 then reports them honestly rather than hiding the failure.

### Step 4b: Remove the worktree

```bash
# Orphaned directory (on disk, not in `git worktree list`): remove the husk
rm -rf <path>

# Git-tracked worktree — plain removal first. It FAILS on a dirty worktree
# specifically to prevent data loss; never blind-escalate past that.
git worktree remove <path>
```

**Two guards run before ANY removal, plain or forced, in this order.** The stranded-work guard first, because it can abort the removal outright — running the carried-file comparison ahead of it spends work reconciling files for a worktree that is not going to be removed, and an aborted removal loses nothing that needed syncing.

**1. Stranded-work guard:** removal itself is recoverable — `git worktree remove` unregisters the directory and leaves the branch ref intact — but a detached-HEAD worktree has no branch ref holding its commits, and for every other candidate the `git branch -D` emitted in Step 4c finishes the job one step later. Both are covered here, at the point where the candidate is still on disk.

Read the candidate's row from the record collected in Step 2:

- `risk=landed`, `ok`, or `bare` → proceed.
- `risk=STRANDED`, `UNKNOWN`, or `superseded` → **stop and do not remove.** Present the count, the `base` stamp, the `reason`, and the commit subjects (`git -C <path> log HEAD --not --remotes --oneline`), then get explicit per-worktree confirmation naming those commits. `UNKNOWN` means the engine could not prove landedness, not that it proved absence. `superseded` means only that a MERGED pull request carried this branch's NAME — a name reused after that merge makes the evidence describe different commits than the ones here, and the row is `landed=no` either way. Treat both exactly as `STRANDED`.
- `risk=in-progress` → **stop.** A merge, rebase, cherry-pick, or revert is paused here. Its staged tree is recomputable, but the operator's conflict resolutions are not, and the sequencer state is lost with the directory. Report the operation and let the user finish or abort it first.
- `risk=dirty` → **stop.** Nothing is unpushed, but the working tree carries uncommitted edits — and the same value is emitted when the working-tree status could not be read at all, which is the `-` or `?` you will see in the count columns. Neither is safe to remove without the user looking.
- **Any value not listed above → treat it as `STRANDED`.** The list is closed on the safe side only. A risk value this file does not recognize is a value it cannot vouch for, and the whole point of the record is that an unproven verdict never authorizes a removal.
- When the row's `peers` column names another worktree, say so: those commits survive in the peer, which is a different decision from losing them.
- The override is `--acknowledge-stranded`, per worktree, never a bare `--force`. `--force` answers git's dirty-tree check, which is a different question, and one flag must not silently answer both.

An absent field prints as the literal `-`, never as nothing (a blank would collapse under tab-splitting and shift every later column). Present `-` as "not resolved" rather than verbatim — a `base` of `-` means no base was resolved, which is exactly why the row is `UNKNOWN`.

Offer the non-destructive resolution first — `git -C <path> push -u origin HEAD` makes the commits durable and reclassifies the row as safe without anyone having to judge whether the work matters.

**2. Carried-ignored-file guard:** `git worktree remove`
succeeds on a worktree whose only edits are gitignored files — `status --porcelain` does not show
them, so plain removal silently discards them. When the repo root has a `.worktreeinclude`, run
the same per-pattern comparison as `/source-control:pull-request create`'s pre-flight — expand each pattern from
the worktree toplevel (skip unmatched globs) AND from `MAIN_ROOT` — before removing. Differing or
new carried file → offer the copy-to-main sync; main-side file ABSENT in the worktree → offer
removing main's copy only on explicit confirmation of a deliberate deletion (default keep — the
file may simply never have been carried). Removal without this pass loses the edits with exit 0.

**Escalation guard (before any `--force`):** when the plain removal fails, inspect why — `git -C <path> status --porcelain` (uncommitted edits) and `git -C <path> log HEAD --not --remotes --oneline | head` (unpushed commits). `HEAD`, not `--branches`: on a detached HEAD — the one case where removal makes commits unreachable *immediately*, with no branch ref left holding them — `--branches` reports every other branch in the repository and nothing about this worktree's own commits, so the guard reads clean at exactly the moment it matters most. If either is non-empty, present the summary to the user and get explicit per-worktree confirmation BEFORE forcing — forced removal permanently discards those changes. Only after confirmation (or when the failure is a lock/metadata issue with a verifiably clean tree):

```bash
git worktree remove --force <path> \
  || git worktree remove --force --force <path>   # second --force required for LOCKED worktrees (git-scm)
```

Do NOT swallow stderr with `2>/dev/null` — a failed removal must surface so Step 5 can report it honestly.

### Step 4c: Emit branch + current-worktree deletion for the user (do not run inline)

Branch deletion is destructive (and the consuming project's hooks may block `git branch -D` mid-session), and the worktree a session runs in cannot delete itself — the running Claude Code process holds its directory handle. Surface these for the user to run from a main-repo terminal (or via the `!` prompt prefix) rather than executing them inline:

```bash
# Run from main repo / another terminal:
git branch -D <branch-name>                    # -D needed (squash-merge changes SHA)
git worktree remove <current-worktree-path>    # only if the active worktree was itself a candidate
```

**The stranded-work precondition applies here too, and this is where it bites hardest.** Removal left the branch ref intact; this line is what actually destroys the commits. Emit `git branch -D <branch-name>` only for a branch whose row was `landed` or `ok`. For `STRANDED`, `UNKNOWN`, or `superseded`, emit nothing and say why — a suggested command in a code block reads as vetted, and a user pasting it has no way to know the guard upstream was never applied to it. Emit `git -C <path> push -u origin HEAD` instead.

The branch this deletes may also be checked out by another worktree; `git branch -D` refuses in that case, which is git protecting the peer rather than an error to work around.

Remote branch cleanup is not needed when the repo has `delete_branch_on_merge` enabled (GitHub deletes the remote branch on merge) — check via `gh api repos/{owner}/{repo} --jq .delete_branch_on_merge`; otherwise also emit `git push origin --delete <branch-name>`.

## Step 5: Verify physical deletion, prune, and report

```bash
git worktree prune   # clears admin metadata for working trees now missing
```

`git worktree prune` clears metadata but cannot delete a husk a process still holds, so verify each removed candidate's directory is actually gone:

```bash
test -d <path> && echo "HUSK REMAINS: <path>" || echo "removed: <path>"   # PowerShell: Test-Path <path>
```

Report honestly — never count a husk as removed:

- **Fully removed** — directory gone AND metadata pruned.
- **Unregistered, husk remains** — `git worktree list` is clean but the directory is still on disk (a lock survived Step 4a). Surface the path; the user removes it after closing the holding process.

Report: "Removed N worktrees (M fully deleted, K husks remaining — paths above). Run `/source-control:worktree status` to verify."
