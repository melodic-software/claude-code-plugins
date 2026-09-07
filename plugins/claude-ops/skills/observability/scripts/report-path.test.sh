#!/usr/bin/env bash
# Regression tests for report-path.sh, the keyed `--write` report path.
#
# Coverage:
#   - two repositories, same date -> distinct report paths (the collision fixed)
#   - two worktrees of ONE repository -> distinct report paths (state-key.sh
#     splits worktrees, and this artifact needs that: the hook event log lives
#     inside the checkout)
#   - same repository, same worktree, same date -> the SAME path as before, so
#     the fix does not change within-context behavior
#   - separator safety: the joined key `<identity>/<discriminator>` cannot be
#     re-parsed two ways, because the discriminator is a fixed 8 hex chars and
#     the identity is the rest. A repository whose remote normalizes onto
#     another's identity-plus-discriminator prefix still gets its own file.
#   - the path conforms to `<component>/<state-key>/<filename>`
#   - an unkeyed leftover is NAMED on stderr and never becomes the path
#   - an underivable state key FAILS rather than falling back to unkeyed
#   - --date is validated as a filename component (no traversal)

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/report-path.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

DATA="$TEST_TMPDIR/plugindata"
mkdir -p "$DATA"
DATE="2026-09-07"

# Inline test helpers, self-contained with no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s: expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_ne() { if [[ "$3" != "$2" ]]; then pass "$1"; else fail "$1" "different from: $2" "$3"; fi; }
assert_exit() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }
assert_match() { if [[ "$2" =~ $3 ]]; then pass "$1"; else fail "$1" "matches: $3" "$2"; fi; }

# Build a git repository with one commit and (optionally) a remote URL.
make_repo() { # <dir> [remote-url]
  local dir="$1" remote="${2:-}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m init
  [[ -n "$remote" ]] && git -C "$dir" remote add origin "$remote"
  return 0
}

resolve() { # <cwd> [extra args...]
  local cwd="$1"
  shift
  (cd "$cwd" && CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "$DATE" "$@" 2>/dev/null)
}

# --- Case group 1: two repositories on the same date ---
make_repo "$TEST_TMPDIR/repo-a" "https://github.com/example/alpha.git"
make_repo "$TEST_TMPDIR/repo-b" "https://github.com/example/beta.git"
PATH_A=$(resolve "$TEST_TMPDIR/repo-a")
PATH_B=$(resolve "$TEST_TMPDIR/repo-b")
assert_ne "two repositories on one date get distinct report paths" "$PATH_A" "$PATH_B"
assert_contains "repo-a path carries its remote identity" "$PATH_A" "/reports/github.com/example/alpha/"
assert_contains "repo-b path carries its remote identity" "$PATH_B" "/reports/github.com/example/beta/"
assert_contains "filename still carries the date" "$PATH_A" "claude-observability-$DATE.md"

# `<component>/<state-key>/<filename>`, with the state key's two parts present.
assert_match "path conforms to component/state-key/filename" "$PATH_A" \
  "/reports/[^/]+/[^/]+/[^/]+/[0-9a-f]{8}/claude-observability-${DATE}\.md$"

# --- Case group 2: two worktrees of ONE repository ---
git -C "$TEST_TMPDIR/repo-a" worktree add -q -b wt-second "$TEST_TMPDIR/repo-a-wt2" >/dev/null 2>&1
PATH_A_WT2=$(resolve "$TEST_TMPDIR/repo-a-wt2")
assert_ne "two worktrees of one repository get distinct report paths" "$PATH_A" "$PATH_A_WT2"
assert_contains "the second worktree keeps the same repo identity" "$PATH_A_WT2" "/reports/github.com/example/alpha/"

# --- Case group 3: same context, same date -> stable ---
PATH_A_AGAIN=$(resolve "$TEST_TMPDIR/repo-a")
assert_eq "same repo, same worktree, same date is stable" "$PATH_A" "$PATH_A_AGAIN"

# --- Case group 4: separator safety ---
# The key joins two fields with `/`, and the identity field can itself contain
# `/`. Construct the ambiguous shape on purpose: repo-c's remote normalizes to
# repo-a's identity followed by repo-a's own discriminator. If the join were
# re-parsable two ways, repo-c would land on repo-a's file.
DISC_A="${PATH_A%/*}"
DISC_A="${DISC_A##*/}"
assert_match "discriminator is exactly 8 hex characters" "$DISC_A" "^[0-9a-f]{8}$"
make_repo "$TEST_TMPDIR/repo-c" "https://github.com/example/alpha/$DISC_A.git"
PATH_C=$(resolve "$TEST_TMPDIR/repo-c")
assert_ne "an identity that spells another key's prefix still gets its own file" "$PATH_A" "$PATH_C"
# repo-c's directory nests one level BELOW repo-a's, so neither file is shadowed.
assert_contains "the ambiguous identity nests rather than colliding" "$PATH_C" \
  "/reports/github.com/example/alpha/$DISC_A/"

# --- Case group 5: no remote, and not a repository at all ---
make_repo "$TEST_TMPDIR/repo-noremote"
PATH_NR=$(resolve "$TEST_TMPDIR/repo-noremote")
assert_contains "a repository with no remote keys on the local rung" "$PATH_NR" "/reports/local/"
mkdir -p "$TEST_TMPDIR/plain-dir"
PATH_PD=$(cd "$TEST_TMPDIR/plain-dir" && CLAUDE_PLUGIN_DATA="$DATA" GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" --date "$DATE" 2>/dev/null)
assert_contains "a non-repository keys on the nonrepo rung" "$PATH_PD" "/reports/nonrepo/"

# --- Case group 6: the unkeyed leftover is named, never served ---
mkdir -p "$DATA/reports"
LEGACY="$DATA/reports/claude-observability-$DATE.md"
printf 'stale report from an unknown project\n' >"$LEGACY"
STDERR_OUT=$( (cd "$TEST_TMPDIR/repo-a" && CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "$DATE" >/dev/null) 2>&1)
assert_contains "an unkeyed leftover is named on stderr" "$STDERR_OUT" "$LEGACY"
PATH_A_WITH_LEGACY=$(resolve "$TEST_TMPDIR/repo-a")
assert_eq "the leftover does not become the resolved path" "$PATH_A" "$PATH_A_WITH_LEGACY"
assert_ne "the resolved path is not the unkeyed path" "$LEGACY" "$PATH_A_WITH_LEGACY"
rm -f "$LEGACY"

# --- Case group 7: --mkdir creates the parent, and only the parent ---
OUT_M=$(resolve "$TEST_TMPDIR/repo-b" --mkdir)
if [[ -d "$(dirname "$OUT_M")" ]]; then pass "--mkdir creates the keyed parent directory"; else fail "--mkdir creates the keyed parent directory" "directory" "absent"; fi
if [[ ! -e "$OUT_M" ]]; then pass "--mkdir does not create the report file itself"; else fail "--mkdir does not create the report file itself" "absent" "present"; fi

# --- Case group 8: fail closed when the state key cannot be derived ---
# A copy of the script in a fake plugin tree whose lib/state-key.sh fails. The
# script resolves its plugin root from its own location, so this exercises the
# real failure path without breaking PATH.
FAKE="$TEST_TMPDIR/fake-plugin"
mkdir -p "$FAKE/lib" "$FAKE/skills/observability/scripts"
cp "$SCRIPT" "$FAKE/skills/observability/scripts/report-path.sh"
printf '#!/usr/bin/env bash\necho "ERROR: no hash tool" >&2\nexit 2\n' >"$FAKE/lib/state-key.sh"
OUT_F=$( (cd "$TEST_TMPDIR/repo-a" && CLAUDE_PLUGIN_DATA="$DATA" bash "$FAKE/skills/observability/scripts/report-path.sh" --date "$DATE") 2>&1)
RC=$?
assert_exit "an underivable state key exits 2" 2 "$RC"
assert_not_contains "an underivable state key prints no unkeyed path" "$OUT_F" "$DATA/reports/claude-observability"

# --- Case group 9: --date is validated as a filename component ---
OUT_D=$( (cd "$TEST_TMPDIR/repo-a" && CLAUDE_PLUGIN_DATA="$DATA" bash "$SCRIPT" --date "../../../etc/passwd") 2>&1)
RC=$?
assert_exit "a traversal --date is refused" 2 "$RC"
assert_contains "the refusal names the offending value" "$OUT_D" "YYYY-MM-DD"

[[ $FAILED -eq 0 ]] || exit 1
echo "All cases passed ($CASE_NUM)."
