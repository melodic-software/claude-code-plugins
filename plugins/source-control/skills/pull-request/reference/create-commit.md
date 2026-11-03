# 2.3 Stage and commit

Part of [Phase 2: Create](create.md), which lists every section's file; a bare § number names a section listed there.

## 2.3.1 Unrelated uncommitted changes check (MANDATORY)

Before staging, run `git status --porcelain` and classify every modified/untracked file as **PR-related** or **unrelated**: files that don't belong in this PR, such as pre-existing edits from other sessions, hook auto-fixes, exploratory changes, or work from a different task.

**Why this matters:** the branch is deleted after merge, and its uncommitted changes are lost; `git reflog` recovers only commits. `git stash` survives branch deletion (stashes live in `.git/refs/stash`, not on branches), but only if created before checkout/deletion.

**If unrelated uncommitted changes exist**, present them and offer options:

| Option | When to use | Command |
|--------|-------------|---------|
| **Include in PR** | Changes are small, related enough, and won't pollute the PR | Stage them with the PR files |
| **Stash** | Changes should be preserved but don't belong in this PR | `git stash push -u -m "unrelated: <description>" -- <files>` |
| **Separate commit** | Changes are valuable and self-contained. Commit on this branch as a separate commit (squash merge collapses anyway) | `git add <files> && git commit -m "chore: <description>"` |
| **Discard** | Changes are throwaway (build artifacts, experimental edits) | `git checkout -- <files>` |

**Default recommendation:** stash with a descriptive message, using `-u` to include untracked files; without it, `git stash push -- <files>` silently skips them (`pathspec did not match`). Stashes persist across branch switches and deletion, `git stash list` shows them from any branch, and the user can `git stash pop` on the new branch.

**Never silently ignore uncommitted changes.** Include them, stash them, or get explicit user confirmation to discard.

## 2.3.2 Stage and commit PR changes

Stage specific files (never `git add -A`), then invoke `/source-control:commit` via the Skill tool (this plugin's sibling skill) for the commit. It owns message drafting, the Conventional Commits regex pre-check, the `Co-authored-by` trailer, and the canonical bash heredoc form. **Wait for user approval on the proposed commit message inside `/source-control:commit`.** Do NOT bypass it by running `git commit` directly from this phase: the heredoc, trailer and pre-check live there.

**When NOT to delegate:** if `/source-control:commit` is unavailable (e.g. skill discovery broken), inline the same heredoc form (`git commit -F - --cleanup=verbatim <<'EOF' ... EOF`), proceed, and note the fallback to the user.

## 2.3.3 Changelog fragments for the whole branch

Only in a repository with a `fragment-plugins.txt` list in its `scripts/` directory; elsewhere skip this step, and the repository's own release record (a version bump plus CHANGELOG entry) applies. `/source-control:commit` writes a fragment per commit, but a branch can carry commits made outside it. After the last commit and before the push, run the script against the default branch with the drafted PR title ([§2.4.1](create-push-and-body.md)) as the message:

```bash
printf '%s\n' "<PR title>" | bash "<plugin-root>/scripts/write-changelog-fragments.sh" --base "origin/<default-branch>"
```

It writes a fragment, with the bump and section the title's Conventional Commits type maps to, only for a listed plugin the branch changes and that has no fragment from this branch yet; a plugin the list does not name keeps the per-PR bump. When it prints paths, stage them and commit through `/source-control:commit` (a `chore` subject naming the fragments). On exit 2 for a title it cannot map, rerun with `--level major|minor|patch|none`.
