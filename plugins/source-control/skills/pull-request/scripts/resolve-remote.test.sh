#!/usr/bin/env bash
# Tests for resolve-remote.sh.
# Each case builds a throwaway git repo with a specific remote/branch-config
# shape, then asserts the resolver's stdout and exit code. Non-zero exit on
# any FAIL.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="${SCRIPT_DIR}/resolve-remote.sh"

if [[ ! -x "$RESOLVER" ]]; then
  echo "FAIL: resolver missing or not executable: $RESOLVER" >&2
  exit 1
fi

PASS=0
FAIL=0
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Builds a fresh repo under $WORKDIR/$1 with a `main` branch, then adds each
# remaining arg as a bare remote (name=url pairs, url reused as a throwaway
# local path — never fetched).
make_repo() {
  local name="$1"
  shift
  local repo="$WORKDIR/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  git -C "$repo" commit -q --allow-empty -m "init"
  for pair in "$@"; do
    git -C "$repo" remote add "${pair%%=*}" "${pair#*=}"
  done
  echo "$repo"
}

run_test() {
  local desc="$1" repo="$2" branch="$3" expected_out="$4" expected_exit="$5"
  local actual_out actual_exit
  actual_out=$(cd "$repo" && bash "$RESOLVER" "$branch" 2>/dev/null)
  actual_exit=$?
  if [[ "$actual_out" == "$expected_out" && "$actual_exit" -eq "$expected_exit" ]]; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc"
    echo "       got     out='$actual_out' exit=$actual_exit"
    echo "       wanted  out='$expected_out' exit=$expected_exit"
    FAIL=$((FAIL + 1))
  fi
}

# origin present, no branch.<name>.remote configured -> origin.
repo=$(make_repo "origin-only" origin=/dev/null)
run_test "sole origin remote resolves to origin" "$repo" "main" "origin" 0

# origin + a second remote, no branch.<name>.remote -> origin still wins.
repo=$(make_repo "origin-plus-fork" origin=/dev/null fork=/dev/null)
run_test "origin wins over other remotes when unconfigured" "$repo" "main" "origin" 0

# branch.<name>.remote explicitly set -> that value wins even over origin.
repo=$(make_repo "explicit-branch-remote" origin=/dev/null fork=/dev/null)
git -C "$repo" config branch.main.remote fork
run_test "branch.<name>.remote overrides origin" "$repo" "main" "fork" 0

# branch.<name>.remote = "." (local-only upstream) is treated as unset.
repo=$(make_repo "dot-remote" origin=/dev/null)
git -C "$repo" config branch.main.remote .
run_test "branch.<name>.remote=. falls through to origin" "$repo" "main" "origin" 0

# No origin, exactly one other remote -> sole-remote fallback (finding 1 case b).
repo=$(make_repo "vendor-clone" vendor=/dev/null)
run_test "sole non-origin remote resolves (vendor clone)" "$repo" "main" "vendor" 0

# No origin, 2+ other remotes, no branch.<name>.remote -> fail loudly, not head -1
# (finding 1 case a: fork + upstream, no origin).
repo=$(make_repo "fork-upstream-no-origin" fork=/dev/null upstream=/dev/null)
run_test "multiple non-origin remotes with no origin fails loudly" "$repo" "main" "" 1

# No remotes at all -> fail loudly.
repo=$(make_repo "no-remotes")
run_test "no remotes configured fails loudly" "$repo" "main" "" 1

echo
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
