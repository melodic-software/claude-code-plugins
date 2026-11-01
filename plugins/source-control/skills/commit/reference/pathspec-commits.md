# Pathspec-limited commits (dirty shared index)

The default stays the plain index commit. Use this form **only** when the index verifiably holds
staged files OUTSIDE this commit's scope (concurrent Claude Code sessions on the same branch,
pre-existing mixed WIP), where a bare `git commit` would sweep them all in.

```bash
# Same trailer_policy conditionality as the canonical form in SKILL.md: drop --trailer
# entirely when trailer_policy is "none"; substitute a named alternate template.
git commit -F - --cleanup=verbatim \
  --trailer "<Co-authored-by trailer>" \
  -- <path> [<path>...] <<'EOF'
<subject>

<body>
EOF
```

## Semantics

Per `git-commit(1)`'s default `--only` mode: the commit records the **working-tree content** of the
named paths, disregarding what is staged for all OTHER paths. Concurrent-session staged work stays
staged, untouched. A path with no `HEAD` entry that was never `git add`ed still errors out
(`pathspec '<path>' did not match any file(s) known to git`): pathspec alone never picks up a
genuinely untracked file.

**A path staged as a deletion is a different case, and it fails silently instead of erroring.**
`git rm --cached <path>` removes the path from the index but leaves it on disk, so `git status`
shows it as both `D` (cached) and `??` (untracked). The path still has a `HEAD` entry, so `--only` mode *does* match it,
but it reads the **working-tree content**, not the cached `D` status, finds the file present, and
re-adds it unchanged: the staged deletion is silently discarded.

With the file still on disk, `git commit -- <D-status path> <other paths>` commits that path
unchanged; with the file absent from disk too (a plain `git rm <path>`, or `git rm --cached`
followed by an on-disk `rm`), the same command records the deletion. `--only` mode gives the right
answer only when the worktree already matches the deletion.

## The exec bit does NOT survive this form under `core.filemode=false`

**A path needing the exec-bit fix and the pathspec form are incompatible on a `core.filemode=false`
repository, the default on Windows/NTFS.** This is a hard constraint, not a bug to work around.

`--only` records the named path's **working-tree** content and mode. With `core.filemode=false` git
ignores worktree permission bits, cannot see the `chmod +x`, and rebuilds the entry as `100644`,
discarding the `100755` index entry `git update-index --chmod=+x` set moments earlier.

Measured on a `core.filemode=false` fixture:

| Commit form | Index before | HEAD after |
|---|---|---|
| plain index commit | `100755` | **`100755`**, preserved |
| pathspec `--only` commit | `100755` | **`100644`**, silently lost |

Two workarounds **both failed** on that platform, so neither is offered:
`git -c core.fileMode=true commit -- <path>` still recorded `100644` (Git Bash's `chmod` is
emulated, so the filesystem carries no exec bit for git to read), and a post-commit
`update-index --chmod=+x` followed by `commit --amend --only` regressed the same way.

**So when this commit's paths include a newly-added shebang file the exec-bit check corrected, do
not use the pathspec form for that path.** Options, in order of preference:

1. **Commit the exec-bit path via the plain index form**, which honors the `100755` entry. If the
   index is dirty with another session's work, coordinate: ask before committing, or wait.
2. **Split the commit**: the exec-bit path in a plain commit of its own, the rest by pathspec.
3. If the pathspec form is genuinely unavoidable, **say so and verify after the fact**:
   `git ls-tree HEAD -- <path>` reports the mode recorded. A `100644` there is the regression,
   repaired by a follow-up plain-form commit, not another pathspec commit.

Never assume the mode survived: `git ls-tree HEAD -- <path>` is the only authority on what was
recorded, not the index entry.

## Safety preconditions, all required before offering this path

- Every named path is fully this commit's work, with no overlap with another session's in-flight
  scope (when unsure which session owns a file, ask).
- For each named path, working tree == intended content (pathspec commits the worktree version,
  silently superseding a different staged version of that path), **except** a path staged as `D`
  whose file is still on disk, which needs the hide/commit/restore sequence below instead.
- Verify scope with `git diff --cached --stat -- <pathspec>` and surface that stat in the review
  gate; the user greenlights exactly what the pathspec captures.
- A directory pathspec (`-- path/to/dir/`) is acceptable only after confirming via
  `git status --porcelain -- <dir>` that nothing under it belongs to another scope; otherwise
  enumerate files.

## Preserving a staged deletion in a pathspec commit

For every named path whose `git diff --cached --name-status -- <path>` reports `D`, **or the old
side of an `R` rename** (`R<score> <old> <new>`, the `<old>` field), check whether that path is
still on disk (the `git rm --cached` case above, or a rename whose old pathname was recreated).
`git commit -- dir/` after `git mv dir/old dir/new` with an ignored `dir/old` present records
`M dir/old` plus `A dir/new`, losing the rename's deletion half.

Expand any directory pathspec to its member files first, via
`git diff --cached --name-status -- <dir>`, **not** the `--name-only` expansion the
format-before-push check uses: `--name-only` reports only a rename's new side (`dir/new`), never the
old side (`R100 dir/old dir/new` appears only in `--name-status` output), so a `--name-only`
expansion would silently drop every rename old-side before the loop sees it.

If a path is still present, the default `--only` read silently drops the deletion per Semantics.
Check disk presence directly: an ignored old-side replacement never shows up in
`git status --porcelain`, so the directory-scope check above cannot catch it.

`--only` mode has no flag to commit a path's cached state instead of its worktree state, so make
the worktree briefly match the staged deletion (`D`) or rename (`R` old-side) rather than delete the
file outright: `git rm --cached` means the user wants to stop tracking it while keeping the local
copy, and a rename's old side should not exist there once the commit lands.

Arm the restore trap **before** the hide loop runs: a later path's hide-target collision must still
restore an earlier path's hidden file, so `hidden` and the trap must be live from the first
iteration.

Every probe of a hide path uses `-e ... -o -L ...`, not `-e` alone: if the hidden original was a
symlink with a missing target, `-e` on the moved `.__commit_hide__` path is false (it follows the
link and checks the target), so an `-e`-only test would leave that dangling symlink un-restored on
exit and miss it as a pre-existing collision.

The pre-hide collision check also queries the index (`git ls-files --error-unmatch`), not just the
disk: a hide path that is a tracked file absent from disk or staged for deletion passes a disk-only
check, and the `mv` would land the hidden original on a still-tracked pathname that the same
pathspec commit silently records as a modification.

Build the candidate list with `-z` (NUL-delimited), not plain `--name-status`: a newline-split read
is unsafe for paths with spaces or newlines. A rename's status field carries a variable similarity
score (`R087`, `R100`, …), so match the `R` prefix, not a literal `R100`.

```bash
hidden=()
restore_hidden() {
  for f in "${hidden[@]}"; do
    [ -e "$f.__commit_hide__" -o -L "$f.__commit_hide__" ] && mv -- "$f.__commit_hide__" "$f"
  done
}
trap restore_hidden EXIT

hide_candidates=()
while IFS= read -r -d '' status; do
  case "$status" in
    D)
      IFS= read -r -d '' path
      hide_candidates+=("$path")
      ;;
    R*)
      IFS= read -r -d '' old
      IFS= read -r -d '' _new  # new side isn't this loop's concern, just consume it
      hide_candidates+=("$old")
      ;;
    *)
      IFS= read -r -d '' _path  # A/M/etc. — consume and discard
      ;;
  esac
done < <(git diff --cached --name-status -z -- <path>)

for f in "${hide_candidates[@]}"; do
  [ -e "$f" -o -L "$f" ] || continue  # only disk-present candidates need hiding
  hide="$f.__commit_hide__"
  if [ -e "$hide" -o -L "$hide" ] || git ls-files --error-unmatch -- "$hide" >/dev/null 2>&1; then
    echo "refusing to hide $f: $hide already exists" >&2
    exit 1
  fi
  mv -- "$f" "$hide"
  hidden+=("$f")
done

# Same trailer_policy conditionality as the canonical form: drop --trailer entirely
# when trailer_policy is "none"; substitute a named alternate template.
git commit -F - --cleanup=verbatim \
  --trailer "<Co-authored-by trailer>" \
  -- <path> [<path>...] <<'EOF'
<subject>

<body>
EOF
```

The `trap ... EXIT` restores the file on every exit path (commit success, a rejecting commit-msg
hook, any other error), so the hide never outlives this one commit invocation; after a rejecting
hook the `D` stays staged for a retry.

If a `<path>.__commit_hide__` collision is detected before hiding starts, stop and surface it
instead of overwriting an unrelated file. Do not guess which one the user meant.
