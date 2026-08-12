#!/usr/bin/env bash
# Regression tests for managed-conformance.sh (self-contained — ships with the plugin).
#
# Every case feeds hand-written reader records on stdin. No test reads the
# operator's real ~/.claude, and none touches the machine's real managed policy
# — deploying policy to a developer's machine to test a report about policy
# would change every session's permission behavior on that machine.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/managed-conformance.sh"

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
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
count_matching() { printf '%s\n' "$1" | grep -cE "$2"; }

report() { printf '%s\n' "$1" | bash "$SCRIPT"; }

# --- The phase's own sanity check: one deny, one autoMode rule ---------------
# The deny is enforced; the autoMode section is loosenable. Getting this pair
# backwards is the failure an administrator would act on.
FIXTURE=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
project settings present /proj/.claude/settings.json
conf managed file autoModePresent true
rule managed file deny Read(./.env)
rule user settings allow Bash(npm test)
EOF
)
OUT=$(report "$FIXTURE")
assert_contains "a managed deny is reported enforced" "$OUT" "managed enforced deny Read(./.env)"
assert_contains "a managed autoMode section is reported loosenable" "$OUT" "managed loosenable autoMode"
assert_contains "and the loosenable finding names the remedy" "$OUT" "use permissions.deny in managed settings"
assert_contains "the summary counts both sides" "$OUT" "enforced=1 loosenable=1"

# --- Lane neutrality, asserted as a POSITIVE property -------------------------
# Every rule string in the report must appear in the input. Asserting the
# absence of some marker string would pass unconditionally and prove nothing.
NEUTRAL=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
rule managed file deny Read(./.env)
rule managed file deny WebFetch
rule managed file allow Bash(git status)
rule user settings allow Bash(npm test)
EOF
)
OUT=$(report "$NEUTRAL")
leaked=0
while IFS= read -r line; do
  case "$line" in
  "managed enforced deny "*)
    rule="${line#managed enforced deny }"
    printf '%s\n' "$NEUTRAL" | grep -qF -- "$rule" || {
      leaked=1
      printf '  leaked rule not present in input: %s\n' "$rule" >&2
    }
    ;;
  *) ;;
  esac
done < <(printf '%s\n' "$OUT")
assert_eq "every rule the report prints came from a file it read" 0 "$leaked"
assert_not_contains "the report never prescribes a rule to add" "$OUT" "should contain"
assert_not_contains "nor recommends one" "$OUT" "recommend"

# --- Managed is highest, but it is not evaluated first ------------------------
# "Managed settings highest" and "deny before ask before allow, from any scope"
# are both true, and their interaction is the thing an administrator would not
# expect: a lower-scope deny beats a managed allow without overriding it.
OUTRANKED=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
rule managed file allow Bash(npm test)
rule user settings deny Bash(npm test)
EOF
)
OUT=$(report "$OUTRANKED")
assert_contains "a managed allow beaten by a lower deny is loosenable" "$OUT" "managed loosenable rule the managed allow rule Bash(npm test)"
assert_contains "the finding names the scope that beat it" "$OUT" "in scope(s) user"
assert_contains "and cites the mechanic rather than asserting it" "$OUT" "evaluation order (deny, then ask, then allow)"
assert_not_contains "it is not also reported enforced" "$OUT" "managed enforced allow Bash(npm test)"

# A managed ask beaten by a lower deny is the same shape.
ASK_BEATEN=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
project settings present /proj/.claude/settings.json
rule managed file ask WebFetch
rule project settings deny WebFetch
EOF
)
OUT=$(report "$ASK_BEATEN")
assert_contains "a managed ask beaten by a lower deny is loosenable" "$OUT" "managed loosenable rule the managed ask rule WebFetch"

# An unbeaten managed allow IS enforced — nothing below it changes the outcome.
UNBEATEN=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
rule managed file allow Bash(git status)
rule user settings allow Bash(npm test)
EOF
)
OUT=$(report "$UNBEATEN")
assert_contains "an unbeaten managed allow is enforced" "$OUT" "managed enforced allow Bash(git status)"

# A managed deny is never loosenable, whatever a lower scope says.
DENY_CHALLENGED=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
user settings present /fx/home/.claude/settings.json
rule managed file deny Read(./.env)
rule user settings allow Read(./.env)
EOF
)
OUT=$(report "$DENY_CHALLENGED")
assert_contains "a managed deny stays enforced against a lower allow" "$OUT" "managed enforced deny Read(./.env)"
assert_eq "and nothing about it is called loosenable" 0 "$(count_matching "$OUT" 'loosenable rule.*Read')"

# --- The lock-out switch, at both key paths ----------------------------------
LOCKED=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
conf managed file disableAutoMode "disable"
EOF
)
OUT=$(report "$LOCKED")
assert_contains "a correctly-typed lock-out is enforced" "$OUT" "managed enforced lockout disableAutoMode"

MISTYPED=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
conf managed file permissions.disableAutoMode true
EOF
)
OUT=$(report "$MISTYPED")
assert_contains "a mistyped lock-out is loosenable, not enforced" "$OUT" "managed loosenable lockout permissions.disableAutoMode"
assert_contains "and says plainly that auto mode is not disabled" "$OUT" "auto mode is NOT disabled"

# --- Completeness bounds every claim -----------------------------------------
# An administrator reading silence as "no policy deployed" is the failure this
# report exists to prevent, so it never stays quiet about what it could not read.
UNREAD=$(
  cat <<'EOF'
managed file present /policy/managed-settings.json
managed registry skipped -
managed plist unreadable com.anthropic.claudecode
rule managed file deny Read(./.env)
EOF
)
OUT=$(report "$UNREAD")
assert_eq "one note per surface that could not be read" 2 "$(count_matching "$OUT" 'MANAGED-NOTE: the managed surface')"
assert_contains "an unread surface is not evidence of absence" "$OUT" "not evidence that no policy is deployed"
assert_contains "server-managed settings are disclosed on every run" "$OUT" "no local path"

# No local policy at all is stated, not implied by an empty report.
NO_POLICY=$(
  cat <<'EOF'
managed file absent /policy/managed-settings.json
managed dropin-dir absent /policy/managed-settings.d
managed registry not-applicable -
managed plist not-applicable -
user settings present /fx/home/.claude/settings.json
rule user settings allow Bash(npm test)
EOF
)
OUT=$(report "$NO_POLICY")
assert_contains "no local policy is stated explicitly" "$OUT" "status=no-local-policy"
assert_eq "and no conformance claim is made" 0 "$(count_matching "$OUT" '^managed enforced')"

# --- A CORRUPT managed policy is not an absent one ---------------------------
# invalid-json means a policy exists and could not be read. Reporting that as
# "no local policy" is the single worst answer this report can give an
# administrator, and the merge already grouped the three statuses correctly.
CORRUPT=$(
  cat <<'EOF'
managed file invalid-json /policy/managed-settings.json
managed dropin-dir absent /policy/managed-settings.d
managed registry not-applicable -
managed plist not-applicable -
user settings present /fx/home/.claude/settings.json
rule user settings allow Bash(npm test)
EOF
)
OUT=$(report "$CORRUPT")
assert_contains "a corrupt managed file is reported unread" "$OUT" "the managed surface file (invalid-json) was NOT read"
assert_contains "and the status says incomplete, not absent" "$OUT" "status=incomplete"
assert_contains "and explicitly not as absence of policy" "$OUT" "not evidence that no policy is deployed"
assert_not_contains "it is never reported as no local policy" "$OUT" "status=no-local-policy"

# --- Fail-loud ----------------------------------------------------------------
rc=0
err=$(printf '' | bash "$SCRIPT" 2>&1) || rc=$?
assert_exit "exit 2 on empty input" 2 "$rc"
assert_contains "the error refuses to report on an unread policy" "$err" "never read"

rc=0
err=$(bash "$SCRIPT" --bogus </dev/null 2>&1) || rc=$?
assert_exit "exit 2 on an unknown argument" 2 "$rc"

rc=0
help=$(bash "$SCRIPT" --help </dev/null 2>&1) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help states the read-only construction" "$help" "read-only by construction"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
