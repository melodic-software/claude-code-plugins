#!/usr/bin/env bash
# Offline tests for delivery-metrics.sh over a fixture repository of merges and
# reverts with fixed author and committer dates. Each expected value is worked
# out by hand from the fixture below, in hours from T0 (Monday 2026-01-05 UTC).
#
#   deploy  author  landed   lead  reverted by (landed)       recovery
#   A merge 0       10       10    R3, a commit A merged (216) 206
#   B       24      28       4     R4, after the window (360)  332
#   C merge 48      54       6     R1, `This reverts` (56)     2
#   R1      55      56       1
#   D       168     170      2
#   E       192     195      3     R2, subject only (204)      9
#   R2      201     204      3
#   R3      216     216      0
#   R4      360     360      (after --until, not reported)
#
# Week 2026-01-05: 4 deployments, lead median 5, fail rate 3/4, recovery median
# 206, rework 1/4. Week 2026-01-12: 4 deployments, lead median 2.5, fail rate
# 1/4, recovery 9, rework 2/4. Window: 8 deployments over 14 days (4 a week),
# lead median 3, fail rate 4/8, recovery median 107.5, rework 3/8.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE

S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/delivery-metrics.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILED=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$*" >&2
}

for tool in git jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not installed" >&2
    exit 0
  }
done

export GIT_AUTHOR_NAME="Ada Lovelace" GIT_AUTHOR_EMAIL="ada@person.example"
export GIT_COMMITTER_NAME="Grace Hopper" GIT_COMMITTER_EMAIL="grace@person.example"
R="$TMP/repo"
H=3600
T0=1767571200

g() { git -C "$R" -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"; }
# at <author-hours> <committer-hours> <git args...>: run git with both dates fixed.
at() {
  local a=$((T0 + $1 * H)) c=$((T0 + $2 * H))
  shift 2
  GIT_AUTHOR_DATE="$a +0000" GIT_COMMITTER_DATE="$c +0000" g "$@" >/dev/null || {
    echo "fixture: git $* failed" >&2
    exit 1
  }
}
# change <author-hours> <committer-hours> <file> <subject>: commit one new file.
change() {
  printf '%s\n' "$3" >"$R/$3"
  g add -- "$3"
  at "$1" "$2" commit -q -m "$4"
}
sha() { g rev-parse "$1"; }

mkdir -p "$R"
git init -q -b main "$R"
change -240 -240 root.txt "chore: root"

g checkout -q -b feat-a
change 0 0 a1.txt "feat: a1"
change 2 2 a2.txt "feat: a2"
A2="$(sha HEAD)"
g checkout -q main
at 10 10 merge -q --no-ff --no-edit feat-a

change 24 28 b.txt "fix: b"
B="$(sha HEAD)"

g checkout -q -b feat-c
change 48 48 c1.txt "feat: c1"
g checkout -q main
at 54 54 merge -q --no-ff --no-edit feat-c
at 55 56 revert --no-edit -m 1 HEAD

change 168 170 d.txt "feat: d"
change 192 195 e.txt "feat: e"
g rm -q -- e.txt
at 201 204 commit -q -m 'Revert "feat: e"'
at 216 216 revert --no-edit "$A2"
at 360 360 revert --no-edit "$B"

# Week 2026-02-02: F (lead 0) is reverted by a commit on a branch (authored at
# 673) that lands through a merge at 677 (lead 4): recovery 5, fail rate 1/2,
# rework 1/2.
change 672 672 f.txt "feat: f"
F="$(sha HEAD)"
g checkout -q -b revert-f
at 673 673 revert --no-edit "$F"
g checkout -q main
at 677 677 merge -q --no-ff --no-edit revert-f

run() { bash "$S" --repo "$R" --branch main --since 2026-01-05 --until 2026-01-18 "$@"; }

if OUT="$(run)"; then
  pass "report exits 0"
else
  fail "report exited non-zero"
  OUT='{}'
fi

expect() { # <name> <jq filter> <expected compact JSON>
  local got
  got="$(jq -c "$2" <<<"$OUT" 2>&1)"
  if [[ "$got" == "$3" ]]; then pass "$1"; else fail "$1: expected $3, got $got"; fi
}

expect "deploy signal" '.deploy_signal' '"merge-to-default-branch"'
expect "window" '[.since, .until]' '["2026-01-05","2026-01-18"]'
expect "deployment frequency: window count" '.totals.deployments' '8'
expect "deployment frequency: per week" '.totals.deployments_per_week' '4'
expect "change lead time: window median" '.totals.change_lead_time_hours_median' '3'
expect "change fail rate: window" '.totals.change_fail_rate' '0.5'
expect "failed deployments: window" '.totals.failed_deployments' '4'
expect "recovery time: window median" '.totals.failed_deployment_recovery_time_hours_median' '107.5'
expect "rework rate: window" '.totals.deployment_rework_rate' '0.375'
expect "trend periods" '[.trend[].period]' '["2026-01-05","2026-01-12"]'
expect "week 1 deployment frequency" '.trend[0].deployments' '4'
expect "week 1 change lead time" '.trend[0].change_lead_time_hours_median' '5'
expect "week 1 change fail rate" '.trend[0].change_fail_rate' '0.75'
expect "week 1 recovery time" '.trend[0].failed_deployment_recovery_time_hours_median' '206'
expect "week 1 rework rate" '.trend[0].deployment_rework_rate' '0.25'
expect "week 2 deployment frequency" '.trend[1].deployments' '4'
expect "week 2 change lead time" '.trend[1].change_lead_time_hours_median' '2.5'
expect "week 2 change fail rate" '.trend[1].change_fail_rate' '0.25'
expect "week 2 recovery time" '.trend[1].failed_deployment_recovery_time_hours_median' '9'
expect "week 2 rework rate" '.trend[1].deployment_rework_rate' '0.5'

if grep -Eqi 'ada|lovelace|grace|hopper|person\.example' <<<"$OUT"; then
  fail "output names a person"
else
  pass "output names no person"
fi

OUT="$(run --bucket month)" || fail "month report exited non-zero"
expect "month bucket: one period" '[.trend[] | {period, deployments}]' '[{"period":"2026-01","deployments":8}]'

OUT="$(bash "$S" --repo "$R" --branch main --since 2026-02-02 --until 2026-02-08)" || fail "merged-revert window exited non-zero"
expect "revert landed through a merge commit" \
  '.totals | [.deployments, .change_lead_time_hours_median, .change_fail_rate, .failed_deployment_recovery_time_hours_median, .deployment_rework_rate]' \
  '[2,2,0.5,5,0.5]'

OUT="$(bash "$S" --repo "$R" --branch main --since 2026-03-02 --until 2026-03-08)" || fail "empty window exited non-zero"
expect "empty window: nothing to measure is null" \
  '[.totals.deployments, .totals.change_lead_time_hours_median, .totals.change_fail_rate]' '[0,null,null]'

# The schema's delivery_deploy_signal must match the script: its default is
# merge-to-default-branch and the script's own default, and the script accepts
# every value the schema lists.
SCHEMA="$(dirname "$S")/../../../schemas/work-items.schema.json"
SCHEMA_DEFAULT="$(jq -r '.properties.delivery_deploy_signal.default // empty' "$SCHEMA" 2>/dev/null)"
if [[ "$SCHEMA_DEFAULT" == merge-to-default-branch ]]; then
  pass "schema: delivery_deploy_signal default"
else
  fail "schema: delivery_deploy_signal default is '$SCHEMA_DEFAULT', expected merge-to-default-branch"
fi
OUT="$(run </dev/null)" || OUT='{}'
expect "schema default is the script's default" '.deploy_signal' "\"$SCHEMA_DEFAULT\""
SIGNALS=0
while IFS= read -r signal; do
  SIGNALS=$((SIGNALS + 1))
  if OUT="$(run --deploy-signal "$signal" </dev/null)" &&
    [[ "$(jq -r '.deploy_signal' <<<"$OUT")" == "$signal" ]]; then
    pass "schema value accepted by the script: $signal"
  else
    fail "schema value not accepted by the script: $signal"
  fi
done < <(jq -r '.properties.delivery_deploy_signal.enum[]?' "$SCHEMA" 2>/dev/null)
((SIGNALS > 0)) || fail "schema: delivery_deploy_signal lists no value"

usage_error() { # <name> <args...>
  local name="$1"
  shift
  bash "$S" "$@" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" == 2 ]]; then pass "usage error: $name"; else fail "usage error: $name exited $rc, expected 2"; fi
}
usage_error "unknown deploy signal" --repo "$R" --branch main --deploy-signal release-tag
usage_error "unknown bucket" --repo "$R" --branch main --bucket day
usage_error "malformed date" --repo "$R" --branch main --since 2026/01/05
usage_error "since after until" --repo "$R" --branch main --since 2026-02-01 --until 2026-01-01
usage_error "unknown branch" --repo "$R" --branch nope
usage_error "no origin/HEAD and no --branch" --repo "$R"
usage_error "argument given twice" --repo "$R" --repo "$R"
usage_error "unknown argument" --repo "$R" --verbose

((FAILED == 0)) || {
  echo "$FAILED failed" >&2
  exit 1
}
echo "all passed"
