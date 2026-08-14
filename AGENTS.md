# AGENTS.md

Orientation for a coding agent working in this repository. It complements the
repository's own `README.md`: the README is written for people (what the
project is, how to build and run it, who owns it), while this file is the
agent-facing companion. Read the README first for repository shape and the
commands that validate a change.

## Synced standards are overwritten, not edited here

This repository's lint, formatting, and repository-hygiene configuration is
synchronized from `melodic-software/standards`. Any file that standards marks
as `managed` for this repository is replaced on the next sync, so a local edit
to such a file is silently lost. When one of them is wrong, fix the cause
upstream in `melodic-software/standards` and let the sync carry the correction
back — never patch the materialized copy here.

## Stage explicit paths

Stage the specific files a change touches. Never `git add -A` or `git add .`:
a blanket stage can sweep in synced, generated, or unrelated files you did not
mean to commit.

## CI `exec-bit=failure`: set a new script's exec bit in the index

CI's `hygiene` lane fails with `exec-bit=failure` when a tracked file whose
first two bytes are `#!` — any shebang file, not just `.sh` — sits in the git
index at mode `100644`. Fix each file the lane's error annotation names, then
commit the mode change:

```shell
chmod +x -- <path>
git update-index --chmod=+x -- <path>
```

The defect is invisible on Windows, where it is usually introduced: an NTFS
clone gets `core.filemode=false`, so git ignores worktree permission bits —
`chmod +x` alone never reaches the index, every newly added file stages as
`100644`, and `git status` / `git diff` show nothing wrong afterward. The bad
mode first surfaces as the red CI lane; locally it is visible only via
`git ls-files --stage -- <path>`. `git update-index --chmod=+x` writes the
index entry directly and works regardless of `core.filemode`; the `chmod`
keeps the worktree in agreement so a later `git add` cannot revert the entry
where filemode is honored. Committing through the source-control plugin's
commit skill applies this fix automatically
(`plugins/source-control/skills/commit/scripts/exec-bit-check.sh`, reasoning
in [its reference](plugins/source-control/skills/commit/reference/exec-bit.md))
— the trap bites commits made without it.

## Pull requests

- Title pull requests with [Conventional Commits](https://www.conventionalcommits.org/).
- Resolve every review thread before merging; an unresolved thread marks a
  finding that has not yet been addressed.
