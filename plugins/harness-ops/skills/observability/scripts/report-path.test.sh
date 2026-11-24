#!/usr/bin/env bash

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/report-path.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

DATA="$TEST_TMPDIR/harness-ops-test"
mkdir -p "$DATA"
DATE="2026-09-07"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s: expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_match() { if [[ "$2" =~ $3 ]]; then pass "$1"; else fail "$1" "matches: $3" "$2"; fi; }

make_repo() {
  local dir="$1" remote="${2:-}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
  [[ -n "$remote" ]] && git -C "$dir" remote add origin "$remote"
  return 0
}

resolve() {
  local cwd="$1"
  shift
  (cd "$cwd" && CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "$DATE" "$@" 2>/dev/null)
}

make_repo "$TEST_TMPDIR/repo-a" "https://github.com/example/alpha.git"
make_repo "$TEST_TMPDIR/repo-b" "https://github.com/example/beta.git"
PATH_A=$(resolve "$TEST_TMPDIR/repo-a")
PATH_B=$(resolve "$TEST_TMPDIR/repo-b")
assert_ne "two repositories on one date get distinct report paths" "$PATH_A" "$PATH_B"
assert_contains "repo-a path carries its remote identity" "$PATH_A" "/reports/github.com/example/alpha/"
assert_contains "repo-b path carries its remote identity" "$PATH_B" "/reports/github.com/example/beta/"
assert_contains "filename still carries the date" "$PATH_A" "claude-observability-$DATE.md"

assert_match "path conforms to component/state-key/filename" "$PATH_A" \
  "/reports/[^/]+/[^/]+/[^/]+/[0-9a-f]{8}/claude-observability-${DATE}\.md$"

git -C "$TEST_TMPDIR/repo-a" worktree add -q -b wt-second "$TEST_TMPDIR/repo-a-wt2" >/dev/null 2>&1
PATH_A_WT2=$(resolve "$TEST_TMPDIR/repo-a-wt2")
assert_ne "two worktrees of one repository get distinct report paths" "$PATH_A" "$PATH_A_WT2"
assert_contains "the second worktree keeps the same repo identity" "$PATH_A_WT2" "/reports/github.com/example/alpha/"

PATH_A_AGAIN=$(resolve "$TEST_TMPDIR/repo-a")
assert_eq "same repo, same worktree, same date is stable" "$PATH_A" "$PATH_A_AGAIN"

DISC_A="${PATH_A%/*}"
DISC_A="${DISC_A##*/}"
assert_match "discriminator is exactly 8 hex characters" "$DISC_A" "^[0-9a-f]{8}$"
make_repo "$TEST_TMPDIR/repo-c" "https://github.com/example/alpha/$DISC_A.git"
PATH_C=$(resolve "$TEST_TMPDIR/repo-c")
assert_ne "an identity that spells another key's prefix still gets its own file" "$PATH_A" "$PATH_C"
assert_contains "the ambiguous identity nests rather than colliding" "$PATH_C" \
  "/reports/github.com/example/alpha/$DISC_A/"

make_repo "$TEST_TMPDIR/repo-noremote"
PATH_NR=$(resolve "$TEST_TMPDIR/repo-noremote")
assert_contains "a repository with no remote keys on the local rung" "$PATH_NR" "/reports/local/"
mkdir -p "$TEST_TMPDIR/plain-dir"
PATH_PD=$(cd "$TEST_TMPDIR/plain-dir" && CLAUDE_PLUGIN_DATA="$DATA" GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" --date "$DATE" 2>/dev/null)
assert_contains "a non-repository keys on the nonrepo rung" "$PATH_PD" "/reports/nonrepo/"

mkdir -p "$DATA/reports"
LEGACY="$DATA/reports/claude-observability-$DATE.md"
printf 'stale report from an unknown project\n' >"$LEGACY"
STDERR_OUT=$( (cd "$TEST_TMPDIR/repo-a" && CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "$DATE" >/dev/null) 2>&1)
assert_contains "an unkeyed leftover is named on stderr" "$STDERR_OUT" "$LEGACY"
PATH_A_WITH_LEGACY=$(resolve "$TEST_TMPDIR/repo-a")
assert_eq "the leftover does not become the resolved path" "$PATH_A" "$PATH_A_WITH_LEGACY"
assert_ne "the resolved path is not the unkeyed path" "$LEGACY" "$PATH_A_WITH_LEGACY"
rm -f "$LEGACY"

OUT_M=$(resolve "$TEST_TMPDIR/repo-b" --mkdir)
if [[ -d "$(dirname "$OUT_M")" ]]; then pass "--mkdir creates the keyed parent directory"; else fail "--mkdir creates the keyed parent directory" "directory" "absent"; fi
if [[ ! -e "$OUT_M" ]]; then pass "--mkdir does not create the report file itself"; else fail "--mkdir does not create the report file itself" "absent" "present"; fi

FAKE="$TEST_TMPDIR/fake-plugin"
mkdir -p "$FAKE/lib" "$FAKE/skills/observability/scripts"
cp "$SCRIPT" "$FAKE/skills/observability/scripts/report-path.sh"
printf '#!/usr/bin/env bash\necho "ERROR: no hash tool" >&2\nexit 2\n' >"$FAKE/lib/state-key.sh"
OUT_F=$( (cd "$TEST_TMPDIR/repo-a" && CLAUDE_PLUGIN_DATA="$DATA" bash "$FAKE/skills/observability/scripts/report-path.sh" --date "$DATE") 2>&1)
RC=$?
assert_exit "an underivable state key exits 2" 2 "$RC"
assert_not_contains "an underivable state key prints no unkeyed path" "$OUT_F" "$DATA/reports/claude-observability"

OUT_D=$( (cd "$TEST_TMPDIR/repo-a" && CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "../../../etc/passwd") 2>&1)
RC=$?
assert_exit "a traversal --date is refused" 2 "$RC"
assert_contains "the refusal names the offending value" "$OUT_D" "YYYY-MM-DD"

# --- Case group 10: another plugin's data dir is never used ---
# Another plugin's SessionStart hook can export its own data dir into every Bash
# call as CLAUDE_PLUGIN_DATA.
FOREIGN="$TEST_TMPDIR/codex-openai-codex"
OUT_X=$(cd "$TEST_TMPDIR/repo-a" && HOME="$TEST_TMPDIR/home" CLAUDE_PLUGIN_DATA="$FOREIGN" bash "$SCRIPT" --date "$DATE" --mkdir 2>/dev/null)
assert_contains "a foreign CLAUDE_PLUGIN_DATA falls back to the home data dir" "$OUT_X" "$TEST_TMPDIR/home/.claude/plugins/data/harness-ops/reports/"
assert_eq "a foreign CLAUDE_PLUGIN_DATA gets no directory" "absent" "$([[ -e "$FOREIGN" ]] && echo present || echo absent)"

OUT_NH=$(cd "$TEST_TMPDIR/repo-a" && env -u HOME CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "$DATE" 2>/dev/null)
assert_contains "an unset HOME still uses a harness-ops CLAUDE_PLUGIN_DATA" "$OUT_NH" "$DATA/reports/"

[[ $FAILED -eq 0 ]] || exit 1
echo "All cases passed ($CASE_NUM)."
