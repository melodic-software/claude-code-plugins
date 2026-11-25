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
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

for fn in wit_require_linear_id wit_need_linear_config \
  wit_linear_scope_in_scope wit_linear_token \
  wit_linear_auth_header wit_linear_http \
  wit_linear_require_ok wit_linear_unimplemented \
  wit_help_if_requested; do
  assert_succeeds "common.sh exposes $fn" "declared" "missing" declare -F "$fn"
done

assert_fails "rejects foreign-provider id" "reject" "accepted" \
  wit_require_linear_id "github:o/r#1"
if wit_require_linear_id "linear:acme/ENG#12"; then
  pass "accepts a linear id and sets the WIT_ID_* globals"
  assert_eq "id number" "12" "$WIT_ID_NUMBER"
else
  fail "accepts a linear id" "accept" "rejected"
fi

WIT_LINEAR_SCOPES='["acme/ENG"]'
assert_succeeds "declared scope accepted" "in" "out" \
  wit_linear_scope_in_scope "acme/ENG"
assert_fails "undeclared scope refused" "out" "in" \
  wit_linear_scope_in_scope "undeclared/elsewhere"

check_map() {
  local label="$1" status="$2" want="$3"
  (
    WIT_LINEAR_STATUS="$status"
    WIT_LINEAR_BODY=""
    wit_linear_require_ok "test" 2>/dev/null
  )
  assert_eq "$label" "$want" "$?"
}
check_map "200 → ok (0)" "200" "0"
check_map "401 → auth (4)" "401" "4"
check_map "403 → auth (4)" "403" "4"
check_map "404 → not-found (5)" "404" "5"
check_map "409 → conflict (7)" "409" "7"
check_map "429 → unavailable (8)" "429" "8"
check_map "503 → unavailable (8)" "503" "8"

write_binding() {
  jq -cn --argjson sub "$1" \
    '{schema_version:"1.0", provider:"linear", config:({lease_ttl_hours:24} + {"linear": $sub})}' \
    >"$FIX/binding.json"
}

config_rc() {
  write_binding "$1"
  WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" \
    bash -c 'source "$1/common.sh"; wit_need_linear_config' _ "$SCRIPT_DIR" >/dev/null 2>&1
  printf '%s' "$?"
}

config_err() {
  write_binding "$1"
  { WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" \
    bash -c 'source "$1/common.sh"; wit_need_linear_config' _ "$SCRIPT_DIR" >/dev/null; } 2>&1
}

GOOD='{"host":"api.linear.app","auth_env":"WIT_LINEAR_API_KEY","scopes":["acme/ENG"]}'

assert_eq "a well-formed binding is accepted" "0" "$(config_rc "$GOOD")"

assert_eq "missing host → exit 3" "3" \
  "$(config_rc "$(jq -c 'del(.host)' <<<"$GOOD")")"
assert_eq "missing auth_env → exit 3" "3" \
  "$(config_rc "$(jq -c 'del(.auth_env)' <<<"$GOOD")")"
assert_eq "missing scopes → exit 3" "3" \
  "$(config_rc "$(jq -c 'del(.scopes)' <<<"$GOOD")")"
assert_eq "scopes as a scalar string → exit 3" "3" \
  "$(config_rc "$(jq -c '.scopes = "acme/ENG"' <<<"$GOOD")")"
assert_eq "empty scopes array → exit 3" "3" \
  "$(config_rc "$(jq -c '.scopes = []' <<<"$GOOD")")"

for bad_host in "https://api.linear.app" "api.linear.app/path" "evil.example.com@api.linear.app" \
  "api.linear.app:8443" "api.linear.app " "-api.linear.app"; do
  assert_eq "host '$bad_host' refused as not-bare → exit 3" "3" \
    "$(config_rc "$(jq -c --arg h "$bad_host" '.host = $h' <<<"$GOOD")")"
done

bare_err="$(config_err "$(jq -c '.host = "https://api.linear.app"' <<<"$GOOD")")"
assert_contains "not-bare host names the reason" "$bare_err" "not a bare hostname"

PINNED="$(jq -c '.host_suffix = ".pinned.example"' <<<"$GOOD")"
assert_eq "host outside the binding's pin → exit 3" "3" "$(config_rc "$PINNED")"
pin_err="$(config_err "$PINNED")"
assert_contains "off-pin host names the pin and the opt-out" "$pin_err" "allow_custom_domain"
assert_eq "allow_custom_domain=true is the opt-out" "0" \
  "$(config_rc "$(jq -c '.allow_custom_domain = true' <<<"$PINNED")")"
assert_eq "a host matching the pin is accepted" "0" \
  "$(config_rc "$(jq -c '.host = "instance.pinned.example"' <<<"$PINNED")")"

DOTLESS="$(jq -c '.host_suffix = "mycompany.com"' <<<"$GOOD")"
assert_eq "dot-less pin still denies suffix confusion" "3" \
  "$(config_rc "$(jq -c '.host = "evilmycompany.com"' <<<"$DOTLESS")")"
assert_eq "and denies a hyphenated lookalike" "3" \
  "$(config_rc "$(jq -c '.host = "attacker-mycompany.com"' <<<"$DOTLESS")")"
assert_eq "a real subdomain under a dot-less pin is accepted" "0" \
  "$(config_rc "$(jq -c '.host = "api.mycompany.com"' <<<"$DOTLESS")")"
assert_eq "the apex itself is accepted" "0" \
  "$(config_rc "$(jq -c '.host = "mycompany.com"' <<<"$DOTLESS")")"

for bad_env in "FOO-BAR" "1FOO" "FOO BAR" "FOO;id" ""; do
  assert_eq "auth_env '${bad_env:-<empty>}' refused → exit 3" "3" \
    "$(config_rc "$(jq -c --arg e "$bad_env" '.auth_env = $e' <<<"$GOOD")")"
done

for bad_scope in '""' '"a b"' '"../../etc/passwd"' '"x;id"' '123' 'null'; do
  assert_eq "scope element $bad_scope refused → exit 3" "3" \
    "$(config_rc "$(jq -c --argjson s "[$bad_scope]" '.scopes = $s' <<<"$GOOD")")"
done

assert_eq "page_size 250 (the cap) is accepted" "0" \
  "$(config_rc "$(jq -c '.page_size = 250' <<<"$GOOD")")"
assert_eq "page_size 251 → exit 3" "3" \
  "$(config_rc "$(jq -c '.page_size = 251' <<<"$GOOD")")"
assert_eq "page_size 500 → exit 3" "3" \
  "$(config_rc "$(jq -c '.page_size = 500' <<<"$GOOD")")"
assert_contains "and the cap is named in the refusal" \
  "$(config_err "$(jq -c '.page_size = 500' <<<"$GOOD")")" "250"
assert_eq "page_size 0 is still refused → exit 3" "3" \
  "$(config_rc "$(jq -c '.page_size = 0' <<<"$GOOD")")"
assert_eq "a fractional page_size → exit 3" "3" \
  "$(config_rc "$(jq -c '.page_size = 12.5' <<<"$GOOD")")"
assert_eq "a non-numeric page_size → exit 3" "3" \
  "$(config_rc "$(jq -c '.page_size = "abc"' <<<"$GOOD")")"
assert_eq "a digit-string page_size is accepted, as elsewhere in the binding" "0" \
  "$(config_rc "$(jq -c '.page_size = "50"' <<<"$GOOD")")"

write_binding "$GOOD"
WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" \
  bash -c 'unset WIT_LINEAR_API_KEY; source "$1/common.sh"; wit_need_linear_config; wit_linear_token' \
  _ "$SCRIPT_DIR" >/dev/null 2>&1
assert_eq "unset credential env var → exit 4" "4" "$?"

MOCKDIR="$FIX/mock"
mkdir -p "$MOCKDIR"
cat >"$MOCKDIR/curl" <<'MOCK'
#!/usr/bin/env bash
# Record argv and the stdin config separately, then answer 200 with an empty object.
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$@" >"$d/argv.txt"
cat >"$d/stdin.txt" 2>/dev/null
printf '%s\n%s' '{}' '200'
MOCK
chmod +x "$MOCKDIR/curl"

write_binding "$GOOD"
SECRET="s3cr3t-linear-token-do-not-leak"
WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" \
  WIT_LINEAR_CURL="$MOCKDIR/curl" \
  WIT_LINEAR_API_KEY="$SECRET" \
  bash -c 'source "$1/common.sh"; wit_need_linear_config; wit_linear_http GET /probe' \
  _ "$SCRIPT_DIR" >/dev/null 2>&1
transport_rc=$?

assert_eq "mocked transport call succeeds" "0" "$transport_rc"
ARGV="$(cat "$MOCKDIR/argv.txt" 2>/dev/null)"
STDIN_CFG="$(cat "$MOCKDIR/stdin.txt" 2>/dev/null)"

EXPECT_HEADER="Authorization: $SECRET"

assert_not_contains "raw credential absent from curl argv" "$ARGV" "$SECRET"
assert_not_contains "built credential header absent from curl argv" "$ARGV" "$EXPECT_HEADER"
assert_contains "credential travels in the stdin config instead" "$STDIN_CFG" "$EXPECT_HEADER"
assert_contains "stdin config carries the Authorization header" "$STDIN_CFG" "Authorization"
assert_contains "curl is restricted to https" "$ARGV" "--proto"
assert_not_contains "redirects are not followed (-L)" "$ARGV" "-L"
assert_not_contains "redirects are not followed (--location)" "$ARGV" "--location"
assert_contains "request URL is https" "$STDIN_CFG" "https://api.linear.app/graphql/probe"

cat >"$MOCKDIR/curl" <<'MOCK'
#!/usr/bin/env bash
cat >/dev/null 2>&1
exit 7
MOCK
chmod +x "$MOCKDIR/curl"
WORK_ITEM_TRACKER_BINDING="$FIX/binding.json" \
  WIT_LINEAR_CURL="$MOCKDIR/curl" \
  WIT_LINEAR_API_KEY="$SECRET" \
  bash -c 'source "$1/common.sh"; wit_need_linear_config; wit_linear_http GET /probe' \
  _ "$SCRIPT_DIR" >/dev/null 2>&1
assert_eq "curl transport failure → exit 8" "8" "$?"

[[ $FAILED -eq 0 ]] || exit 1
