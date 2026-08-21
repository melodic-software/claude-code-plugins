#!/usr/bin/env bash
# Self-contained tests for lib/state-key.sh (no external test lib — ships with the plugin).
#
# The copy in claude-memory is byte-identical and registered in
# scripts/cross-plugin-source-registry.txt, so this suite covers both.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/state-key.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_ne() {
  if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1" "expected difference, both were [$2]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed" >&2
  exit 0
fi

mkrepo() {
  # mkrepo <name> [remote-url] — echo a fresh repo path
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name Test
  if [[ -n "${2:-}" ]]; then
    git -C "$d" remote add origin "$2"
  fi
  printf '%s' "$d"
}

key() { bash "$SCRIPT" --root "$1" 2>/dev/null; }

# --- Case 1: an https remote normalizes to host/owner/repo --------------------
r="$(mkrepo https https://github.com/Melodic-Software/Claude-Code-Plugins.git)"
k="$(key "$r")"
assert_contains "case 1: https remote normalizes" "$k" "github.com/melodic-software/claude-code-plugins/"
assert_not_contains "case 1: .git suffix stripped" "$k" ".git/"

# --- Case 2: the scp-style ssh form keys identically ---------------------------
# The property that matters: one repository, two remote spellings, one key. A
# scheme that keyed them apart would fragment a project's own history.
r2="$(mkrepo ssh git@github.com:Melodic-Software/Claude-Code-Plugins.git)"
k2="$(key "$r2")"
assert_eq "case 2: ssh and https identities agree" \
  "${k%/*}" "${k2%/*}"

# --- Case 3: an upstream-only repo keys by that remote, not the local rung ----
r="$(mkrepo upstream-only)"
git -C "$r" remote add upstream https://gitlab.com/acme/widget.git
k="$(key "$r")"
assert_contains "case 3: first remote is used whatever its name" "$k" "gitlab.com/acme/widget/"
assert_not_contains "case 3: did not fall through to local" "$k" "local/"

# --- Case 4: no remote falls to local/<hash> ----------------------------------
r="$(mkrepo no-remote)"
k="$(key "$r")"
assert_contains "case 4: no remote keys local" "$k" "local/"

# --- Case 5: a non-repo directory keys nonrepo/<hash> -------------------------
d="$TEST_TMPDIR/plain"
mkdir -p "$d"
k="$(key "$d")"
assert_contains "case 5: non-repo keys nonrepo" "$k" "nonrepo/"

# --- Case 6: a traversal remote cannot escape the namespace -------------------
# The security property. A remote URL becomes directory components in the
# caller's path, so `../../../etc` must not survive into the key. It is hashed
# instead — still deterministic, still inside the namespace.
r="$(mkrepo traversal ../../../etc)"
k="$(key "$r")"
assert_not_contains "case 6: no .. in the key" "$k" ".."
assert_contains "case 6: traversal remote is hashed" "$k" "remote/"
k_again="$(key "$r")"
assert_eq "case 6: hashed key is deterministic" "$k" "$k_again"

# --- Case 7: an absolute local remote is hashed, not embedded -----------------
r="$(mkrepo abslocal /var/lib/central.git)"
k="$(key "$r")"
assert_not_contains "case 7: absolute path not embedded" "$k" "var/lib"
assert_contains "case 7: absolute local remote is hashed" "$k" "remote/"

# --- Case 8: a Windows-path remote is hashed ----------------------------------
r="$(mkrepo winpath 'C:\repos\central.git')"
k="$(key "$r")"
# A literal backslash, built without a backslash-bearing literal: shellcheck's
# SC1003 fires on every spelling of one inside quotes, and this assertion is
# precisely about a backslash surviving into a path segment.
backslash=$(printf '%b' '\134')
assert_not_contains "case 8: no backslash in the key" "$k" "$backslash"
assert_contains "case 8: windows-path remote is hashed" "$k" "remote/"

# --- Case 9: two worktrees of one repo differ in the discriminator ------------
# The whole reason the key has a second segment: two checkouts of one repository
# legitimately hold different content and must not share a report.
r="$(mkrepo wt-base https://github.com/acme/widget.git)"
printf 'x\n' >"$r/f.txt"
git -C "$r" add f.txt 2>/dev/null
git -C "$r" commit -qm "seed" 2>/dev/null
wt="$TEST_TMPDIR/wt-second"
git -C "$r" worktree add -q "$wt" -b other 2>/dev/null
ka="$(key "$r")"
kb="$(key "$wt")"
assert_eq "case 9: same repository identity" "${ka%/*}" "${kb%/*}"
assert_ne "case 9: different worktree discriminator" "${ka##*/}" "${kb##*/}"
git -C "$r" worktree remove --force "$wt" 2>/dev/null

# --- Case 10: the key is a plain relative path, never absolute ----------------
# It is concatenated onto ${CLAUDE_PLUGIN_DATA} by the caller, so a leading
# slash would relocate the whole write.
for d in "$TEST_TMPDIR/plain" "$(mkrepo shape https://github.com/acme/widget.git)"; do
  k="$(key "$d")"
  case "$k" in
  /* | *:* | *' '*) fail "case 10: key is a plain relative path" "got [$k]" ;;
  *) pass "case 10: key is a plain relative path ($k)" ;;
  esac
done

# --- Case 11: --explain writes to stderr and leaves stdout clean --------------
r="$(mkrepo explain https://github.com/acme/widget.git)"
out="$(bash "$SCRIPT" --root "$r" --explain 2>/dev/null)"
err="$(bash "$SCRIPT" --root "$r" --explain 2>&1 >/dev/null)"
assert_eq "case 11: stdout is exactly the key" "$out" "$(key "$r")"
assert_contains "case 11: explain names the rung" "$err" "rung:"

# --- Case 12: a bad argument and a missing root both exit 2 -------------------
rc=0
bash "$SCRIPT" --nope >/dev/null 2>&1 || rc=$?
assert_exit "case 12: unknown argument exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --root "$TEST_TMPDIR/does-not-exist" >/dev/null 2>&1 || rc=$?
assert_exit "case 12: missing --root exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --root >/dev/null 2>&1 || rc=$?
assert_exit "case 12: --root with no value exits 2" 2 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
