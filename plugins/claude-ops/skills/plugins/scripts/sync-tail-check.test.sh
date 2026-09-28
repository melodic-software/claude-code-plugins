#!/usr/bin/env bash
# Contract tests for sync-tail-check.sh. Network is not used.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/sync-tail-check.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq required" >&2
  exit 0
fi

chmod +x "$SUT"

# --- permissions: absent file, exact rule, broader rule, no write ----------
MISS="$TEST_TMPDIR/missing-settings.json"
OUT="$(bash "$SUT" --check-permissions --settings "$MISS")"
assert_exit "missing settings is a finding" 1 "$?"
assert_contains "missing settings names the rule" "$OUT" "status: absent"
assert_contains "missing settings prints a seed" "$OUT" 'Bash(gh pr merge *)'
if [[ -e "$MISS" ]]; then fail "missing settings was created" "$MISS"; else pass "missing settings was not created"; fi

EXACT="$TEST_TMPDIR/exact.json"
printf '%s\n' '{"permissions":{"allow":["Bash(gh pr view *)","Bash(gh pr merge *)"]}}' >"$EXACT"
BEFORE="$(cksum "$EXACT")"
OUT="$(bash "$SUT" --check-permissions --settings "$EXACT")"
assert_exit "exact rule is clean" 0 "$?"
assert_contains "exact rule status" "$OUT" "status: present-exact"
assert_eq "exact settings bytes unchanged" "$BEFORE" "$(cksum "$EXACT")"

COLON="$TEST_TMPDIR/colon.json"
printf '%s\n' '{"permissions":{"allow":["Bash(gh pr merge:*)"]}}' >"$COLON"
OUT="$(bash "$SUT" --check-permissions --settings "$COLON")"
assert_exit "colon form counts as the exact grant" 0 "$?"
assert_contains "colon form status" "$OUT" "status: present-exact"

BROAD="$TEST_TMPDIR/broad.json"
printf '%s\n' '{"permissions":{"allow":["Bash(gh pr merge*)"]}}' >"$BROAD"
OUT="$(bash "$SUT" --check-permissions --settings "$BROAD")"
assert_exit "broader merge rule is clean" 0 "$?"
assert_contains "broader rule status" "$OUT" "status: present-broader"

NONE="$TEST_TMPDIR/none.json"
printf '%s\n' '{"permissions":{"allow":["Bash(gh pr merge --auto *)"]}}' >"$NONE"
BEFORE="$(cksum "$NONE")"
OUT="$(bash "$SUT" --check-permissions --settings "$NONE")"
assert_exit "auto-only rule is still absent" 1 "$?"
assert_contains "auto-only stays absent" "$OUT" "status: absent"
assert_eq "absent settings bytes unchanged" "$BEFORE" "$(cksum "$NONE")"

# --- orphan sweep -----------------------------------------------------------
CACHE="$TEST_TMPDIR/cache"
KNOWN="$TEST_TMPDIR/known.json"
printf '%s\n' '{"kept":{"source":{"source":"github","repo":"x"}}}' >"$KNOWN"
mkdir -p "$CACHE/kept/plugin/1.0.0" "$CACHE/gone/plugin/0.0.1" "$CACHE/old/plugin/0.0.1" "$CACHE/bare/plugin/0.0.1"
NOW="$(date +%s)"
printf '%s' "$(((NOW - 2 * 86400) * 1000))" >"$CACHE/gone/plugin/0.0.1/.orphaned_at"
printf '%s' "$(((NOW - 10 * 86400) * 1000))" >"$CACHE/old/plugin/0.0.1/.orphaned_at"

OUT="$(bash "$SUT" --check-orphan --cache "$CACHE" --known "$KNOWN")"
assert_exit "unmarked residue is actionable" 1 "$?"
assert_contains "pending marker is not overdue" "$OUT" "removed-marketplace gone tree=present"
assert_contains "pending word" "$OUT" "sweep=pending"
assert_contains "split window is named" "$OUT" "removed-marketplace old"
assert_contains "split word" "$OUT" "sweep=split"
assert_contains "unmarked tree is named" "$OUT" "removed-marketplace bare tree=present marker=missing sweep=unmarked"
assert_contains "installed marketplace is skipped" "$OUT" "status: actionable"
if printf '%s' "$OUT" | grep -q 'removed-marketplace kept'; then
  fail "installed marketplace was reported" "$OUT"
else
  pass "installed marketplace was not reported"
fi

OUT="$(bash "$SUT" --check-orphan --cache "$CACHE" --known "$KNOWN" --marketplace wiped)"
assert_exit "a missing named tree is unobserved, not a sweep" 0 "$?"
assert_contains "absent tree reason" "$OUT" "removed-marketplace wiped tree=absent reason=unobserved"

OVER="$TEST_TMPDIR/over"
mkdir -p "$OVER/cache/stale/plugin/0.0.1"
printf '%s' "$(((NOW - 20 * 86400) * 1000))" >"$OVER/cache/stale/plugin/0.0.1/.orphaned_at"
printf '%s\n' '{}' >"$OVER/known.json"
OUT="$(bash "$SUT" --check-orphan --cache "$OVER/cache" --known "$OVER/known.json")"
assert_exit "overdue marker is actionable" 1 "$?"
assert_contains "overdue word" "$OUT" "sweep=overdue"

# --- drift fixture ----------------------------------------------------------
FIX="$TEST_TMPDIR/fix"
mkdir -p "$FIX/cited"
printf '%s\n' 'github-iac' >"$FIX/targets.txt"
printf '%s\n' 'See .github/workflows/release-tag-drift-check.yml and its tracking issue.' >"$FIX/release.yml"
printf '%s\n' 'PUBLISHED Releases are the source.' >>"$FIX/release.yml"
: >"$FIX/cited/release-tag-drift-check.yml.missing"
printf '%s\n' 'This repository is v0.7.0 at the time of writing' >"$FIX/readme.txt"
printf '%s\n' 'v0.29.1' >"$FIX/latest.txt"
printf '%s\n' 'the standards-sync label keeps sync pull requests green' >"$FIX/acceptance.md"
printf '%s\n' 'ignore:' >"$FIX/github-iac.yml"
printf '%s\n' 'uses: actions/checkout@abc' >"$FIX/guard.yml"
OUT="$(bash "$SUT" --check-drift --fixture "$FIX")"
assert_exit "open drift items are actionable" 1 "$?"
assert_contains "account-rotation target missing" "$OUT" "a status=open"
assert_contains "cited workflow missing" "$OUT" "b status=open"
assert_contains "readme version mismatch" "$OUT" "c status=open"
assert_contains "acceptance bullet gap" "$OUT" "d status=open"
assert_contains "dependabot ignore gap" "$OUT" "e status=open"
assert_contains "published-release header is clear" "$OUT" "f status=clear"
assert_contains "upstream hook stays unprobed" "$OUT" "g status=unprobed"
assert_contains "checkout still waiting" "$OUT" "h status=waiting-on-release"

CLEAN="$TEST_TMPDIR/clean-fix"
mkdir -p "$CLEAN/cited"
printf '%s\n' 'account-rotation' 'github-iac' >"$CLEAN/targets.txt"
printf '%s\n' 'The next version is the highest SemVer among PUBLISHED Releases.' >"$CLEAN/release.yml"
printf '%s\n' 'This repository is v0.29.1 today' >"$CLEAN/readme.txt"
printf '%s\n' 'v0.29.1' >"$CLEAN/latest.txt"
printf '%s\n' 'the dependabot[bot] arm keeps those pulls green' >"$CLEAN/acceptance.md"
printf '%s\n' 'melodic-software/ci-workflows/*' >"$CLEAN/github-iac.yml"
printf '%s\n' 'uses: melodic-software/ci-workflows/.github/actions/example@abc' >"$CLEAN/guard.yml"
OUT="$(bash "$SUT" --check-drift --fixture "$CLEAN")"
assert_exit "a clean fixture is not actionable" 0 "$?"
assert_contains "clean fixture says so" "$OUT" "status: clean"

OUT="$(bash "$SUT" --check-drift --offline)"
assert_exit "offline drift check does not fetch" 0 "$?"
assert_contains "offline names account-rotation" "$OUT" "a status=unprobed"
assert_contains "offline status" "$OUT" "status: offline"

OUT="$(bash "$SUT" 2>&1)"
assert_exit "no mode is usage" 2 "$?"
assert_contains "usage names the modes" "$OUT" "--check-permissions"

if [[ "$FAILED" -eq 0 ]]; then
  echo "all sync-tail-check contract tests passed"
  exit 0
fi
echo "$FAILED sync-tail-check contract test(s) failed" >&2
exit 1
