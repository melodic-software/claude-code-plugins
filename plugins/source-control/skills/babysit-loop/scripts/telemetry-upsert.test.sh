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
# the body a single-comment GET returns; STUB_USER is the `GET user` response
# (`fail` makes the call fail, as it does under an App installation token);
# STUB_AUTHOR is the login the token's writes land under.
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
"GET user")
  [[ "${STUB_USER:-}" == fail ]] && exit 1
  user='{"login":"lane-op","type":"User"}'
  jq -r "$jqexpr" <<<"${STUB_USER:-$user}" ;;
"GET repos/"*"/comments?per_page=100")
  [[ "${STUB_FAIL:-}" == list ]] && exit 1
  jq -r "$jqexpr" "$db" ;;
"POST repos/"*"/comments")
  [[ "${STUB_FAIL:-}" == post ]] && exit 1
  jq --arg b "$body" --arg a "${STUB_AUTHOR:-lane-op}" \
    '. + [{id: ((map(.id) | max // 100) + 1), body: $b, user: {login: $a}}]' "$db" >"$db.new" && mv "$db.new" "$db"
  jq -r ".[-1] | $jqexpr" "$db" ;;
"PATCH repos/"*"/issues/comments/"*)
  [[ "${STUB_FAIL:-}" == patch ]] && exit 1
  id="${url##*/}"
  jq --arg b "$body" --argjson id "$id" 'map(if .id == $id then .body = $b else . end)' "$db" >"$db.new" && mv "$db.new" "$db" ;;
"DELETE repos/"*"/issues/comments/"*)
  [[ "${STUB_FAIL:-}" == delete ]] && exit 1
  jq --argjson id "${url##*/}" 'map(select(.id != $id))' "$db" >"$db.new" && mv "$db.new" "$db" ;;
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
run() { # extra arguments pass through to the script
  PATH="$TMP/bin:$PATH" bash "$SCRIPT" --repo acme/widgets --issue 5 --instance "${INST-lap-1}" \
    --body-file "$STUB_DIR/body.txt" "$@" >"$STUB_DIR/out" 2>"$STUB_DIR/err"
}
read_state() {
  PATH="$TMP/bin:$PATH" bash "$SCRIPT" --repo acme/widgets --issue 5 --instance lap-1 --read \
    >"$STUB_DIR/out" 2>"$STUB_DIR/err"
}
# c <id> <body> [author]: one comment object, written by lane-op unless named
c() { jq -n --argjson id "$1" --arg b "$2" --arg a "${3:-lane-op}" '{id: $id, body: $b, user: {login: $a}}'; }
OLD="$SENT"$'\n''cycle: 6 old body here'
FOREIGN="$SENT"$'\n''{"writer_nonce":"intruder","heartbeat_at":"2099-01-01T00:00:00Z"}'
body_of() { jq -r --argjson id "$1" '.[] | select(.id == $id) | .body' "$STUB_DIR/comments.json"; }
writes() { grep -cE '^(POST|PATCH) ' "$STUB_DIR/calls.log"; }

# 1. No comment yet: created, then verified.
setup '[]'
run
check "create: exit 0" 0 "$?"
check "create: stored body is sentinel + payload" "$SENT"$'\n'"$PAYLOAD" "$(body_of 101)"

# 2. Existing sentinel comment holding last cycle's body: updated in place.
setup "[$(c 40 unrelated), $(c 41 "$OLD")]"
run
check "update: exit 0" 0 "$?"
check "update: comment 41 holds this cycle's body" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"
check "update: no POST" 0 "$(grep -c '^POST' "$STUB_DIR/calls.log")"

# 3. Read-back returns a well-formed telemetry body that is not this cycle's (a
#    PATCH that stored the previous body): unconfirmed, exit 6.
setup "[$(c 41 "$OLD")]"
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
setup "[$(c 41 "$OLD")]"
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
setup "[$(c 9 "$OLD"), $(c 5 "$OLD")]"
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

# 17. A foreign-author sentinel comment with a lower id is never adopted: this
#     identity's own comment stays canonical and the foreign one is not touched.
setup "[$(c 3 "$FOREIGN" outsider), $(c 41 "$OLD")]"
run
check "foreign lower id: exit 0" 0 "$?"
check "foreign lower id: own comment 41 is canonical" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"
check "foreign lower id: foreign comment untouched" "$FOREIGN" "$(body_of 3)"
check "foreign lower id: no write to it" 0 "$(grep -c 'comments/3$' "$STUB_DIR/calls.log")"

# 18. Only a foreign sentinel comment exists: this identity creates its own.
setup "[$(c 3 "$FOREIGN" outsider)]"
run
check "foreign only: exit 0" 0 "$?"
check "foreign only: own comment 4 created" "$SENT"$'\n'"$PAYLOAD" "$(body_of 4)"
check "foreign only: foreign comment untouched" "$FOREIGN" "$(body_of 3)"

# 19. App installation token: GET user fails and --app-slug names the writer; a
#     lower-id sentinel comment by a user account is foreign to it.
setup "[$(c 3 "$FOREIGN" lane-op), $(c 41 "$OLD" 'lane-app[bot]')]"
STUB_USER=fail STUB_AUTHOR='lane-app[bot]' run --app-slug lane-app
check "app token: exit 0" 0 "$?"
check "app token: own bot comment 41 is canonical" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"
check "app token: user-authored comment untouched" "$FOREIGN" "$(body_of 3)"

# 20. GET user fails and no --app-slug: identity unresolved, exit 5, nothing written.
setup "[$(c 41 "$OLD")]"
STUB_USER=fail run
check "no identity: exit 5" 5 "$?"
check "no identity: no write" 0 "$(writes)"

# 20b. A wrong --app-slug: the POST lands under another login, so the comment it
#      created is deleted, nothing else is written, exit 5 naming the real author.
setup "[$(c 3 "$FOREIGN" outsider)]"
STUB_USER=fail STUB_AUTHOR='real-app[bot]' run --app-slug wrong-app
check "wrong slug: exit 5" 5 "$?"
check "wrong slug: the created comment 4 is deleted" "DELETE repos/acme/widgets/issues/comments/4" \
  "$(grep '^DELETE' "$STUB_DIR/calls.log")"
check "wrong slug: only the foreign comment remains" "3" "$(jq -r 'map(.id) | join(",")' "$STUB_DIR/comments.json")"
check "wrong slug: no PATCH" 0 "$(grep -c '^PATCH' "$STUB_DIR/calls.log")"
check "wrong slug: error names the real author" 1 "$(grep -c "posted as 'real-app\[bot\]'" "$STUB_DIR/err")"

# 20c. The cleanup DELETE fails: still exit 5, and the error says to remove it by hand.
setup '[]'
STUB_USER=fail STUB_AUTHOR='real-app[bot]' STUB_FAIL=delete run --app-slug wrong-app
check "wrong slug, delete fails: exit 5" 5 "$?"
check "wrong slug, delete fails: says remove by hand" 1 "$(grep -c 'deleting comment 101 failed' "$STUB_DIR/err")"

# 21. GET user reports a bot: its [bot] login is the identity.
setup "[$(c 3 "$FOREIGN"), $(c 41 "$OLD" 'lane-app[bot]')]"
STUB_USER='{"login":"lane-app","type":"Bot"}' run
check "bot user: exit 0" 0 "$?"
check "bot user: own bot comment 41 is canonical" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"
check "bot user: user-authored comment untouched" "$FOREIGN" "$(body_of 3)"

# 22. --read prints this identity's canonical body, skipping a lower-id foreign
#     comment, and writes nothing.
setup "[$(c 3 "$FOREIGN" outsider), $(c 41 "$OLD")]"
read_state
check "read: exit 0" 0 "$?"
check "read: prints own canonical body" "$OLD" "$(cat "$STUB_DIR/out")"
check "read: no write" 0 "$(writes)"

# 23. --read with only a foreign comment: unclaimed, empty output, exit 0.
setup "[$(c 3 "$FOREIGN" outsider)]"
read_state
check "read unclaimed: exit 0" 0 "$?"
check "read unclaimed: empty output" "" "$(cat "$STUB_DIR/out")"

# 24. --read fails closed: a failed lookup, read, or identity is exit 5 with no
#     output, never the empty "unclaimed" answer.
for knob in list get user; do
  setup "[$(c 41 "$OLD")]"
  if [[ "$knob" == user ]]; then STUB_USER=fail read_state; else STUB_FAIL="$knob" read_state; fi
  check "read, $knob fails: exit 5" 5 "$?"
  check "read, $knob fails: no output" "" "$(cat "$STUB_DIR/out")"
done

# 25. An invalid --app-slug: exit 3 before any gh call.
setup '[]'
run --app-slug 'bad"slug'
check "invalid slug: exit 3" 3 "$?"
check "invalid slug: no gh call" 0 "$(wc -l <"$STUB_DIR/calls.log" | tr -d ' ')"

# 25b. A surviving ${user_config.lane_app_slug} placeholder or an empty slug is
#      absent: with GET user failing, the identity stays unresolved (exit 5).
# shellcheck disable=SC2016 # the literal placeholder is the input under test
for slug in '${user_config.lane_app_slug}' ''; do
  setup "[$(c 41 "$OLD")]"
  STUB_USER=fail run --app-slug "$slug"
  check "absent slug '$slug': exit 5, identity unresolved" 5 "$?"
  check "absent slug '$slug': no write" 0 "$(writes)"
done

# 25c. A placeholder slug is not fatal when GET user reports a User.
setup "[$(c 41 "$OLD")]"
# shellcheck disable=SC2016 # the literal placeholder is the input under test
run --app-slug '${user_config.lane_app_slug}'
check "placeholder slug, user token: exit 0" 0 "$?"
check "placeholder slug, user token: comment 41 updated" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"

# 26. An Enterprise Managed User login (underscore shortcode) is a valid identity.
setup "[$(c 3 "$FOREIGN" outsider), $(c 41 "$OLD" 'jane_acme')]"
STUB_USER='{"login":"jane_acme","type":"User"}' run
check "EMU login: exit 0" 0 "$?"
check "EMU login: own comment 41 is canonical" "$SENT"$'\n'"$PAYLOAD" "$(body_of 41)"

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
