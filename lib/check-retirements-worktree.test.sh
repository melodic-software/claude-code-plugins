#!/usr/bin/env bash
# Tests for lib/check-retirements.sh run from a linked worktree: a `.git/`
# record path names git's own files, which a linked worktree keeps in the main
# checkout's git directory, so detection and cleanup find them there.
# Run directly: bash lib/check-retirements-worktree.test.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-retirements.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
export GIT_CONFIG_GLOBAL="$TEST_TMPDIR/no-global" GIT_CONFIG_NOSYSTEM=1

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

MAIN="$TEST_TMPDIR/main"
LINKED="$TEST_TMPDIR/linked"
git init -q -b main "$MAIN"
git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m seed
git -C "$MAIN" worktree add -q --detach "$LINKED"

MANIFEST="$TEST_TMPDIR/retirements.yaml"
printf '%s\n' \
  'id: t-r001' 'retired: 2026-01-01' 'plugin_version: 1.0.0' 'kind: file' \
  'path: .git/hooks/old-hook' "content_match: 'old-marker'" 'action: delete' 'note: "old hook"' \
  '---' \
  'id: t-r002' 'retired: 2026-01-01' 'plugin_version: 1.0.0' 'kind: dir' \
  'path: .git/hooks/old-lib' 'action: delete' 'note: "old lib"' >"$MANIFEST"

run() { # [args...] -> "<rc>|<stdout>"
  local out rc
  out="$(bash "$SCRIPT" --manifest "$MANIFEST" "$@" 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$out"
}

expect "nothing present passes from the linked worktree" "0|" "$(run --root "$LINKED")"

printf '#!/bin/sh\n# old-marker\n' >"$MAIN/.git/hooks/old-hook"
mkdir -p "$MAIN/.git/hooks/old-lib"
expect "the linked worktree finds leftovers in the common git dir" \
  "1|t-r001	file	.git/hooks/old-hook	delete	active	old hook
t-r002	dir	.git/hooks/old-lib	delete	active	old lib" "$(run --root "$LINKED")"
expect "the main checkout finds the same leftovers" 1 "$(r="$(run --root "$MAIN")" && printf '%s' "${r%%|*}")"

expect "a clean from the linked worktree removes the file" "0|" "$(run --root "$LINKED" --clean t-r001)"
expect "the file is gone from the common git dir" no "$(test -e "$MAIN/.git/hooks/old-hook" && echo yes || echo no)"
expect "a clean from the linked worktree removes the directory" "0|" "$(run --root "$LINKED" --clean t-r002)"
expect "the directory is gone from the common git dir" no "$(test -e "$MAIN/.git/hooks/old-lib" && echo yes || echo no)"
expect "the hooks directory itself stays" yes "$(test -d "$MAIN/.git/hooks" && echo yes || echo no)"

echo "check-retirements-worktree: $PASS passed, $FAIL failed"
((FAIL == 0))
