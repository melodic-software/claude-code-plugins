#!/usr/bin/env bash
# Tests for telemetry-upsert.sh against a PATH-stub `gh` that keeps the issue's
# comments in a JSON file and applies the script's own --jq programs with real jq.
# SKIPs (exit 0) when jq is unavailable.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/telemetry-upsert.sh"
type -P jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed" >&2
  exit 0
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Knobs: STUB_FAIL=list|post|patch|get fails that call; STUB_READBACK replaces
# the body a single-comment GET returns.
db="$STUB_DIR/comments.json"
method=GET url="" jqexpr="" body=""
while (($#)); do
  case "$1" in
  api | --paginate) ;;
  -X) method="$2"; shift ;;
  --jq) jqexpr="$2"; shift ;;
  -F) body="$(cat "${2#body=@}")"; shift ;;
  -f) body="${2#body=}"; shift ;;
  *) url="$1" ;;
  esac
  shift
done
echo "$method $url" >>"$STUB_DIR/calls.log"
case "$method $url" in
"GET repos/"*"/comments?per_page=100")
  [[ "${STUB_FAIL:-}" == list ]] && exit 1
  jq -r "$jqexpr" "$db" ;;
"POST repos/"*"/comments")
  [[ "${STUB_FAIL:-}" == post ]] && exit 1
  jq --arg b "$body" '. + [{id: ((map(.id) | max // 100) + 1), body: $b}]' "$db" >"$db.new" && mv "$db.new" "$db" ;;
"PATCH repos/"*"/issues/comments/"*)
  [[ "${STUB_FAIL:-}" == patch ]] && exit 1
  id="${url##*/}"
  jq --arg b "$body" --argjson id "$id" 'map(if .id == $id then .body = $b else . end)' "$db" >"$db.new" && mv "$db.new" "$db" ;;
"GET repos/"*"/issues/comments/"*)
  [[ "${STUB_FAIL:-}" == get ]] && exit 1
  if [[ -n "${STUB_READBACK:-}" ]]; then printf '%s\n' "$STUB_READBACK"; exit 0; fi
  jq -r --argjson id "${url##*/}" ".[] | select(.id == \$id) | $jqexpr" "$db" ;;
*) echo "stub: unexpected call $method $url" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gh"

SENT='<!-- harness-ops:lane-telemetry marker=source-control:babysit-loop@lap-1 -->'
PAYLOAD='cycle: 7
{"schema":"source-control/babysit-loop-state@2","cycle":7}'
FAILED=0 N=0
check() { # name expected actual
  N=$((N + 1))
  if [[ "$3" == "$2" ]]; then printf 'PASS: [%d] %s\n' "$N" "$1"; else
    printf 'FAIL: [%d] %s\n  expected: %q\n  got:      %q\n' "$N" "$1" "$2" "$3" >&2
    FAILED=$((FAILED + 1))
  fi
}
# setup <comments-json> [body]: fresh comment store and body file
setup() {
  export STUB_DIR="$TMP/case$N"
  rm -rf "$STUB_DIR" && mkdir -p "$STUB_DIR"
  printf '%s\n' "$1" >"$STUB_DIR/comments.json"
  : >"$STUB_DIR/calls.log"
  printf '%s\n' "${2-$PAYLOAD}" >"$STUB_DIR/body.txt"
}
run() {
  PATH="$TMP/bin:$PATH" bash "$SCRIPT" --repo acme/widgets --issue 5 --instance "${INST-lap-1}" \
    --body-file "$STUB_DIR/body.txt" >/dev/null 2>"$STUB_DIR/err"
}
body_of() { jq -r --argjson id "$1" '.[] | select(.id == $id) | .body' "$STUB_DIR/comments.json"; }
writes() { grep -cE '^(POST|PATCH) ' "$STUB_DIR/calls.log"; }

# 1. No comment yet: created, then verified.
setup '[]'
run
check "create: exit 0" 0 "$?"
check "create: stored body is sentinel + payload" "$SENT"$'\n'"$PAYLOAD" "$(body_of 101)"

# 2. Existing sentinel comment holding last cycle's body: updated in place.
setup "$(jq -n --arg b "$SENT"$'\n''cycle: 6 old body here' '[{id: 40, body: "unrelated"}, {id: 41, body: $b}]')"
run
check "update: exit 0" 0 "$?"
check "update: comment 41 holds this cycle's body" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"
check "update: no POST" 0 "$(grep -c '^POST' "$STUB_DIR/calls.log")"

# 3. Read-back returns a well-formed telemetry body that is not this cycle's (a
#    PATCH that stored the previous body): unconfirmed, exit 6.
setup "$(jq -n --arg b "$SENT"$'\n''cycle: 6 old body here' '[{id: 41, body: $b}]')"
STUB_READBACK="$SENT"$'\n''cycle: 6 old body here' run
check "stale read-back: exit 6" 6 "$?"

# 4. Read-back that differs only by CRLF line endings still verifies.
setup '[]'
STUB_READBACK="$(printf '%s\n%s\n' "$SENT" "$PAYLOAD" | sed 's/$/\r/')" run
check "CRLF read-back: exit 0" 0 "$?"

# 5. Lookup fails: exit 5, nothing written.
setup '[]'
STUB_FAIL='list' run
check "lookup failure: exit 5" 5 "$?"
check "lookup failure: no write" 0 "$(writes)"

# 6. POST fails: exit 5.
setup '[]'
STUB_FAIL='post' run
check "create failure: exit 5" 5 "$?"

# 7. PATCH fails: exit 5.
setup "$(jq -n --arg b "$SENT"$'\n''cycle: 6 old body here' '[{id: 41, body: $b}]')"
STUB_FAIL='patch' run
check "patch failure: exit 5" 5 "$?"

# 8. Read-back GET fails: exit 6.
setup '[]'
STUB_FAIL='get' run
check "read-back failure: exit 6" 6 "$?"

# 9. Invalid instance id: exit 3 before any gh call.
setup '[]'
INST='Bad_Id' run
check "invalid instance: exit 3" 3 "$?"
check "invalid instance: no gh call" 0 "$(wc -l <"$STUB_DIR/calls.log" | tr -d ' ')"

# 10. A literal @path body: exit 3 before any gh call.
setup '[]' '@/tmp/telemetry.md'
run
check "@path body: exit 3" 3 "$?"
check "@path body: no gh call" 0 "$(wc -l <"$STUB_DIR/calls.log" | tr -d ' ')"

# 11. Two sentinel comments: the lower id is canonical, the other tombstoned.
setup "$(jq -n --arg b "$SENT"$'\n''cycle: 6 old body here' '[{id: 9, body: $b}, {id: 5, body: $b}]')"
run
check "duplicates: exit 0" 0 "$?"
check "duplicates: comment 5 is canonical" "$SENT"$'\n'"$PAYLOAD" "$(body_of 5)"
check "duplicates: comment 9 tombstoned" "Superseded duplicate - canonical telemetry comment: 5" "$(body_of 9)"

# 12. A body file that already opens with the sentinel is not double-prefixed.
setup '[]' "$SENT"$'\n'"$PAYLOAD"
run
check "pre-prefixed body: exit 0" 0 "$?"
check "pre-prefixed body: one sentinel" "$SENT"$'\n'"$PAYLOAD" "$(body_of 101)"

# 13. An unsubstituted ${user_config.…} placeholder falls back to the hostname.
cat >"$TMP/bin/hostname" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$STUB_HOST"
STUB
chmod +x "$TMP/bin/hostname"
setup '[]'
# shellcheck disable=SC2016 # the literal placeholder is the input under test
INST='${user_config.lane_instance}' STUB_HOST='Melo_Lap.001' run
check "placeholder instance: exit 0" 0 "$?"
check "placeholder instance: hostname-derived marker" \
  '<!-- harness-ops:lane-telemetry marker=source-control:babysit-loop@melo-lap-001 -->'$'\n'"$PAYLOAD" "$(body_of 101)"

# 14. A hostname too long for an instance id: exit 3 before any gh call.
setup '[]'
# shellcheck disable=SC2016
INST='${user_config.lane_instance}' STUB_HOST="$(printf 'h%.0s' {1..40})" run
check "over-length hostname: exit 3" 3 "$?"
check "over-length hostname: no gh call" 0 "$(wc -l <"$STUB_DIR/calls.log" | tr -d ' ')"

# 15. Under 16 payload bytes below the sentinel: exit 3 before any gh call.
setup '[]' "$SENT"$'\n''short'
run
check "short body: exit 3" 3 "$?"
check "short body: no gh call" 0 "$(wc -l <"$STUB_DIR/calls.log" | tr -d ' ')"

# 16. gh not on PATH: exit 4.
setup '[]'
PATH=/nonexistent "$BASH" "$SCRIPT" --repo acme/widgets --issue 5 --instance lap-1 \
  --body-file "$STUB_DIR/body.txt" >/dev/null 2>&1
check "gh missing: exit 4" 4 "$?"

((FAILED == 0)) || {
  echo "$FAILED of $N checks failed" >&2
  exit 1
}
echo "all $N checks passed"
