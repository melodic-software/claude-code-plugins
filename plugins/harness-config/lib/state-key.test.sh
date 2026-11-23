#!/usr/bin/env bash
# Every plugin copy is generated from the canonical lib/state-key.sh, registered in
# scripts/shared-copies.txt and pinned by scripts/sync-shared-copies.sh --check, so
# this suite covers them all.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/state-key.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_ne() {
  if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1" "expected difference, both were [$2]"; fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed" >&2
  exit 0
fi

mkrepo() {
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

r="$(mkrepo https https://github.com/Melodic-Software/Claude-Code-Plugins.git)"
k="$(key "$r")"
assert_contains "case 1: https remote normalizes" "$k" "github.com/melodic-software/claude-code-plugins/"
assert_not_contains "case 1: .git suffix stripped" "$k" ".git/"

r2="$(mkrepo ssh git@github.com:Melodic-Software/Claude-Code-Plugins.git)"
k2="$(key "$r2")"
assert_eq "case 2: ssh and https identities agree" \
  "${k%/*}" "${k2%/*}"

r="$(mkrepo upstream-only)"
git -C "$r" remote add upstream https://gitlab.com/acme/widget.git
k="$(key "$r")"
assert_contains "case 3: first remote is used whatever its name" "$k" "gitlab.com/acme/widget/"
assert_not_contains "case 3: did not fall through to local" "$k" "local/"

r="$(mkrepo no-remote)"
k="$(key "$r")"
assert_contains "case 4: no remote keys local" "$k" "local/"

d="$TEST_TMPDIR/plain"
mkdir -p "$d"
k="$(key "$d")"
assert_contains "case 5: non-repo keys nonrepo" "$k" "nonrepo/"

real="$TEST_TMPDIR/real/notes"
mkdir -p "$real" "$TEST_TMPDIR/via"
if ln -s "$TEST_TMPDIR/real" "$TEST_TMPDIR/via/projects-link" 2>/dev/null; then
  k_real="$(key "$real")"
  k_link="$(key "$TEST_TMPDIR/via/projects-link/notes")"
  assert_eq "case 5b: symlinked and real --root spellings agree" "$k_real" "$k_link"
  k_cwd="$(cd "$TEST_TMPDIR/via/projects-link/notes" && bash "$SCRIPT" 2>/dev/null)"
  assert_eq "case 5b: the no-arg form from the symlink spelling agrees" "$k_real" "$k_cwd"
else
  pass "case 5b: skipped, this host cannot create a symlink"
fi

r="$(mkrepo traversal ../../../etc)"
k="$(key "$r")"
assert_not_contains "case 6: no .. in the key" "$k" ".."
assert_contains "case 6: traversal remote is hashed" "$k" "remote/"
k_again="$(key "$r")"
assert_eq "case 6: hashed key is deterministic" "$k" "$k_again"

r="$(mkrepo abslocal /var/lib/central.git)"
k="$(key "$r")"
assert_not_contains "case 7: absolute path not embedded" "$k" "var/lib"
assert_contains "case 7: absolute local remote is hashed" "$k" "remote/"

r="$(mkrepo winpath 'C:\repos\{central}.git')"
k="$(key "$r")"
# A literal backslash, built without a backslash-bearing literal: shellcheck's
# SC1003 fires on every spelling of one inside quotes, and this assertion is
# precisely about a backslash surviving into a path segment.
backslash=$(printf '%b' '\134')
assert_not_contains "case 8: no backslash in the key" "$k" "$backslash"
assert_contains "case 8: windows-path remote is hashed" "$k" "remote/"

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

for d in "$TEST_TMPDIR/plain" "$(mkrepo shape https://github.com/acme/widget.git)"; do
  k="$(key "$d")"
  case "$k" in
  /* | *:* | *' '*) fail "case 10: key is a plain relative path" "got [$k]" ;;
  *) pass "case 10: key is a plain relative path ($k)" ;;
  esac
done

r="$(mkrepo explain https://github.com/acme/widget.git)"
out="$(bash "$SCRIPT" --root "$r" --explain 2>/dev/null)"
err="$(bash "$SCRIPT" --root "$r" --explain 2>&1 >/dev/null)"
assert_eq "case 11: stdout is exactly the key" "$out" "$(key "$r")"
assert_contains "case 11: explain names the rung" "$err" "rung:"

rc=0
bash "$SCRIPT" --nope >/dev/null 2>&1 || rc=$?
assert_exit "case 12: unknown argument exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --root "$TEST_TMPDIR/does-not-exist" >/dev/null 2>&1 || rc=$?
assert_exit "case 12: missing --root exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --root >/dev/null 2>&1 || rc=$?
assert_exit "case 12: --root with no value exits 2" 2 "$rc"

real_bash=$(command -v bash)
nohash="$TEST_TMPDIR/nohash-bin"
mkdir -p "$nohash"
for cmd in git tr head sed grep cut; do
  src=$(command -v "$cmd") || continue
  ln -s "$src" "$nohash/$cmd"
done
r="$(mkrepo no-hash-tools)"
rc=0
PATH="$nohash" "$real_bash" "$SCRIPT" --root "$r" \
  >"$TEST_TMPDIR/nohash.out" 2>"$TEST_TMPDIR/nohash.err" || rc=$?
err=$(cat "$TEST_TMPDIR/nohash.err")
assert_exit "case 13: missing hash tool exits 2" 2 "$rc"
if [[ ! -s "$TEST_TMPDIR/nohash.out" ]]; then
  pass "case 13: prints no key"
else
  fail "case 13: prints no key" "stdout was [$(cat "$TEST_TMPDIR/nohash.out")]"
fi
assert_contains "case 13: documented error" "$err" \
  "ERROR: no sha256sum or shasum on PATH"

cdp="$TEST_TMPDIR/cdpath"
mkdir -p "$cdp/here/target" "$cdp/elsewhere/target"
out="$(cd "$cdp/here" && CDPATH="$cdp/elsewhere" bash "$SCRIPT" --root target 2>/dev/null)"
assert_eq "case 14: stdout is one line under an exported CDPATH" \
  "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1"
assert_eq "case 14: key is for the named directory, not the CDPATH one" \
  "$out" "$(key "$cdp/here/target")"

report_and_exit
