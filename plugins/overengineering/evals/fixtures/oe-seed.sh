#!/usr/bin/env bash
# Seeds the eval workspace from fixture files.
# Usage: oe-seed.sh <branch|--no-git> <token>...
# Tokens: <fixture-file> <dest-path> copies a fixture (stored with a .txt
# suffix so no scanner reads it as source) and stages it unless git ignores it;
# --commit <message> commits what is staged; --detach detaches HEAD.
# Anything still staged at the end is committed. --no-git copies files only.
set -euo pipefail

fixtures="$(dirname "${BASH_SOURCE[0]}")"
branch="$1"
shift
use_git=true
if [[ "$branch" == "--no-git" ]]; then
  use_git=false
else
  git init -q -b "$branch"
  git config user.name eval
  git config user.email eval@example.invalid
fi

commit_staged() {
  if ! git diff --cached --quiet; then
    git commit -q -m "$1"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      commit_staged "$2"
      shift 2
      ;;
    --detach)
      git checkout -q --detach
      shift
      ;;
    *)
      src="$1" dest="$2"
      shift 2
      mkdir -p "$(dirname "$dest")"
      cp "$fixtures/$src" "$dest"
      case "$dest" in
        *.sh | .githooks/*) chmod +x "$dest" ;;
        *) ;;
      esac
      if "$use_git" && ! git check-ignore -q "$dest"; then
        git add "$dest"
      fi
      ;;
  esac
done

if "$use_git"; then
  commit_staged "add fixtures"
fi
