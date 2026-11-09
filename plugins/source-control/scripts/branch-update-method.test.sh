#!/usr/bin/env bash
# Regression tests for branch-update-method.sh, black-box over stdin and stdout.
# Every expected method and rule is written by hand, never read back from the script.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$SCRIPT_DIR/branch-update-method.sh"
DOC="$SCRIPT_DIR/../reference/branch-update-criteria.md"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

# Reaches keeps-commits; each case flips only the signals it is about.
BASE='{"head_sha":"abc123","setting":"auto","setting_level":"default","behind":"yes","conflict":"no","up_to_date_required":"yes","base_change_needed":"no","native_stack":"no","managed_head":"no","rewrite":"allowed","other_authors":"no","dependents":"no","base_merged":"no","human_review":"no","landing":"keeps-commits"}'
TRI_STATE="behind conflict up_to_date_required base_change_needed native_stack managed_head other_authors dependents base_merged human_review"
OTHER_SIGNALS="head_sha setting setting_level rewrite landing"
COVERED=""

signals() {
  local args=(-c) pair
  for pair in "$@"; do args+=(--arg "${pair%%=*}" "${pair#*=}"); done
  jq "${args[@]}" '. + $ARGS.named' <<<"$BASE"
}

decide() {
  DECISION="$(signals "$@" | bash "$ENGINE")"
  RC=$?
}

field() { jq -r "$1" <<<"$DECISION" | tr -d '\r'; }

assert_decision() {
  local label="$1" method="$2" rule="$3"
  assert_exit "$label: exit" 0 "$RC"
  assert_eq "$label: method" "$method" "$(field .method)"
  assert_eq "$label: rule" "$rule" "$(field .rule)"
  assert_eq "$label: reason present" "true" "$(field '.reason | type == "string" and length > 0')"
  COVERED+="$rule"$'\n'
}

# check <label> <method> <rule> [signal=value ...]
check() {
  local label="$1" method="$2" rule="$3"
  shift 3
  decide "$@"
  assert_decision "$label" "$method" "$rule"
}

# check_setting <label> <setting> <method> <rule> <applied> [signal=value ...]
check_setting() {
  local label="$1" setting="$2" method="$3" rule="$4" applied="$5"
  shift 5
  decide "setting=$setting" "$@"
  assert_decision "$label" "$method" "$rule"
  assert_eq "$label: applied" "$applied" "$(field .setting.applied)"
}

# malformed <label> <stdin>
malformed() {
  local out rc
  out="$(printf '%s' "$2" | bash "$ENGINE" 2>/dev/null)"
  rc=$?
  assert_exit "$1: exit" 2 "$rc"
  assert_silent "$1: stdout" "$out"
}

check "fixture" rebase keeps-commits

check "head holds the base tip" none no-update-needed behind=no
check "head holds the base tip outranks an unknown stack" none no-update-needed behind=no native_stack=unknown
check "nothing calls for an update" none no-update-needed up_to_date_required=no
check "a conflict calls for an update" rebase keeps-commits up_to_date_required=no conflict=yes
check "a needed base change calls for an update" rebase keeps-commits up_to_date_required=no base_change_needed=yes
check "unknown base change does not match" rebase keeps-commits up_to_date_required=no base_change_needed=unknown
check "unknown conflict does not match" rebase keeps-commits up_to_date_required=no conflict=unknown
check "unknown up-to-date requirement does not match" rebase keeps-commits up_to_date_required=unknown
check "unknown behind does not match" rebase keeps-commits behind=unknown
check "a stack member is never skipped by the second clause" rebase native-stack up_to_date_required=no native_stack=yes
check "an unknown stack is never skipped by the second clause" hold safety-unknown up_to_date_required=no native_stack=unknown

check "unknown stack" hold safety-unknown native_stack=unknown
check "unknown manager" hold safety-unknown managed_head=unknown
check "unknown manager outranks a known stack" hold safety-unknown managed_head=unknown native_stack=yes

check "manager owns the head" delegate managed-head managed_head=yes
check "manager outranks a stack" delegate managed-head managed_head=yes native_stack=yes
check "manager outranks other authors" delegate managed-head managed_head=yes other_authors=yes

check "stack member" rebase native-stack native_stack=yes
check "a stack member has dependents by design" rebase native-stack native_stack=yes dependents=yes

check "stack, rewrite blocked" hold native-stack-blocked native_stack=yes rewrite=blocked
check "stack, other authors" hold native-stack-blocked native_stack=yes other_authors=yes
check "stack, unknown authors" hold native-stack-blocked native_stack=yes other_authors=unknown

check "other authors" merge shared-history other_authors=yes
check "dependents" merge shared-history dependents=yes
check "unknown authors count" merge shared-history other_authors=unknown
check "unknown dependents count" merge shared-history dependents=unknown
check "shared history outranks a blocked rewrite" merge shared-history other_authors=yes rewrite=blocked

check "rewrite blocked" merge no-rewrite rewrite=blocked
check "blocked rewrite outranks a base merge" merge no-rewrite rewrite=blocked base_merged=yes

check "base already merged" merge base-merged base_merged=yes
check "base merge outranks review" merge base-merged base_merged=yes human_review=yes
check "unknown base merge counts" merge base-merged base_merged=unknown

check "human review" merge human-reviewed human_review=yes
check "review outranks squash" merge human-reviewed human_review=yes landing=squash

check "squash landing" merge squash-landing landing=squash
check "unknown review does not match" merge squash-landing human_review=unknown landing=squash

check "unknown landing" merge default-merge landing=unknown
check "unknown review cannot reach keeps-commits" merge default-merge human_review=unknown

check_setting "forced rebase, unknown authors" rebase merge shared-history false other_authors=unknown
check_setting "forced rebase, unknown stack" rebase hold safety-unknown false native_stack=unknown
check_setting "forced rebase, unknown base merge" rebase merge base-merged false base_merged=unknown

while read -r -a row; do
  for forced in merge rebase; do
    check_setting "forced $forced leaves ${row[0]} (${row[*]:2})" "$forced" "${row[1]}" "${row[0]}" false "${row[@]:2}"
  done
done <<'ROWS'
no-update-needed none behind=no
no-update-needed none up_to_date_required=no
safety-unknown hold managed_head=unknown
managed-head delegate managed_head=yes
native-stack rebase native_stack=yes
native-stack-blocked hold native_stack=yes rewrite=blocked
shared-history merge other_authors=yes
shared-history merge dependents=unknown
no-rewrite merge rewrite=blocked
base-merged merge base_merged=yes
ROWS

while read -r -a row; do
  for forced in merge rebase; do
    check_setting "forced $forced decides ${row[0]}" "$forced" "$forced" "${row[0]}" true "${row[@]:1}"
  done
done <<'ROWS'
human-reviewed human_review=yes
squash-landing landing=squash
keeps-commits
default-merge landing=unknown
ROWS

check_setting "auto never applies on a forceable row" auto merge squash-landing false landing=squash

decide setting=rebase setting_level=repository head_sha=feedface landing=squash
assert_eq "head_sha echoed" "feedface" "$(field .head_sha)"
assert_eq "setting value echoed" "rebase" "$(field .setting.value)"
assert_eq "setting level echoed" "repository" "$(field .setting.level)"
assert_contains "reason names the forced value when applied" "$(field .reason)" "rebase"
decide landing=squash
assert_not_contains "reason names no forced value under auto" "$(field .reason)" "pr_update_method"

decide human_review=yes
assert_eq "human_review yes is carried on a merge" "merge yes" "$(field '"\(.method) \(.human_review)"')"
decide
assert_eq "human_review no is carried on a rebase" "rebase no" "$(field '"\(.method) \(.human_review)"')"
decide human_review=yes setting=rebase
assert_eq "human_review yes is carried on a forced rebase" "rebase yes" "$(field '"\(.method) \(.human_review)"')"
decide human_review=yes behind=no
assert_eq "human_review is carried when no update is needed" "none yes" "$(field '"\(.method) \(.human_review)"')"
decide human_review=unknown landing=squash
assert_eq "human_review unknown is carried" "unknown" "$(field .human_review)"

for signal in $TRI_STATE landing; do
  decide "$signal=unknown"
  assert_eq "unknown lists $signal" "$signal" "$(field '.unknown | join(",")')"
done
decide other_authors=unknown landing=unknown
assert_eq "unknown lists every unknown signal" "landing,other_authors" "$(field '.unknown | sort | join(",")')"
decide head_sha=unknown setting_level=unknown
assert_eq "free-text signals are never listed as unknown" "" "$(field '.unknown | join(",")')"

assert_eq "the signal lists name every key of the fixture" \
  "$(jq -r 'keys_unsorted[]' <<<"$BASE" | tr -d '\r' | sort)" \
  "$(tr ' ' '\n' <<<"$TRI_STATE $OTHER_SIGNALS" | sort)"

malformed "non-JSON" 'not json'
malformed "empty stdin" ''
malformed "array" '[]'
malformed "scalar" '"yes"'
malformed "two documents" "$BASE$BASE"
for signal in $TRI_STATE $OTHER_SIGNALS; do
  malformed "missing $signal" "$(jq -c "del(.$signal)" <<<"$BASE")"
done
for signal in $TRI_STATE; do
  malformed "$signal out of range" "$(signals "$signal=maybe")"
done
malformed "boolean tri-state" "$(jq -c '.behind = true' <<<"$BASE")"
malformed "setting out of range" "$(signals setting=squash)"
malformed "setting cannot be unknown" "$(signals setting=unknown)"
malformed "rewrite out of range" "$(signals rewrite=maybe)"
malformed "rewrite cannot be unknown" "$(signals rewrite=unknown)"
malformed "landing out of range" "$(signals landing=merge)"
malformed "empty head_sha" "$(signals head_sha=)"
malformed "empty setting_level" "$(signals setting_level=)"
malformed "numeric head_sha" "$(jq -c '.head_sha = 7' <<<"$BASE")"

out="$(bash "$ENGINE" --no-such-flag </dev/null 2>/dev/null)"
assert_exit "unknown flag: exit" 2 "$?"
assert_silent "unknown flag: stdout" "$out"

script_rows="$(bash "$ENGINE" --rows | tr -d '\r' | sort)"
doc_rows="$(sed -n "s/^### \`\([a-z-]*\)\`\$/\1/p" "$DOC" | tr -d '\r' | sort)"
assert_eq "criteria doc and script hold the same row ids" "$script_rows" "$doc_rows"
assert_eq "every script row has a case" "$script_rows" "$(printf '%s' "$COVERED" | sort -u)"

[[ $FAILED -eq 0 ]] || exit 1
