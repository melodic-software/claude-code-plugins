#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TESTS_LIB=""
for candidate in \
  "${WIT_SEAM_TESTS_DIR:-}/lib.sh" \
  "${WIT_SEAM_LIB_DIR:-}/../tests/lib.sh" \
  "$SCRIPT_DIR/../../tests/lib.sh"; do
  if [[ -f "$candidate" ]]; then
    TESTS_LIB="$candidate"
    break
  fi
done
if [[ -z "$TESTS_LIB" ]]; then
  echo "SKIP: seam test helper not found — set WIT_SEAM_TESTS_DIR to the work-item-tracker tests/ directory" >&2
  exit 0
fi
# shellcheck source=/dev/null
source "$TESTS_LIB"

S="$SCRIPT_DIR/capabilities.sh"
MANIFEST="$SCRIPT_DIR/capabilities.json"

out="$(bash "$S" --help 2>/dev/null)"
assert_eq "--help exit 0" "0" "$?"
assert_contains "--help mentions the manifest" "$out" "capabilities.json"

bash "$S" --nope >/dev/null 2>&1
assert_eq "unexpected argument → exit 2" "2" "$?"

out="$(bash "$S" 2>/dev/null)"
assert_eq "capabilities exit 0 with no binding configured" "0" "$?"
case "$out" in
*$'\r'*) fail "stdout is CR-free" "no CR" "CR present" ;;
*) pass "stdout is CR-free" ;;
esac

assert_eq "manifest is valid JSON" "0" "$(
  jq -e . "$MANIFEST" >/dev/null 2>&1
  echo $?
)"
assert_eq "the verb emits the manifest's provider" "gitea" "$(jq -r '.provider' <<<"$out")"
assert_eq "declares a MAJOR.MINOR schema_version" "true" \
  "$(jq -r '.schema_version | test("^[0-9]+\\.[0-9]+$")' <<<"$out")"

assert_eq "capabilities is declared true" "true" "$(jq -r '.verbs["capabilities"]' <<<"$out")"

for v in create-item get-item claim renew-lease release reclaim link-blocks add-sub-item \
  list-items list-sub-items capabilities; do
  assert_eq "verbs[\"$v\"] is boolean" "boolean" "$(jq -r --arg v "$v" '.verbs[$v] | type' <<<"$out")"
done

for k in sub_items_per_parent sub_item_depth dependencies_per_type list_items_max; do
  assert_eq "limits[\"$k\"] is an integer or null" "ok" \
    "$(jq -r --arg k "$k" '.limits[$k] | if . == null then "ok" elif (type == "number" and . >= 0 and floor == .) then "ok" else "bad" end' <<<"$out")"
done

while IFS= read -r v; do
  [[ "$v" == "capabilities" ]] && continue
  declared="$(jq -r --arg v "$v" '.verbs[$v]' <<<"$out")"
  if [[ "$declared" == "true" ]]; then
    if [[ -f "$SCRIPT_DIR/$v.sh" ]]; then
      pass "declared verb $v has a script"
    else
      fail "declared verb $v has a script" "$v.sh present" "missing"
    fi
  else
    if [[ -e "$SCRIPT_DIR/$v.sh" ]]; then
      fail "undeclared verb $v has no script" "$v.sh absent" "present"
    else
      pass "undeclared verb $v has no script"
    fi
  fi
done < <(jq -r '.verbs | keys[]' <<<"$out" | tr -d '\r')

[[ $FAILED -eq 0 ]] || exit 1
