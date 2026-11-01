# Why each staging precondition exists

The hub's step 2 carries the rule and detection command for each of the four conditions. This file
carries the reasoning: what goes wrong when a blanket `git add <path>` runs over a path in that
state. Read it when a precondition fires and the right action is not obvious, or when deciding
whether a new condition belongs in the set.

Each condition is a state `git add` silently *overwrites* rather than errors on, and in three of the
four the usual detection command (`git diff --stat`) reads empty, so the first check you would reach
for misses it.

## Already-staged deletion (`D`)

`git diff --cached --name-status -- <path>` reports `D`, for example from a prior
`git rm --cached <path>`, which stages the deletion while leaving the file on disk ("stop tracking
it, keep my local copy").

The file stays in the worktree, so `git diff --stat -- <path>` reads **empty** and does not flag a
partial-staging split. A blanket `git add <path>` then re-adds the file and silently clears the
intended deletion, with no error.

Skip any path already staged as `D` entirely; never `git add` over it.

## Staged rename, old side (`R`)

`git diff --cached --name-status -- <path>` reports an `R<score> <old> <new>` entry whose `<old>`
falls under `<path>`, including when `<path>` is a **directory** containing that old pathname.

A staged rename can leave an untracked replacement file at the old pathname. `git diff` never
reports untracked files, so `git diff --stat -- <path>` misses it, and it slips past both the
deletion check above and the partial-staging-split check below. A blanket `git add <path>` (or
`git add <dir>`) then stages the replacement as a new add, turning the rename into an
add-plus-modify.

Skip the old side of any staged `R` entry entirely; never `git add` over it.

## Untracked files under a directory path

When `<path>` is a directory, neither `git diff --cached --name-status -- <path>` nor
`git diff --stat -- <path>` reports untracked files under it: `git diff` compares only
tracked/staged content.

A blanket `git add <path>` on a directory stages every untracked file under it too, sweeping in
secrets, build artifacts, or other new files the user never approved: the harm the `git add -A`
prohibition prevents, reached by a narrower-looking command.

Check `git status --porcelain -- <path>` for `??` entries before staging a directory path; if any
exist, stop and surface them rather than blanket-adding, and enumerate the intended files instead.

## Partial-staging split

`git diff --cached --stat -- <path>` non-empty **and** `git diff --stat -- <path>` also non-empty.

The path has hunks the user deliberately left unstaged, typically from `git add -p`. A blanket add
sweeps them into the commit, discarding the user's explicit decision.

Leave the path as-is rather than running `git add <path>` over it.

## Interaction with the format-before-push check

The same state constrains step 3: a formatter run over a partially-staged file mixes its edits into
the worktree copy the user only partially wants staged, so the re-stage after formatting cannot be a
blanket `git add`. Take that snapshot **before** the formatter runs.
See [format-check.md](format-check.md), "Preserve partial staged selections when re-staging".
