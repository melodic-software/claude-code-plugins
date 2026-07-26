# Staging preconditions — why each one exists

The hub's step 2 carries the rule and the detection command for each of the four conditions. This
file carries the reasoning: what specifically goes wrong when a blanket `git add <path>` runs over a
path already in that state. Read it when a precondition fires and the right action is not obvious,
or when deciding whether a new condition belongs in the set.

The common shape: each condition is a state `git add` silently *overwrites* rather than errors on,
and in three of the four the usual detection command (`git diff --stat`) reads empty, so the
condition is invisible to the check you would reach for first.

## Already-staged deletion (`D`)

`git diff --cached --name-status -- <path>` reports `D` — e.g. from a prior `git rm --cached <path>`,
which stages the deletion while deliberately leaving the file on disk ("stop tracking it, keep my
local copy").

A deletion staged this way leaves a file present in the worktree, untracked or otherwise, so
`git diff --stat -- <path>` reads **empty** and would not flag it as a partial-staging split. A
blanket `git add <path>` then re-adds the file and silently clears the intended deletion. Nothing
errors; the deletion simply does not happen.

Skip any path already staged as `D` entirely; never `git add` over it.

## Staged rename, old side (`R`)

`git diff --cached --name-status -- <path>` reports an `R<score> <old> <new>` entry whose `<old>`
falls under `<path>` — including when `<path>` is a **directory** containing that old pathname.

A staged rename can leave an untracked replacement file sitting at the old pathname. That
replacement is invisible to `git diff --stat -- <path>`, because untracked files are never reported
by `git diff` at all, so it slips past both the deletion check above and the partial-staging-split
check below. A blanket `git add <path>` (or `git add <dir>`) then stages that replacement as a new
add, turning the intended rename into an add-plus-modify.

Skip the old side of any staged `R` entry entirely; never `git add` over it.

## Untracked files under a directory path

When `<path>` is a directory, neither `git diff --cached --name-status -- <path>` nor
`git diff --stat -- <path>` reports untracked files sitting under it — `git diff` only ever compares
tracked/staged content.

A blanket `git add <path>` on a directory stages every untracked file underneath it too, sweeping in
secrets, build artifacts, or other unrelated new files the user never approved. This is the same
class of harm the `git add -A` prohibition exists to prevent, reached by a narrower-looking command.

Check `git status --porcelain -- <path>` for `??` entries before staging a directory path; if any
exist, stop and surface them rather than blanket-adding — enumerate the specific intended files
instead.

## Partial-staging split

`git diff --cached --stat -- <path>` non-empty **and** `git diff --stat -- <path>` also non-empty.

A path in that state has hunks the user deliberately left unstaged — typically from an interactive
`git add -p` selection. A blanket add sweeps those unstaged hunks into the commit, discarding a
decision the user made explicitly.

Leave the path as-is rather than running `git add <path>` over it.

## Interaction with the format-before-push check

The same partial-split state also constrains step 3: a formatter run over a partially-staged file
mixes its edits into the worktree copy the user only partially wants staged, so the re-stage after
formatting cannot be a blanket `git add`. That snapshot must be taken **before** the formatter runs
— see [format-check.md](format-check.md), "Preserve partial staged selections when re-staging".
