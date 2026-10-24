#!/usr/bin/env bash
# The commit refs/heads/guardrails-release moves to: the branch consumers' lefthook remotes fetch
# the guardrails git hooks from (plugins/guardrails/git-hooks/entries.json `remote.ref`), so it
# holds only commits on main.
#
#   move.sh <main-sha> [<target>] [<current>]
#
# <target> defaults to the newest commit at or below <main-sha> that changed the `version` in
# plugins/guardrails/.claude-plugin/plugin.json; a given one must be <main-sha> or below it.
# <current> is the branch's tip, empty when it does not exist yet. Prints `action=create`,
# `action=push` or `action=unchanged`, then `sha=<target>`, for $GITHUB_OUTPUT.
#
# Exit 0 decided; 1 refused (a target not on main, no version change found, or a move that is not
# a fast-forward of <current>); 2 usage.
set -uo pipefail

MANIFEST=plugins/guardrails/.claude-plugin/plugin.json

[[ $# -ge 1 && $# -le 3 && -n "$1" ]] || {
  echo "usage: move.sh <main-sha> [<target>] [<current>]" >&2
  exit 2
}
main="$(git rev-parse --verify --quiet "$1^{commit}")" || {
  echo "move.sh: $1 is not a commit" >&2
  exit 2
}

version() { # <commit> -> the manifest's version there, empty when absent
  git show "$1:$MANIFEST" 2>/dev/null | jq -r '.version // empty' 2>/dev/null
}

target=""
if [[ -n "${2:-}" ]]; then
  target="$(git rev-parse --verify --quiet "$2^{commit}")" || {
    echo "move.sh: $2 is not a commit" >&2
    exit 1
  }
  if ! git merge-base --is-ancestor "$target" "$main"; then
    echo "move.sh: $target is not on main ($main)" >&2
    exit 1
  fi
else
  while read -r c; do
    if [[ -n "$(version "$c")" && "$(version "$c")" != "$(version "$c^")" ]]; then
      target="$c"
      break
    fi
  done < <(git log --format=%H "$main" -- "$MANIFEST")
  [[ -n "$target" ]] || {
    echo "move.sh: no commit at or below $main changes the guardrails version" >&2
    exit 1
  }
fi

current="${3:-}"
if [[ -z "$current" ]]; then
  echo "action=create"
elif [[ "$(git rev-parse --verify --quiet "$current^{commit}")" == "$target" ]]; then
  echo "action=unchanged"
elif git merge-base --is-ancestor "$current" "$target" 2>/dev/null; then
  echo "action=push"
else
  echo "move.sh: guardrails-release ($current) is not an ancestor of $target; refusing a move that is not a fast-forward" >&2
  exit 1
fi
echo "sha=$target"
