#!/usr/bin/env bash
# Tests for tree-entries.sh on throwaway repositories: `main` (the trusted
# base) is merged into `pr` (the gated head) without committing, the test
# stages a resolution, and the entries must describe exactly the index.
# shellcheck disable=SC2310  # tg wraps one git call, so its status is that call's
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENTRIES="$SCRIPT_DIR/tree-entries.sh"

# Keep the developer's own git configuration, and any inherited repository
# location, out of every fixture.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() {
  printf 'not ok - %s\n' "$1"
  FAILED=1
}
check() {
  if [[ $2 == "$3" ]]; then ok "$1"; else not_ok "$1: expected [$2], got [$3]"; fi
}

tg() { git -C "$R" -c user.name=t -c user.email=t@t.t -c commit.gpgsign=false "$@"; }
put() {
  mkdir -p "$(dirname "$R/$1")"
  printf '%b' "$2" >"$R/$1"
}
commit() {
  tg add -A
  tg commit -q --allow-empty -m "$1"
}
new_repo() {
  R="$(mktemp -d "$TMP/repo.XXXXXX")"
  git init -q -b main "$R"
  tg config core.autocrlf false
}
merge_main() {
  tg checkout -q pr
  tg merge --no-commit --no-ff main >/dev/null 2>&1 || true
}
# run_entries [<head> <base> <tree>]: sets OUT (sorted), ERR and RC. The tree
# defaults to the index written as a tree, as post.sh prints it.
run_entries() {
  local head=${1:-$(tg rev-parse pr)} base=${2:-$(tg rev-parse main)} tree=${3:-}
  [[ -n $tree ]] || tree=$(tg write-tree 2>/dev/null) || tree=none
  RC=0
  OUT=$(cd "$R" && bash "$ENTRIES" "$head" "$base" "$tree" 2>"$TMP/err" | LC_ALL=C sort) || RC=$?
  ERR=$(cat "$TMP/err")
}
blob() { printf '%b' "$1" | git hash-object --stdin; }
line() { printf '%s %s %s\t%s' "$1" "$2" "$3" "$4"; }

echo '# many-paths'
# The base adds 600 files, deletes one, renames one and edits three the PR also
# edits: auto.txt merges cleanly from both sides, c.txt and r.txt conflict.
new_repo
put auto.txt '1\n2\n3\n4\n5\n'
put c.txt 'base c\n'
put r.txt 'base r\n'
put old.txt 'old\n'
put moved.txt 'moved content\nkept whole\n'
commit base
tg checkout -q -b pr
put auto.txt 'P\n2\n3\n4\n5\n'
put c.txt 'pr c\n'
put r.txt 'pr r\n'
commit pr
tg checkout -q main
put auto.txt '1\n2\n3\n4\nM\n'
put c.txt 'main c\n'
put r.txt 'main r\n'
tg rm -q old.txt
tg mv moved.txt renamed.txt
for i in $(seq 1 600); do put "gen/f$i.txt" "$i\n"; done
commit main
merge_main
put c.txt 'resolved c\n'
put r.txt 'main r\n'
tg add c.txt r.txt
expected=$(
  {
    line 100644 "$(blob 'P\n2\n3\n4\nM\n')" create-blob auto.txt
    echo
    line 100644 "$(blob 'resolved c\n')" create-blob c.txt
    echo
    for i in $(seq 1 600); do
      line 100644 "$(blob "$i\n")" - "gen/f$i.txt"
      echo
    done
    line 100644 null - moved.txt
    echo
    line 100644 null - old.txt
    echo
    line 100644 "$(blob 'main r\n')" - r.txt
    echo
    line 100644 "$(blob 'moved content\nkept whole\n')" - renamed.txt
    echo
  } | LC_ALL=C sort
)
run_entries
check 'many-paths: exit 0' 0 "$RC"
if [[ $OUT == "$expected" ]]; then ok 'many-paths: one entry per staged path'; else not_ok "many-paths: entries differ: $(diff <(echo "$expected") <(echo "$OUT") | head -5)"; fi
check 'many-paths: 606 entries' 606 "$(grep -c . <<<"$OUT")"
check 'many-paths: only blobs neither parent holds are created' 2 "$(grep -c ' create-blob	' <<<"$OUT")"

echo '# untracked-dir'
# claude-code-action leaves an untracked .claude-pr/ directory, and the model
# may leave unstaged edits: neither is staged, so neither is an entry.
new_repo
put c.txt 'base\n'
put keep.txt 'keep\n'
put tool.sh 'echo\n'
commit base
tg checkout -q -b pr
put c.txt 'pr\n'
put tool.sh 'echo pr\n'
commit pr
tg checkout -q main
put c.txt 'main\n'
commit main
merge_main
put c.txt 'resolved\n'
tg add c.txt
tg update-index --chmod=+x tool.sh
# A staged submodule pointer names a commit, never a blob to upload.
SUB=$(tg rev-parse main)
tg update-index --add --cacheinfo "160000,$SUB,sub"
put .claude-pr/snapshot.txt 'snapshot\n'
put keep.txt 'unstaged edit\n'
put c.txt 'unstaged edit on top of the resolution\n'
run_entries
expected=$(
  line 100644 "$(blob 'resolved\n')" create-blob c.txt
  echo
  line 100755 "$(blob 'echo pr\n')" - tool.sh
  echo
  line 160000 "$SUB" - sub
)
check 'untracked-dir: only staged entries; a mode change and a gitlink upload nothing' "$expected" "$OUT"
# The entries describe the tree post.sh validated, not whatever the index
# holds by the time the commit step runs.
TREE=$(tg write-tree)
tg add keep.txt .claude-pr
run_entries "" "" "$TREE"
check 'untracked-dir: changes staged after the tree was written stay out' "$expected" "$OUT"

echo '# unmerged entries and unsafe paths'
# conflict_with <main-only path>: c.txt conflicts; main also adds the path.
conflict_with() {
  new_repo
  put c.txt 'base\n'
  commit base
  tg checkout -q -b pr
  put c.txt 'pr\n'
  commit pr
  tg checkout -q main
  put c.txt 'main\n'
  put "$1" 'x\n'
  commit main
  merge_main
}
conflict_with plain.txt
put c.txt 'resolved\n'
tg add c.txt
TREE=$(tg write-tree)
# Hex of a length between the two object-id sizes is a ref name, never an id:
# a branch and a tag named with 45 hex digits must not resolve.
L45=$(printf 'a%.0s' {1..45}) B45=$(printf 'b%.0s' {1..45})
tg branch -f "$L45" main
tg tag "$B45" "$TREE"
run_entries "" "" "$B45"
check 'unsafe input: a 45-hex tag naming the tree is refused' 1 "$RC"
for bad in main HEAD --output=x "$(tg rev-parse --short main)" "$L45"; do
  run_entries "$bad" "" "$TREE"
  check "unsafe input: a gated head given as '$bad' is refused" 1 "$RC"
  run_entries "" "$bad" "$TREE"
  check "unsafe input: a trusted base given as '$bad' is refused" 1 "$RC"
  run_entries "" "" "$bad"
  check "unsafe input: a tree given as '$bad' is refused" 1 "$RC"
done
run_entries "" "" "$(tg rev-parse main:c.txt)"
check 'unsafe input: a blob given as the tree is refused' 1 "$RC"
run_entries "" "" "$(tg rev-parse --short "$TREE")"
check 'unsafe input: an abbreviated tree id is refused' 1 "$RC"
conflict_with $'two\nlines.txt'
put c.txt 'resolved\n'
tg add c.txt
run_entries
check 'unsafe paths: a path holding a newline fails' 1 "$RC"
check 'unsafe paths: the error names the cause' 'tree-entries.sh: a staged path holds a newline' "$ERR"

if ((FAILED)); then
  echo 'FAILED' >&2
  exit 1
fi
echo 'all tree-entries.sh tests passed'
