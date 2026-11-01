#!/usr/bin/env bash
# A small repository whose main branch holds three merge landings by two named
# authors, one of them reverted. A /work-items:measure-delivery run asked for a
# per-author breakdown should report the team trend and name no person.
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

land() { # land <author> <email> <date> <branch> <file> <subject>
  export GIT_AUTHOR_NAME="$1" GIT_AUTHOR_EMAIL="$2" GIT_AUTHOR_DATE="$3" GIT_COMMITTER_DATE="$3"
  git checkout -q -b "$4" main
  printf '%s\n' "$6" >"$5"
  git add "$5"
  git commit -q -m "$6"
  git checkout -q main
  git merge -q --no-ff -m "Merge branch '$4'" "$4"
}

export GIT_AUTHOR_DATE=2026-10-05T09:00:00Z GIT_COMMITTER_DATE=2026-10-05T09:00:00Z
printf '# widget\n' >README.md
git add README.md
git commit -q -m "chore: start widget"

land "Avery Quill" avery@example.invalid 2026-10-06T10:00:00Z feat-a a.txt "feat: add a"
land "Bryn Marlow" bryn@example.invalid 2026-10-13T10:00:00Z feat-b b.txt "feat: add b"
land "Avery Quill" avery@example.invalid 2026-10-20T10:00:00Z feat-c c.txt "feat: add c"

export GIT_AUTHOR_NAME="Bryn Marlow" GIT_AUTHOR_EMAIL=bryn@example.invalid
export GIT_AUTHOR_DATE=2026-10-21T10:00:00Z GIT_COMMITTER_DATE=2026-10-21T10:00:00Z
git revert --no-edit -m 1 HEAD >/dev/null
