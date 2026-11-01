#!/usr/bin/env bash
# Tests for sync-shared-copies.sh on fixture repositories that carry this
# repository's real scripts/sync-shared-copies.sh and scripts/lib.
# shellcheck disable=SC2310  # run chains its steps with &&, so its status is the first failure's
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sync-shared-copies.sh"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

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

g() { git -C "$1" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false "${@:2}"; }

# A repository whose main holds a canonical, its generated copy and the real
# tooling, and a PR branch carrying one change of its own. Then main changes
# the canonical. Prints the repo path; base/ is a checkout of main's tip.
# An optional second argument is the registry line.
fixture() {
  local name=$1 repo="$TMP/$1" entry=${2:-lib/shared.sh plugins/p/lib/shared.sh}
  mkdir -p "$repo/scripts" "$repo/lib" "$repo/plugins/p/lib"
  git init -q -b main "$repo"
  cp "$ROOT/scripts/sync-shared-copies.sh" "$repo/scripts/"
  cp -R "$ROOT/scripts/lib" "$repo/scripts/lib"
  printf '%s\n' "$entry" >"$repo/scripts/shared-copies.txt"
  printf 'echo one\n' >"$repo/lib/shared.sh"
  (cd "$repo" && bash scripts/sync-shared-copies.sh) >/dev/null
  g "$repo" add -A
  g "$repo" commit -qm base
  g "$repo" checkout -qb pr
  printf 'pr\n' >"$repo/notes.txt"
  g "$repo" add notes.txt
  g "$repo" commit -qm pr
  g "$repo" checkout -q main
  printf 'echo two\n' >"$repo/lib/shared.sh"
  g "$repo" commit -qam canonical
  git clone -q "$repo" "$TMP/$name-base"
  printf '%s\n' "$repo"
}

# Merge main into pr without committing, as merge-base/prepare.sh leaves a
# clean merge, then run the activity's script.
run() {
  local repo=$1 base_dir=$2
  g "$repo" checkout -q pr &&
    rm -f "$TMP/out.patch" &&
    g "$repo" merge -q --no-ff --no-commit main >/dev/null 2>&1 &&
    bash "$SUT" "$base_dir" "$repo" "$(g "$repo" rev-parse main)" "$TMP/out.patch" 2>/dev/null
}

# A changed canonical: the copy is regenerated, the patch holds it alone, and
# the merge commits with it.
repo=$(fixture regen)
rc=0
out=$(run "$repo" "$TMP/regen-base") || rc=$?
check "changed canonical: exit 0" 0 "$rc"
check "changed canonical: state written" state=written "$(grep '^state=' <<<"$out")"
check "changed canonical: one path" paths=1 "$(grep '^paths=' <<<"$out")"
check "changed canonical: the patch names the copy alone" "plugins/p/lib/shared.sh" "$(git apply --numstat "$TMP/out.patch" | cut -f3)"
check "changed canonical: patch hash" "$(sha256sum <"$TMP/out.patch" | cut -d' ' -f1)" "$(grep '^sha256=' <<<"$out" | cut -d= -f2)"
g "$repo" add -A
g "$repo" commit -qm merge
check "changed canonical: the committed copy carries the new canonical" 1 "$(grep -c '^echo two$' "$repo/plugins/p/lib/shared.sh")"
check "changed canonical: the commit merges main" 3 "$(g "$repo" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')"
check "changed canonical: the drift check passes on the commit" 0 "$( (cd "$repo" && bash scripts/sync-shared-copies.sh --check >/dev/null 2>&1) && echo 0 || echo 1)"

# A head that registers a new copy outside any plugin: refused, no patch.
repo=$(fixture registry)
g "$repo" checkout -q pr
printf 'lib/shared.sh plugins/p/lib/shared.sh\nlib/shared.sh .github/workflows/evil.yml\n' >"$repo/scripts/shared-copies.txt"
g "$repo" commit -qam registry
g "$repo" checkout -q main
rc=0
out=$(run "$repo" "$TMP/registry-base") || rc=$?
check "head alters the registry: exit 3" 3 "$rc"
check "head alters the registry: refused" refused=shared-copy-tooling-changed "$out"
check "head alters the registry: nothing written outside the merge" "" "$(g "$repo" ls-files --others)"

# A head that edits the sync script: refused before the script runs.
repo=$(fixture script)
g "$repo" checkout -q pr
# shellcheck disable=SC2016  # the planted line expands when the head's script runs
printf 'touch "$(git rev-parse --show-toplevel)/pwned"\n' >>"$repo/scripts/sync-shared-copies.sh"
g "$repo" commit -qam script
g "$repo" checkout -q main
rc=0
out=$(run "$repo" "$TMP/script-base") || rc=$?
check "head alters the script: exit 3" 3 "$rc"
check "head alters the script: refused" refused=shared-copy-tooling-changed "$out"
check "head alters the script: the head's script never ran" no "$([[ -e $repo/pwned ]] && echo yes || echo no)"

# A head that adds a file under scripts/lib: refused.
repo=$(fixture lib)
g "$repo" checkout -q pr
printf 'x\n' >"$repo/scripts/lib/extra.sh"
g "$repo" add scripts/lib/extra.sh
g "$repo" commit -qm lib
g "$repo" checkout -q main
rc=0
out=$(run "$repo" "$TMP/lib-base") || rc=$?
check "head alters scripts/lib: refused" refused=shared-copy-tooling-changed "$out"

# A run that writes a path the base registry does not list: refused, no patch.
repo=$(fixture stray)
printf 'printf x >.github-stray\n' >>"$TMP/stray-base/scripts/sync-shared-copies.sh"
rc=0
out=$(run "$repo" "$TMP/stray-base") || rc=$?
check "unregistered path written: exit 3" 3 "$rc"
check "unregistered path written: refused" refused=shared-copy-path-unregistered "$out"
check "unregistered path written: no patch" "" "$(cat "$TMP/out.patch" 2>/dev/null || true)"

# Copies already current: empty, nothing to push.
repo=$(fixture current)
g "$repo" checkout -q main
g "$repo" revert --no-edit HEAD >/dev/null
rc=0
out=$(run "$repo" "$TMP/current-base") || rc=$?
check "copies current: empty" state=empty "$(grep '^state=' <<<"$out")"

# A registry line with an inline comment registers its copy, as the
# canonical sync script reads it.
repo=$(fixture inline 'lib/shared.sh plugins/p/lib/shared.sh # generated copy')
rc=0
out=$(run "$repo" "$TMP/inline-base") || rc=$?
check "inline comment: exit 0" 0 "$rc"
check "inline comment: state written" state=written "$(grep '^state=' <<<"$out")"

# The PR and main each edit their own end of the canonical and regenerate the
# copy: the merge holds current copies, so the run is empty and the push job
# commits the merge alone.
repo=$(fixture disjoint)
printf 'echo one\necho 2\necho 3\necho 4\necho 5\n' >"$TMP/disjoint-lines"
for side in main pr; do
  g "$repo" checkout -q "$side"
  cp "$TMP/disjoint-lines" "$repo/lib/shared.sh"
  (cd "$repo" && bash scripts/sync-shared-copies.sh) >/dev/null
  g "$repo" commit -qam "$side: canonical body"
done
g "$repo" checkout -q main
g "$repo" merge -q --no-edit pr >/dev/null
g "$repo" checkout -q pr
g "$repo" merge -q --ff-only main
sed -i 's/^echo one$/echo pr/' "$repo/lib/shared.sh"
(cd "$repo" && bash scripts/sync-shared-copies.sh) >/dev/null
g "$repo" commit -qam "pr: first line"
g "$repo" checkout -q main
sed -i 's/^echo 5$/echo main/' "$repo/lib/shared.sh"
(cd "$repo" && bash scripts/sync-shared-copies.sh) >/dev/null
g "$repo" commit -qam "main: last line"
rm -rf "$TMP/disjoint-base"
git clone -q "$repo" "$TMP/disjoint-base"
rc=0
out=$(run "$repo" "$TMP/disjoint-base") || rc=$?
check "disjoint canonical edits: exit 0" 0 "$rc"
check "disjoint canonical edits: empty" state=empty "$(grep '^state=' <<<"$out")"
check "disjoint canonical edits: the merged copy holds both edits" 2 "$(grep -cE '^echo (pr|main)$' "$repo/plugins/p/lib/shared.sh")"

exit "$FAILED"
