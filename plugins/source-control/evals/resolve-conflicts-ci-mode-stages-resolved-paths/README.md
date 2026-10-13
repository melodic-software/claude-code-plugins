# resolve-conflicts-ci-mode-stages-resolved-paths

`graders/no-unmerged-path.md` reads the binary `.git/index` the run leaves behind. Each index
entry stores two flag bytes before its path: the stage in the high nibble and the path length in
the low byte. Stage 1, 2 or 3 (`\x10`, `\x20`, `\x30`) followed by the path's length (`\x0d` for
`docs/retry.md`, `\x11` for `src/http/retry.ts`) is an unmerged entry; `git add` leaves only the
stage-0 entry. The pattern assumes index version 2 or 3, which git writes unless `index.version`
or `feature.manyFiles` is set.

Gap: no grader checks for an edit made after the last `git add`. The index alone cannot show one,
it needs the working tree compared against it, and the eval sandbox runs no git hooks that could
record that comparison. The content graders (`no-markers-*`, `both-sides-*`) read the working
tree, so a run that edits after staging can pass them while the merge the runner commits omits
that edit.
