#!/usr/bin/env bash
# Tests for move.sh on a throwaway repository whose history bumps the guardrails version once,
# edits the manifest without a bump, and adds an unrelated commit: the default target is the
# bump, a fast-forward pushes, the current tip is unchanged, a first run creates the branch, and a
# target off main, a branch that is not an ancestor and a history with no bump are refused.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOVE="$SCRIPT_DIR/move.sh"

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

R="$TMP/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
M="$R/plugins/guardrails/.claude-plugin/plugin.json"
mkdir -p "$(dirname "$M")"
commit() { # <message>
  git -C "$R" add -A
  git -C "$R" commit -q -m "$1"
  git -C "$R" rev-parse HEAD
}
printf '{"name":"guardrails","version":"1.0.0"}\n' >"$M"
v1="$(commit v1)"
printf '{"name":"guardrails","version":"1.1.0"}\n' >"$M"
v2="$(commit v2)"
printf '{"name":"guardrails","description":"x","version":"1.1.0"}\n' >"$M"
edit="$(commit "manifest edit, no bump")"
echo x >"$R/other.txt"
head="$(commit unrelated)"
git -C "$R" switch -q -c side "$v1"
echo y >"$R/side.txt"
side="$(commit side)"
git -C "$R" switch -q main

run() { # <args...> -> "<rc>|<stdout joined by space>"
  local out rc
  out="$(cd "$R" && bash "$MOVE" "$@" 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$(xargs <<<"$out")"
}

expect "the default target is the newest version change, past a manifest edit and an unrelated commit" \
  "0|action=push sha=$v2" "$(run "$head" "" "$v1")"
expect "no branch yet: create it at the version change" "0|action=create sha=$v2" "$(run "$head")"
expect "the branch already at the target is unchanged" "0|action=unchanged sha=$v2" "$(run "$head" "" "$v2")"
expect "a given target on main is used" "0|action=push sha=$edit" "$(run "$head" "$edit" "$v2")"
expect "a target off main is refused" "1|" "$(run "$head" "$side" "$v1")"
expect "a move that is not a fast-forward is refused" "1|" "$(run "$head" "" "$side")"
expect "moving back to an older commit is refused" "1|" "$(run "$head" "$v1" "$v2")"
expect "an unknown current tip is refused" "1|" "$(run "$head" "" 0123456789012345678901234567890123456789)"
git -C "$R" switch -q --orphan bare
echo z >"$R/z.txt"
nobump="$(commit "no manifest")"
expect "a history with no version change is refused" "1|" "$(run "$nobump")"
expect "no main commit is a usage error" "2|" "$(run)"

echo "guardrails-release-ref: $PASS passed, $FAIL failed"
((FAIL == 0))
