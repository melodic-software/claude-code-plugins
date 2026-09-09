#!/usr/bin/env bash
# Regression tests for file-provenance.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/file-provenance.sh"

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}

make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}
commit_as() { # <repo> <author name> <subject>
  (cd "$1" && git add -A && git -c user.name="$2" -c user.email="bot@example.com" commit -q -m "$3")
}

# --- Case 1: --help and usage errors ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
rc=0
bash "$SCRIPT" >/dev/null 2>&1 || rc=$?
assert_eq "no path exits 2" 2 "$rc"

# --- Case 2: header signal, with and without a named source ---

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
printf '# SYNC-MANAGED FILE. DO NOT EDIT.\n# Source of truth: acme/standards, components/x/x.yml\nname: x\n' >"$REPO/managed.yml"
printf '<!-- SYNC-MANAGED -->\nbody\n' >"$REPO/managed-unnamed.md"
printf '# Local\n\nbody\n' >"$REPO/local.md"
commit_as "$REPO" "test" "docs: fixture"

OUT=$(cd "$REPO" && bash "$SCRIPT" managed.yml)
assert_eq "header signal names the upstream" $'synced\theader\tacme/standards' "$OUT"
OUT=$(cd "$REPO" && bash "$SCRIPT" managed-unnamed.md)
assert_eq "header signal without a source line reports unknown upstream" $'synced\theader\tunknown' "$OUT"
OUT=$(cd "$REPO" && bash "$SCRIPT" local.md)
assert_eq "a hand-authored file is local" $'local\tnone\tunknown' "$OUT"

# --- Case 3: commit signal by subject, then by author ---

printf 'synced body\n' >"$REPO/by-subject.md"
commit_as "$REPO" "test" "chore: sync standards components (#1)"
OUT=$(cd "$REPO" && bash "$SCRIPT" by-subject.md)
assert_eq "a sync subject marks the file synced" $'synced\tcommit\tunknown' "$OUT"

printf 'synced body\n' >"$REPO/by-author.md"
commit_as "$REPO" "melodic-standards-sync[bot]" "update managed files"
OUT=$(cd "$REPO" && bash "$SCRIPT" by-author.md)
assert_eq "a sync author marks the file synced" $'synced\tcommit\tunknown' "$OUT"

# A later hand edit takes ownership back: the LAST commit decides.
printf 'edited by hand\n' >>"$REPO/by-subject.md"
commit_as "$REPO" "test" "fix: hand edit"
OUT=$(cd "$REPO" && bash "$SCRIPT" by-subject.md)
assert_eq "the last commit decides: a hand edit after a sync is local" $'local\tnone\tunknown' "$OUT"

# --- Case 4: --synced exit codes, untracked and missing files ---

rc=0
(cd "$REPO" && bash "$SCRIPT" --synced managed.yml) || rc=$?
assert_eq "--synced exits 0 for a synced file" 0 "$rc"
rc=0
(cd "$REPO" && bash "$SCRIPT" --synced local.md) || rc=$?
assert_eq "--synced exits 1 for a local file" 1 "$rc"
printf 'new\n' >"$REPO/untracked.md"
OUT=$(cd "$REPO" && bash "$SCRIPT" untracked.md)
assert_eq "an untracked file is local" $'local\tnone\tunknown' "$OUT"
OUT=$(cd "$REPO" && bash "$SCRIPT" absent.md)
assert_eq "a missing file is local" $'local\tnone\tunknown' "$OUT"

# --- Case 5: outside a repository, only the header signal can fire ---

NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
printf 'SYNC-MANAGED\n' >"$NOREPO/h.md"
printf 'plain\n' >"$NOREPO/p.md"
OUT=$(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" h.md)
assert_eq "header fires outside a repo" $'synced\theader\tunknown' "$OUT"
OUT=$(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" p.md)
assert_eq "no history outside a repo means local" $'local\tnone\tunknown' "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
