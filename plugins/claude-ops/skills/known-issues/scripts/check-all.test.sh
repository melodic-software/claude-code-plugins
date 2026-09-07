#!/usr/bin/env bash
# Regression tests for check-all.sh.
#
# Coverage:
#   - reads <output-dir>/registry-snapshot.tsv (header
#     written to OUT regardless of input rows)
#   - per-row gh failure → FETCH_FAILED transition
#   - per-row gh JSON success → OPEN/CLOSED transition computed correctly
#   - empty snapshot → header-only results, exit 0
#   - missing snapshot → exit 1
#   - snapshot without trailing newline → last row still processed
#   - the default output directory is KEYED: two repositories, and two
#     worktrees of one repository, get distinct directories, and one project
#     is never served another's rows
#   - the joined key cannot be re-parsed two ways (separator safety)
#   - an unkeyed leftover is named on stderr and never read
#   - an underivable state key fails rather than falling back to unkeyed
#
# Uses a per-case fake output tree and a PATH-stub `gh`.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-all.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Inline test helpers — self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_ne() { if [[ "$3" != "$2" ]]; then pass "$1"; else fail "$1" "different from: $2" "$3"; fi; }
assert_exit() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_file_exists() { if [[ -f "$2" ]]; then pass "$1"; else fail "$1" "file exists: $2" "absent"; fi; }

# Build per-case CWD with snapshot.tsv + PATH-stub gh.
make_case() {
  local case_dir="$1" snapshot_content="$2" gh_mode="$3"
  mkdir -p "$case_dir/check-all-output" "$case_dir/path-stub"
  printf '%s' "$snapshot_content" >"$case_dir/check-all-output/registry-snapshot.tsv"

  case "$gh_mode" in
  fail)
    cat >"$case_dir/path-stub/gh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
    ;;
  closed)
    cat >"$case_dir/path-stub/gh" <<'STUB'
#!/usr/bin/env bash
echo '{"state":"CLOSED","stateReason":"completed","closedAt":"2026-01-01T00:00:00Z"}'
STUB
    ;;
  open)
    cat >"$case_dir/path-stub/gh" <<'STUB'
#!/usr/bin/env bash
echo '{"state":"OPEN","stateReason":"","closedAt":""}'
STUB
    ;;
  *) ;;
  esac
  chmod +x "$case_dir/path-stub/gh" 2>/dev/null || true
}

# --- Case 1: gh always fails → FETCH_FAILED transition ---
CASE_A="$TEST_TMPDIR/case-a"
make_case "$CASE_A" $'1\texample-org/example-repo\topen\n' fail
(cd "$CASE_A" && CHECK_ALL_OUTPUT_DIR="$CASE_A/check-all-output" PATH="$CASE_A/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "gh-fail → exit 0" 0 "$RC"
OUT_FILE="$CASE_A/check-all-output/check-all-results.tsv"
assert_file_exists "results.tsv written" "$OUT_FILE"
RESULTS=$(cat "$OUT_FILE")
assert_contains "FETCH_FAILED transition recorded" "$RESULTS" "FETCH_FAILED"

# --- Case 2: tracked=open + state=CLOSED → OPEN->CLOSED transition ---
CASE_B="$TEST_TMPDIR/case-b"
make_case "$CASE_B" $'42\texample-org/example-repo\topen\n' closed
(cd "$CASE_B" && CHECK_ALL_OUTPUT_DIR="$CASE_B/check-all-output" PATH="$CASE_B/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "open→closed → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_B/check-all-output/check-all-results.tsv")
assert_contains "OPEN->CLOSED transition" "$RESULTS" "OPEN->CLOSED"

# --- Case 3: tracked=closed + state=OPEN → CLOSED->OPEN transition ---
CASE_C="$TEST_TMPDIR/case-c"
make_case "$CASE_C" $'7\texample-org/example-repo\tclosed\n' open
(cd "$CASE_C" && CHECK_ALL_OUTPUT_DIR="$CASE_C/check-all-output" PATH="$CASE_C/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "closed→open → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_C/check-all-output/check-all-results.tsv")
assert_contains "CLOSED->OPEN transition" "$RESULTS" "CLOSED->OPEN"

# --- Case 4: tracked=open + state=OPEN → UNCHANGED ---
CASE_D="$TEST_TMPDIR/case-d"
make_case "$CASE_D" $'5\texample-org/example-repo\topen\n' open
(cd "$CASE_D" && CHECK_ALL_OUTPUT_DIR="$CASE_D/check-all-output" PATH="$CASE_D/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "unchanged → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_D/check-all-output/check-all-results.tsv")
assert_contains "UNCHANGED transition" "$RESULTS" "UNCHANGED"

# --- Case 5: empty snapshot → header only, exit 0 ---
CASE_E="$TEST_TMPDIR/case-e"
mkdir -p "$CASE_E/check-all-output"
printf '' >"$CASE_E/check-all-output/registry-snapshot.tsv"
(cd "$CASE_E" && CHECK_ALL_OUTPUT_DIR="$CASE_E/check-all-output" PATH="$CASE_E/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "empty snapshot → exit 0" 0 "$RC"
RESULTS=$(cat "$CASE_E/check-all-output/check-all-results.tsv")
assert_contains "header present" "$RESULTS" "transition"
assert_not_contains "no FETCH_FAILED on empty input" "$RESULTS" "FETCH_FAILED"
LOG_CONTENT=$(cat "$CASE_E/check-all-output/check-all.log")
assert_contains "log ends DONE" "$LOG_CONTENT" "DONE"

# --- Case 6: missing snapshot → exit 1 ---
CASE_F="$TEST_TMPDIR/case-f"
mkdir -p "$CASE_F/check-all-output"
(cd "$CASE_F" && CHECK_ALL_OUTPUT_DIR="$CASE_F/check-all-output" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "missing snapshot → exit 1" 1 "$RC"

# --- Case 7: snapshot missing trailing newline → last row still processed ---
CASE_G="$TEST_TMPDIR/case-g"
make_case "$CASE_G" $'5\texample-org/example-repo\topen\n42\texample-org/example-repo\tclosed' open
(cd "$CASE_G" && CHECK_ALL_OUTPUT_DIR="$CASE_G/check-all-output" PATH="$CASE_G/path-stub:$PATH" bash "$SCRIPT") >/dev/null 2>&1
RC=$?
assert_exit "no trailing newline → exit 0" 0 "$RC"
RESULTS_FILE="$CASE_G/check-all-output/check-all-results.tsv"
DATA_ROWS=$(($(wc -l <"$RESULTS_FILE") - 1))
assert_eq "no trailing newline → both rows processed" 2 "$DATA_ROWS"
LAST_ROW=$(tail -n 1 "$RESULTS_FILE")
assert_contains "last row (no trailing newline) has issue number 42" "$LAST_ROW" $'42\t'
LOG_G=$(cat "$CASE_G/check-all-output/check-all.log")
assert_contains "no trailing newline → progress counts both rows" "$LOG_G" "[2/2]"

# ---------------------------------------------------------------------------
# Keying: the DEFAULT output directory (no CHECK_ALL_OUTPUT_DIR override).
# Every case above pins the directory explicitly, so none of them exercises it.
# ---------------------------------------------------------------------------

KEY_DATA="$TEST_TMPDIR/plugindata"
mkdir -p "$KEY_DATA"

make_repo() { # <dir> [remote-url]
  local dir="$1" remote="${2:-}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
  [[ -n "$remote" ]] && git -C "$dir" remote add origin "$remote"
  return 0
}

out_dir_for() { # <cwd>
  (cd "$1" && CLAUDE_PLUGIN_DATA="$KEY_DATA" bash "$SCRIPT" --print-output-dir 2>/dev/null)
}

REPO_A="$TEST_TMPDIR/key-repo-a"
REPO_B="$TEST_TMPDIR/key-repo-b"
make_repo "$REPO_A" "https://github.com/example/alpha.git"
make_repo "$REPO_B" "https://github.com/example/beta.git"

DIR_A=$(out_dir_for "$REPO_A")
DIR_B=$(out_dir_for "$REPO_B")
assert_ne "two repositories get distinct output directories" "$DIR_A" "$DIR_B"
assert_contains "repo-a directory carries its remote identity" "$DIR_A" "/check-all-output/github.com/example/alpha/"
assert_contains "repo-b directory carries its remote identity" "$DIR_B" "/check-all-output/github.com/example/beta/"
if [[ -d "$DIR_A" ]]; then pass "--print-output-dir creates the directory"; else fail "--print-output-dir creates the directory" "directory" "absent"; fi

# Two worktrees of ONE repository. The registry is project-relative whenever the
# `registry_dir` option is set, so two worktrees hold two registries and must
# not share a scratch directory. state-key.sh splits them.
git -C "$REPO_A" worktree add -q -b key-wt-second "$TEST_TMPDIR/key-repo-a-wt2" >/dev/null 2>&1
DIR_A_WT2=$(out_dir_for "$TEST_TMPDIR/key-repo-a-wt2")
assert_ne "two worktrees of one repository get distinct output directories" "$DIR_A" "$DIR_A_WT2"
assert_contains "the second worktree keeps the same repo identity" "$DIR_A_WT2" "/check-all-output/github.com/example/alpha/"
assert_eq "the same worktree resolves to the same directory twice" "$DIR_A" "$(out_dir_for "$REPO_A")"

# Separator safety. The key joins `<identity>/<discriminator>`, and the identity
# field can itself contain `/`. Build the ambiguous shape: repo-c's remote
# normalizes to repo-a's identity followed by repo-a's own discriminator. The
# discriminator is a fixed 8 hex characters, so the join is not re-parsable and
# repo-c cannot land on repo-a's directory.
DISC_A="${DIR_A##*/}"
if [[ "$DISC_A" =~ ^[0-9a-f]{8}$ ]]; then pass "discriminator is exactly 8 hex characters"; else fail "discriminator is exactly 8 hex characters" "8 hex chars" "$DISC_A"; fi
REPO_C="$TEST_TMPDIR/key-repo-c"
make_repo "$REPO_C" "https://github.com/example/alpha/$DISC_A.git"
DIR_C=$(out_dir_for "$REPO_C")
assert_ne "an identity that spells another key's prefix gets its own directory" "$DIR_A" "$DIR_C"
assert_contains "the ambiguous identity nests rather than colliding" "$DIR_C" "/check-all-output/github.com/example/alpha/$DISC_A/"

# End to end: the collision this fixes. Each project writes its OWN snapshot to
# the directory the script names, then runs. Before keying, both snapshots went
# to one path and the first project read the second's rows back.
STUB_DIR="$TEST_TMPDIR/key-stub"
mkdir -p "$STUB_DIR"
printf '#!/usr/bin/env bash\necho %s\n' \
  "'"'{"state":"OPEN","stateReason":"","closedAt":""}'"'" >"$STUB_DIR/gh"
chmod +x "$STUB_DIR/gh"
printf '111\texample/alpha\topen\n' >"$DIR_A/registry-snapshot.tsv"
printf '222\texample/beta\topen\n' >"$DIR_B/registry-snapshot.tsv"
(cd "$REPO_A" && CLAUDE_PLUGIN_DATA="$KEY_DATA" PATH="$STUB_DIR:$PATH" bash "$SCRIPT" >/dev/null 2>&1)
A_ROWS=$(tail -n +2 "$DIR_A/check-all-results.tsv" | cut -f1 | tr '\n' ' ')
assert_eq "repo-a is served its own registry rows, not repo-b's" "111 " "$A_ROWS"

# An unkeyed leftover from the older layout is NAMED and never read.
LEGACY_DIR="$KEY_DATA/check-all-output"
printf '999\texample/legacy\topen\n' >"$LEGACY_DIR/registry-snapshot.tsv"
LEGACY_ERR=$( (cd "$REPO_A" && CLAUDE_PLUGIN_DATA="$KEY_DATA" PATH="$STUB_DIR:$PATH" bash "$SCRIPT" >/dev/null) 2>&1 )
assert_contains "an unkeyed leftover is named on stderr" "$LEGACY_ERR" "$LEGACY_DIR/registry-snapshot.tsv"
A_ROWS_AFTER=$(tail -n +2 "$DIR_A/check-all-results.tsv" | cut -f1 | tr '\n' ' ')
assert_eq "the unkeyed leftover is not read" "111 " "$A_ROWS_AFTER"
assert_not_contains "the leftover's rows never reach the results" "$A_ROWS_AFTER" "999"
rm -f "$LEGACY_DIR/registry-snapshot.tsv"

# Fail closed. A copy of the script in a fake plugin tree whose lib/state-key.sh
# fails: falling back to the unkeyed path would silently restore the collision.
FAKE="$TEST_TMPDIR/fake-plugin"
mkdir -p "$FAKE/lib" "$FAKE/skills/known-issues/scripts"
cp "$SCRIPT" "$FAKE/skills/known-issues/scripts/check-all.sh"
printf '#!/usr/bin/env bash\necho "ERROR: no hash tool" >&2\nexit 2\n' >"$FAKE/lib/state-key.sh"
FAKE_OUT=$( (cd "$REPO_A" && CLAUDE_PLUGIN_DATA="$KEY_DATA" bash "$FAKE/skills/known-issues/scripts/check-all.sh" --print-output-dir) 2>&1 )
RC=$?
assert_exit "an underivable state key exits 2" 2 "$RC"
assert_not_contains "an underivable state key prints no unkeyed path" "$FAKE_OUT" "$LEGACY_DIR"

# An unknown argument is refused rather than silently ignored.
(bash "$SCRIPT" --not-a-flag) >/dev/null 2>&1
RC=$?
assert_exit "an unknown argument exits 2" 2 "$RC"

[[ $FAILED -eq 0 ]] || exit 1
echo "All cases passed ($CASE_NUM)."
