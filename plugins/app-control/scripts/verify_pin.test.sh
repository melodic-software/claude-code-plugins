#!/usr/bin/env bash
# Tests for verify_pin.py against throwaway repositories: a folder at its pin passes (with an
# ignored config/local.json, a CRLF working copy and an inside symlink), and each condition of
# control-skill.md "Checkout off the pin" refuses a checkout that breaks only that condition.
# Usage: verify_pin.test.sh [verifier]   (default: the sibling verify_pin.py)
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY="${1:-$SCRIPT_DIR/verify_pin.py}"
FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.name fixture
git config --global user.email fixture@example.invalid
git config --global init.defaultBranch main
git config --global core.autocrlf false

D=.claude/skills/control-id
# The pinned commit: a control skill with a CLI, committed config, an inside symlink, and an
# ignore rule for one person's config/local.json.
BASE="$T/base"
mkdir -p "$BASE/$D/cli" "$BASE/$D/config"
git init -q "$BASE"
printf '# control-id\n' >"$BASE/$D/SKILL.md"
printf 'print("sign-in")\n' >"$BASE/$D/cli/id.py"
printf '{"safety": {}}\n' >"$BASE/$D/config/defaults.json"
printf 'local.json\n' >"$BASE/$D/config/.gitignore"
ln -s ../SKILL.md "$BASE/$D/cli/hub"
printf 'outside\n' >"$BASE/README.md"
git -C "$BASE" add -A
git -C "$BASE" commit -q -m pin
PIN="$(git -C "$BASE" rev-parse HEAD)"

N=0
# clone_case: a fresh clone of BASE at the pin, its path in $C.
clone_case() {
  N=$((N + 1))
  C="$T/case-$N"
  git clone -q "$BASE" "$C"
}
# run <checkout> <sha> [env assignments...]: exit code in $rc, stderr in $err.
run() {
  local checkout="$1" sha="$2"
  shift 2
  rc=0
  env "$@" python3 -I "$VERIFY" "$checkout" id "$sha" 2>"$T/stderr" >/dev/null || rc=$?
  err="$(cat "$T/stderr")"
}
expect_pass() {
  if [[ "$rc" == 0 ]]; then pass "$1"; else fail "$1" "rc=$rc: $err"; fi
}
# expect_refused <name> <reason fragment>: exit 1, the contract's message, and that reason.
expect_refused() {
  if [[ "$rc" == 1 && "$err" == *"pins.id "*": fetch or check out"* && "$err" == *"reason: "*"$2"* ]]; then
    pass "$1"
  else
    fail "$1" "rc=$rc: $err"
  fi
}

# --- passes --------------------------------------------------------------------
clone_case
printf '{"timeouts": {}}\n' >"$C/$D/config/local.json"
printf 'print("sign-in")\r\n' >"$C/$D/cli/id.py"
git -C "$C" update-index -q --refresh
run "$C" "$PIN"
expect_pass "pinned folder with local.json, a CRLF copy and an inside symlink passes"

run "$C" "$PIN" GIT_DIR=/nonexistent GIT_WORK_TREE=/nonexistent
expect_pass "inherited GIT_* variables are scrubbed"

# --- the pin value --------------------------------------------------------------
run "$C" ""
if [[ "$rc" == 1 && "$err" == *"pins.id is unset: commit pins.id, for example through /app-control:map"* ]]; then
  pass "an unset pin says to commit pins.id"
else
  fail "an unset pin says to commit pins.id" "rc=$rc: $err"
fi

run "$C" HEAD
expect_refused "a ref name is not a pin" "not 40 or 64 lowercase hex characters"

run "$C" "${PIN:0:12}"
expect_refused "a short id is not a pin" "not 40 or 64 lowercase hex characters"

run "$C" "0123456789abcdef0123456789abcdef01234567"
expect_refused "a SHA missing from the object store" "the pin is not a commit"

# --- HEAD off the pin, working folder at the pin --------------------------------
clone_case
printf 'print("changed")\n' >"$C/$D/cli/id.py"
git -C "$C" commit -q -am moved
git -C "$C" restore --source="$PIN" --staged --worktree -- "$D"
run "$C" "$PIN"
expect_refused "HEAD that differs from the pin in the folder" "HEAD differs from the pin"

# --- index flags, no content change ---------------------------------------------
clone_case
git -C "$C" update-index --skip-worktree "$D/cli/id.py"
run "$C" "$PIN"
expect_refused "a skip-worktree flag" "index flag S on"

clone_case
git -C "$C" update-index --assume-unchanged "$D/cli/id.py"
run "$C" "$PIN"
expect_refused "an assume-unchanged flag" "index flag h on"

# --- the working folder ---------------------------------------------------------
clone_case
printf 'print("edited")\n' >"$C/$D/cli/id.py"
run "$C" "$PIN"
expect_refused "a working-tree edit" "$D/cli/id.py differs from the pin"

clone_case
printf 'x\n' >"$C/$D/cli/extra.py"
run "$C" "$PIN"
expect_refused "an untracked file" "untracked or ignored $D/cli/extra.py"

clone_case
mkdir -p "$C/$D/node_modules/dep"
printf 'module.exports = 1\n' >"$C/$D/node_modules/dep/index.js"
printf 'node_modules/\n' >>"$C/.git/info/exclude"
run "$C" "$PIN"
expect_refused "an ignored installed dependency" "untracked or ignored $D/node_modules/dep/index.js"

clone_case
rm "$C/$D/cli/id.py"
mkdir "$C/$D/cli/id.py"
run "$C" "$PIN"
expect_refused "a tracked file replaced by an empty directory" "missing $D/cli/id.py"

clone_case
printf '* filter=clean-me\n' >"$C/.git/info/attributes"
run "$C" "$PIN"
expect_refused "a filter attribute" "has a filter attribute"

# --- replace refs ---------------------------------------------------------------
clone_case
printf 'print("swapped")\n' >"$C/$D/cli/id.py"
git -C "$C" commit -q -am swapped
git -C "$C" replace "$PIN" HEAD
run "$C" "$PIN"
expect_refused "a replace ref standing in for the pin" "HEAD differs from the pin"

# --- symlinks out of the folder -------------------------------------------------
clone_case
ln -s ../../../../README.md "$C/$D/cli/readme"
git -C "$C" add -A
git -C "$C" commit -q -m link-out
run "$C" "$(git -C "$C" rev-parse HEAD)"
expect_refused "a pinned symlink that leaves the folder" "symlink $D/cli/readme resolves outside the folder"

clone_case
mv "$C/.claude/skills/control-id" "$T/moved"
ln -s "$T/moved" "$C/.claude/skills/control-id"
run "$C" "$PIN"
expect_refused "a folder path through a symlink" "passes through a symlink"

if ((FAILED)); then
  printf '%d failed\n' "$FAILED" >&2
  exit 1
fi
printf 'all passed\n'
