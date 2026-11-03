# 2.1 Pre-flight

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

1. **Prep completed?** Prep writes no state file; its outputs (verified findings + clean verify-gate results) live in conversation context. If neither ran this session, suggest `/source-control:pull-request prep` first; `full` runs prep before this phase. Skip the review prompt for docs-only PRs (Phase 1.1 skips review/simplify); `ready` still reviews an instruction-surface diff ([definition](ready-for-review.md#docs-only-and-instruction-surfaces)).
2. **Changes exist?** `git status --porcelain` must show changes or commits ahead of remote.
3. **Not on the default branch?** If on it, suggest a branch/worktree.
4. **Branch naming?** If the branch name doesn't fit the project's convention (common default: `<type>/<kebab-description>`; Claude Code's auto-created worktree branches may be named `worktree-*`), rename before push: `git branch -m <old> <type>/<description>`. Derive `<type>` from commit content (feat/fix/chore/etc.) and `<description>` from the commit subject. With no commits yet (empty branch), prompt the user for a branch name; there is nothing to derive from. Present the rename for awareness, not approval.
5. **Worktreeinclude file sync?** In a worktree, check for modified gitignored files that won't survive worktree removal: files copied at worktree creation via `.worktreeinclude`, whose session changes exist only in the worktree and are lost on cleanup.

   **Detection:**

   ```bash
   # Am I in a worktree?
   GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
   GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
   if [[ "$GIT_COMMON" != "$GIT_DIR" ]]; then
     # .worktreeinclude lives at the repo root and its globs are root-relative —
     # run from the worktree toplevel, not wherever the session happens to be.
     cd "$(git rev-parse --show-toplevel)" || return
     MAIN_ROOT=$(git worktree list | head -1 | awk '{print $1}')
     # Read .worktreeinclude patterns (one per line, .gitignore syntax)
     while IFS= read -r pattern; do
       [[ -z "$pattern" || "$pattern" == \#* ]] && continue
       # Worktree side: modified or new files. An unmatched glob stays
       # literal — skip it (no phantom CHANGED for absent files).
       for f in $pattern; do
         [[ -f "$f" ]] || continue
         if [[ -f "$MAIN_ROOT/$f" ]]; then
           diff -q "$f" "$MAIN_ROOT/$f" >/dev/null 2>&1 || echo "CHANGED: $f"
         else
           echo "CHANGED (new): $f"
         fi
       done
       # Main side: a carried file deleted in the worktree no longer expands
       # locally — expand from MAIN_ROOT too. ABSENT is ambiguous: the file may
       # have been deleted here, or never copied at all (manual `git worktree
       # add`, or a worktree created before .worktreeinclude existed).
       for m in "$MAIN_ROOT"/$pattern; do
         [[ -f "$m" ]] || continue
         f="${m#"$MAIN_ROOT"/}"
         [[ -f "$f" ]] || echo "ABSENT here (deleted, or never carried): $f"
       done
     done < .worktreeinclude
   fi
   ```

   **If differences found:**

   1. Show diff for each changed file (`diff --unified "$MAIN_ROOT/$f" "$f"`; for a `(new)` file
      diff against `/dev/null`, since main has no copy yet; for an `ABSENT` file show main's copy)
   2. Show active worktrees (`git worktree list`). If >1 worktree exists beyond main, warn: *"Other active worktrees have their own copies of this file. Overwriting main's copy won't affect existing worktrees but will affect future ones."*
   3. Present options per file:
      - **Copy to main:** overwrite main's copy with worktree's version. Safe for cosmetic changes (reordering), new additions, or when this is the only active session
      - **Skip:** proceed without syncing. User accepts that worktree changes will be lost on cleanup
      - For an `ABSENT` file only: **Remove from main**, offered only if the user confirms the file was deliberately deleted in this worktree this session. ABSENT is ambiguous (a manual or pre-`.worktreeinclude` worktree never received the copy), so default to **Skip**; never remove main's copy without that explicit confirmation
   4. If user chooses "copy to main": `mkdir -p "$(dirname "$MAIN_ROOT/$f")" && cp "$f" "$MAIN_ROOT/$f"` (a new topic slug has no parent directory in main yet); confirmed deliberate deletion: `rm "$MAIN_ROOT/$f"`

   **Why here (not WorktreeRemove hook):** this is the last checkpoint where the user is engaged and can inspect a diff. A WorktreeRemove hook cannot prompt, and this plugin's (`hooks/worktree-remove-gate.sh`) compares no carried file. A silent copy could overwrite concurrent session changes. One mechanism per concern.

   **Skip conditions:** not in a worktree, no `.worktreeinclude` file exists, no differences found.
