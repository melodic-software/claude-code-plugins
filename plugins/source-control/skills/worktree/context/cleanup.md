# Worktree `cleanup` — full 5-step procedure

Full detail for the `/worktree cleanup [--dry-run]` action. SKILL.md carries the headline plus the safety invariants; this file carries the complete step-by-step (prune → identify → present → execute → verify), including the Windows file-lock handling and the user-emitted branch deletion.

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

Extract actual branch name from porcelain output (`branch refs/heads/<name>`), not from directory name — they may differ if branch was renamed.

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

Skipping 4a is the usual reason a previous `/worktree cleanup` left husks behind — Step 5 then reports them honestly rather than hiding the failure.

### Step 4b: Remove the worktree

```bash
# Orphaned directory (on disk, not in `git worktree list`): remove the husk
rm -rf <path>

# Git-tracked worktree — plain removal first. It FAILS on a dirty worktree
# specifically to prevent data loss; never blind-escalate past that.
git worktree remove <path>
```

**Escalation guard (before any `--force`):** when the plain removal fails, inspect why — `git -C <path> status --porcelain` (uncommitted edits) and `git -C <path> log --branches --not --remotes --oneline | head` (unpushed commits). If either is non-empty, present the summary to the user and get explicit per-worktree confirmation BEFORE forcing — forced removal permanently discards those changes. Only after confirmation (or when the failure is a lock/metadata issue with a verifiably clean tree):

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

Report: "Removed N worktrees (M fully deleted, K husks remaining — paths above). Run `/worktree status` to verify."
