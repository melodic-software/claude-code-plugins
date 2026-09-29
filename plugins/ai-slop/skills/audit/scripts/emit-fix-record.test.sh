#!/usr/bin/env bash
# Self-contained tests for emit-fix-record.sh: fixtures are built inline in a
# tmpdir; the "subtracted" checks restate review:fanout's fix-pass-mode.md
# Step 1 rule (a candidate is retired only when a same-branch record names it
# by file name AND the first 12 hex of its own sha256).
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REC="$SCRIPT_DIR/emit-fix-record.sh"
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
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
sha12() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -c1-12; }

# Step 1's subtraction test for one candidate against one record: some
# source-findings entry matches BOTH the candidate's name and its own digest.
subtracted() {
  local cand="$1" rec="$2" name digest
  name="$(basename "$cand")"
  digest="$(sha12 "$cand")"
  awk -v n="$name" -v d="$digest" '
    /^  - name: / { cur = substr($0, 11); next }
    /^    sha256: / { if (cur == n && tolower(substr($0, 13, 12)) == d) hit = 1 }
    END { exit hit ? 0 : 1 }
  ' "$rec"
}

REPO="$TEST_TMPDIR/repo"
HOME_DIR="$REPO/.work/reviews/fix-x"
mkdir -p "$REPO" "$HOME_DIR"
git -C "$REPO" init -q -b fix/x
FA="$HOME_DIR/20260101T000000Z-ai-slop.md"
FB="$HOME_DIR/20260101T000100Z-ai-slop.md"
printf -- '---\ntype: review-findings\ndate: 2026-01-01T00:00:00Z\nbranch: fix/x\n---\n\n## Findings\n\n| a |\n' >"$FA"
printf -- '---\ntype: review-findings\ndate: 2026-01-01T00:01:00Z\nbranch: fix/x\n---\n\n## Findings\n\n| b |\n' >"$FB"

# Case group 1: one consumed file, branch from the current checkout.
R1="$(cd "$REPO" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$FA")"
rc=$?
assert_eq "exit 0 on success" "0" "$rc"
if [[ -f "$R1" ]]; then pass "prints the path of an existing file"; else fail "record exists" "file" "$R1"; fi
assert_eq "record lives in the findings home" "$HOME_DIR" "$(dirname "$R1")"
assert_eq "type is fix-pass-record" "type: fix-pass-record" "$(sed -n 2p "$R1")"
assert_eq "branch is the current branch" "branch: fix/x" "$(sed -n 4p "$R1")"
assert_contains "source-findings is a block sequence" "$(cat "$R1")" "source-findings:
  - name: 20260101T000000Z-ai-slop.md
    sha256: $(sha12 "$FA")"
assert_eq "digest is 12 lowercase hex" "1" "$(grep -cE '^    sha256: [0-9a-f]{12}$' "$R1")"
BASE="$(basename "$R1")"
assert_eq "file name digest equals the record's own digest" "$(sha12 "$R1")" "$(printf '%s' "$BASE" | sed -E 's/.*-fix-pass-applied-([0-9a-f]{12})\.md$/\1/')"
assert_contains "empty Not applied renders (none)" "$(cat "$R1")" "recover by re-running the source producer

(none)"
assert_contains "Consumed line names the file" "$(cat "$R1")" "- Consumed (1 files): 20260101T000000Z-ai-slop.md"
if subtracted "$FA" "$R1"; then pass "consumed file is subtracted (name + digest match)"; else fail "subtraction" "subtracted" "kept"; fi
if subtracted "$FB" "$R1"; then fail "unnamed file stays in the set" "kept" "subtracted"; else pass "unnamed file stays in the set"; fi

# A rewrite under the same name changes the digest, so it is not retired.
cp "$FA" "$TEST_TMPDIR/orig.md"
printf '| new row |\n' >>"$FA"
if subtracted "$FA" "$R1"; then fail "same name, new content stays" "kept" "subtracted"; else pass "same name, new content stays"; fi
cp "$TEST_TMPDIR/orig.md" "$FA"

# Case group 2: two consumed files, Not applied rows, explicit branch, no git.
NA="$TEST_TMPDIR/na.txt"
printf '| a.md:3 | em dash | reverted: meaning loss | 20260101T000000Z-ai-slop.md |\n' >"$NA"
R2="$(cd "$TEST_TMPDIR" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$FA" --consumed "$FB" --branch other/b --rows 7 --outcome '`/ai-slop:audit fix` → 6 fixed, 1 reverted' --not-applied-rows "$NA")"
assert_eq "explicit --branch wins" "branch: other/b" "$(sed -n 4p "$R2")"

# YAML-sensitive branch names are quoted like emit-findings.sh quotes them.
for pair in 'true|"true"' '123|"123"' '#topic|"#topic"' 'a: b|"a: b"'; do
  RB="$(cd "$TEST_TMPDIR" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$FA" --branch "${pair%%|*}")"
  assert_eq "branch ${pair%%|*} is quoted" "branch: ${pair#*|}" "$(sed -n 4p "$RB")"
done
assert_eq "one entry per consumed file" "2" "$(grep -c '^  - name: ' "$R2")"
assert_contains "Not applied table carries the row" "$(cat "$R2")" "| Location | Finding | Why not applied | Source file |"
assert_contains "Not applied row is copied through" "$(cat "$R2")" "reverted: meaning loss"
# shellcheck disable=SC2016
assert_contains "Producer-owned line carries rows and outcome" "$(cat "$R2")" '- Producer-owned (7): `/ai-slop:audit fix` → 6 fixed, 1 reverted'
if subtracted "$FA" "$R2" && subtracted "$FB" "$R2"; then pass "both consumed files match their entries"; else fail "two-file subtraction" "both" "not both"; fi

# Case group 3: a second run never overwrites the first.
sum1="$(sha12 "$R1")"
R3="$(cd "$REPO" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$FA")"
if [[ -f "$R1" && "$(sha12 "$R1")" == "$sum1" ]]; then pass "first record is untouched by a second run"; else fail "first record intact" "$sum1" "changed or gone"; fi
if [[ -f "$R3" ]]; then pass "second run wrote its own record"; else fail "second record exists" "file" "$R3"; fi
assert_eq "no stray staging file in the findings home" "0" "$(find "$HOME_DIR" -name 'tmp.*' | wc -l | tr -d ' ')"

# Case group 4: usage errors.
(cd "$REPO" && bash "$REC" --out-dir "$HOME_DIR" >/dev/null 2>&1)
assert_eq "no --consumed is a usage error" "2" "$?"
(cd "$REPO" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$TEST_TMPDIR/missing.md" >/dev/null 2>&1)
assert_eq "missing consumed file is a usage error" "2" "$?"
(cd "$TEST_TMPDIR" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$FA" >/dev/null 2>&1)
assert_eq "no branch and no git is a usage error" "2" "$?"
(cd "$REPO" && bash "$REC" --out-dir "$HOME_DIR" --consumed "$FA" --rows x >/dev/null 2>&1)
assert_eq "non-numeric --rows is a usage error" "2" "$?"

printf '%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
