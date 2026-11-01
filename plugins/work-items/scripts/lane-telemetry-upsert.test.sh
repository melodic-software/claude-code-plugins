#!/usr/bin/env bash
# A fake `gh` on PATH stores comments and logs every argv, so the suite asserts
# each write's flag FORM (-F body=@ vs -f body=), not only its effect.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSERT="$SCRIPT_DIR/lane-telemetry-upsert.sh"
# The safe body dir must be the plugin's data dir, so the work dir's last segment
# names work-items.
ROOT="$(mktemp -d)"
WORK="$ROOT/work-items"
mkdir -p "$WORK"
trap 'chmod -R u+rwx "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n' "$1" >&2
}
check_rc() { # $1 expected $2 actual $3 label
  if [[ "$2" == "$1" ]]; then
    pass "$3"
  else
    fail "$3 (expected exit $1, got $2)"
  fi
}

# --- fake gh -----------------------------------------------------------------
BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/gh" <<'FAKE'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"$FAKE_GH_ARGV"
STATE="$FAKE_GH_STATE"
mkdir -p "$STATE"

method="GET"
endpoint=""
body_file=""
body_text=""
jqexpr=""
while (($#)); do
  case "$1" in
  api) shift ;;
  --method)
    method="$2"
    shift 2
    ;;
  -F | -f)
    case "$2" in
    body=@*) body_file="${2#body=@}" ;;
    body=*) body_text="${2#body=}" ;;
    *) : ;;
    esac
    shift 2
    ;;
  --jq)
    jqexpr="$2"
    shift 2
    ;;
  -*) shift ;;
  *)
    [[ -z "$endpoint" ]] && endpoint="$1"
    shift
    ;;
  esac
done

fails=" ${FAKE_GH_FAIL:-} "
path="${endpoint%%\?*}"
last="${path##*/}"
if [[ "$last" == "comments" && "$method" == "GET" ]]; then
  op=list
elif [[ "$last" == "comments" && "$method" == "POST" ]]; then
  op=post
elif [[ "$path" == */issues/comments/* && "$method" == "PATCH" ]]; then
  op=patch
elif [[ "$path" == */issues/comments/* && "$method" == "GET" ]]; then
  op=get
elif [[ "$path" == "user" ]]; then
  op=user
else
  op=unknown
fi
[[ "$fails" == *" $op "* ]] && exit 1

# A comment's author is its `.author` file, else the token's own login.
LOGIN="${FAKE_GH_LOGIN:-lane-bot}"
emit() {
  local author
  author="$(cat "$STATE/c-$1.author" 2>/dev/null || printf '%s' "$LOGIN")"
  jq -Rs --arg id "$1" --arg a "$author" '{id: ($id|tonumber), user: {login: $a}, body: .}' <"$2"
}

case "$op" in
user)
  # The real call runs `--jq '.login + " " + .type'`, so it prints both.
  printf '%s %s\n' "$LOGIN" "${FAKE_GH_TYPE:-User}"
  ;;
list)
  if [[ "${FAKE_GH_BAD_JSON:-0}" == "1" ]]; then
    printf 'not json at all\n'
    exit 0
  fi
  printf '['
  first=1
  for f in "$STATE"/c-*.body; do
    [[ -e "$f" ]] || continue
    b="${f##*/}"
    id="${b#c-}"
    id="${id%.body}"
    ((first)) || printf ','
    first=0
    emit "$id" "$f"
  done
  printf ']\n'
  ;;
post)
  next="$(cat "$STATE/next_id" 2>/dev/null || printf '100')"
  printf '%s' "$((next + 1))" >"$STATE/next_id"
  if [[ "${FAKE_GH_POST_DROP:-0}" != "1" ]]; then
    cp "$body_file" "$STATE/c-$next.body"
    # The token's real comment author; it differs from LOGIN only to model a wrong --app-slug.
    [[ -n "${FAKE_GH_POST_AS:-}" ]] && printf '%s' "$FAKE_GH_POST_AS" >"$STATE/c-$next.author"
    if [[ -n "$jqexpr" ]]; then
      emit "$next" "$STATE/c-$next.body" | jq -r "$jqexpr"
    else
      emit "$next" "$STATE/c-$next.body"
    fi
  else
    printf '{"id":%s,"user":{"login":"%s"},"body":""}\n' "$next" "$LOGIN" | jq -r "${jqexpr:-.}"
  fi
  ;;
patch)
  id="${path##*/}"
  target="$STATE/c-$id.body"
  [[ -e "$target" ]] || exit 1
  if [[ -n "$body_file" ]]; then
    if [[ "${FAKE_GH_PATCH_MANGLE:-0}" == "1" ]]; then
      tail -n +2 "$body_file" >"$target"
    elif [[ "${FAKE_GH_PATCH_STALE:-0}" == "1" ]]; then
      : # reports success and stores nothing: the comment keeps its earlier body
    elif [[ "${FAKE_GH_PATCH_LF:-0}" == "1" ]]; then
      tr -d '\r' <"$body_file" >"$target"
    else
      cp "$body_file" "$target"
    fi
  else
    printf '%s\n' "$body_text" >"$target"
  fi
  emit "$id" "$target"
  ;;
get)
  id="${path##*/}"
  target="$STATE/c-$id.body"
  [[ -e "$target" ]] || exit 1
  emit "$id" "$target"
  ;;
*)
  exit 1
  ;;
esac
FAKE
chmod +x "$BIN/gh"
PATH="$BIN:$PATH"
export PATH
# A passwd lookup stub: the home dir the safe-dir check reads, so a test can put
# it under the work dir without touching HOME.
cat >"$BIN/getent" <<'GETENT'
#!/usr/bin/env bash
printf 'tester:x:1000:1000::%s:/bin/sh\n' "${STUB_PASSWD_HOME:-/nonexistent-home}"
GETENT
chmod +x "$BIN/getent"

LANE=work-loop
INSTANCE=laptop-a
REPO=melodic-software/example-repo
ISSUE=42
SENT="<!-- harness-ops:lane-telemetry marker=work-items:$LANE@$INSTANCE -->"

run() { # sets RC, STDERR, STDOUT; args after the fixed five
  STDERR="$WORK/stderr.txt"
  STDOUT="$(bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
    --issue "$ISSUE" --body-file "$1" --body-dir "$WORK" "${@:2}" 2>"$STDERR")"
  RC=$?
}

fresh_state() {
  FAKE_GH_STATE="$WORK/state"
  FAKE_GH_ARGV="$WORK/argv.log"
  rm -rf "$FAKE_GH_STATE"
  mkdir -p "$FAKE_GH_STATE"
  : >"$FAKE_GH_ARGV"
  unset FAKE_GH_FAIL FAKE_GH_BAD_JSON FAKE_GH_POST_DROP FAKE_GH_PATCH_MANGLE FAKE_GH_PATCH_STALE FAKE_GH_PATCH_LF FAKE_GH_LOGIN FAKE_GH_TYPE FAKE_GH_POST_AS
  export FAKE_GH_STATE FAKE_GH_ARGV
}

write_body() { # $1 = path, $2 = marker sentinel to use
  printf '%s\ncycle=7 clean_streak=1 item_cap=2\n' "$2" >"$1"
}

GOOD="$WORK/body.md"
write_body "$GOOD" "$SENT"

# --- 1. fresh insert ---------------------------------------------------------
fresh_state
run "$GOOD"
check_rc 0 "$RC" "fresh insert exits 0"
if [[ -e "$FAKE_GH_STATE/c-100.body" ]] && grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-100.body"; then
  pass "fresh insert stores the composed body"
else
  fail "fresh insert did not store the body"
fi
if grep -q -- '--method POST .*-F body=@' "$FAKE_GH_ARGV"; then
  pass "create sends -F body=@ (never -f, which would post the literal path)"
else
  fail "create did not use -F body=@"
fi
if [[ "$STDOUT" == *"upserted comment 100"* ]]; then
  pass "fresh insert reports the canonical comment id"
else
  fail "fresh insert stdout: $STDOUT"
fi

# --- 2. update of an existing row -------------------------------------------
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
run "$GOOD"
check_rc 0 "$RC" "update of an existing row exits 0"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body"; then
  pass "update edits the existing comment in place"
else
  fail "update did not rewrite the existing comment"
fi
if grep -q -- '--method POST' "$FAKE_GH_ARGV"; then
  fail "update posted a second comment"
else
  pass "update posts no second comment"
fi
if grep -q -- '--method PATCH .*issues/comments/77 -F body=@' "$FAKE_GH_ARGV"; then
  pass "update sends -F body=@ to the existing comment"
else
  fail "update flag form"
fi

# --- 3. creation-race reconcile ---------------------------------------------
fresh_state
printf '%s\nracer one body\n' "$SENT" >"$FAKE_GH_STATE/c-9.body"
printf '%s\nracer two body\n' "$SENT" >"$FAKE_GH_STATE/c-31.body"
run "$GOOD"
check_rc 0 "$RC" "duplicate reconcile exits 0"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-9.body"; then
  pass "the LOWEST comment id is canonical and receives this cycle's body"
else
  fail "canonical selection picked the wrong comment"
fi
if grep -q 'Superseded duplicate' "$FAKE_GH_STATE/c-31.body"; then
  pass "the higher duplicate is tombstoned"
else
  fail "duplicate was not tombstoned"
fi
if grep -q -- 'issues/comments/31 -f body=Superseded' "$FAKE_GH_ARGV"; then
  pass "the tombstone sends -f body= (a literal string, not a file)"
else
  fail "tombstone flag form"
fi

# --- 4. a sibling instance's comment is never adopted or tombstoned ---------
fresh_state
printf '%s\nsibling lane body\n' "<!-- harness-ops:lane-telemetry marker=work-items:$LANE@laptop-b -->" \
  >"$FAKE_GH_STATE/c-5.body"
run "$GOOD"
check_rc 0 "$RC" "sibling instance present still exits 0"
if grep -q 'sibling lane body' "$FAKE_GH_STATE/c-5.body"; then
  pass "a sibling instance's comment is neither made canonical nor tombstoned"
else
  fail "sibling instance comment was written to"
fi

# --- 5. a body quoting the sentinel mid-text is not matched -----------------
fresh_state
printf 'chatter above\n%s\nquoted, not a telemetry comment\n' "$SENT" >"$FAKE_GH_STATE/c-6.body"
run "$GOOD"
check_rc 0 "$RC" "sentinel quoted mid-body still exits 0"
if grep -q 'chatter above' "$FAKE_GH_STATE/c-6.body"; then
  pass "lookup is a startswith on the full sentinel, not a contains"
else
  fail "a comment merely quoting the sentinel was adopted"
fi

# --- 5b. a sentinel comment another login wrote is never adopted -------------
# Anyone can paste the public sentinel. A foreign comment with a LOWER id would
# otherwise win the lowest-id canonical rule and take this cycle's state.
fresh_state
printf '%s\nforged durable state\n' "$SENT" >"$FAKE_GH_STATE/c-3.body"
printf 'mallory' >"$FAKE_GH_STATE/c-3.author"
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
run "$GOOD"
check_rc 0 "$RC" "a foreign sentinel comment beside the lane's own still exits 0"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body"; then
  pass "the lane's own comment stays canonical over a lower-id foreign one"
else
  fail "the lane's own comment did not receive this cycle's body"
fi
if grep -q 'forged durable state' "$FAKE_GH_STATE/c-3.body"; then
  pass "a foreign sentinel comment is neither written to nor tombstoned"
else
  fail "a foreign sentinel comment was written to"
fi

fresh_state
printf '%s\nforged durable state\n' "$SENT" >"$FAKE_GH_STATE/c-3.body"
printf 'mallory' >"$FAKE_GH_STATE/c-3.author"
run "$GOOD"
check_rc 0 "$RC" "a foreign sentinel comment alone still exits 0"
if grep -q -- '--method POST' "$FAKE_GH_ARGV" && grep -q 'forged durable state' "$FAKE_GH_STATE/c-3.body"; then
  pass "with only a foreign sentinel comment present, the lane creates its own"
else
  fail "a foreign-only sentinel comment was adopted instead of creating the lane's own"
fi

# Under an App installation token `gh api user` is refused; --app-slug names the bot.
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf 'lane-app[bot]' >"$FAKE_GH_STATE/c-77.author"
FAKE_GH_FAIL=user
export FAKE_GH_FAIL
run "$GOOD" --app-slug lane-app
check_rc 0 "$RC" "--app-slug resolves the identity when gh api user is refused"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body"; then
  pass "--app-slug adopts the App bot's own comment"
else
  fail "--app-slug did not adopt the bot-authored comment"
fi

# A Bot reported with no slug: the reported login plus [bot].
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf 'lane-app[bot]' >"$FAKE_GH_STATE/c-77.author"
FAKE_GH_LOGIN=lane-app FAKE_GH_TYPE=Bot
export FAKE_GH_LOGIN FAKE_GH_TYPE
run "$GOOD"
check_rc 0 "$RC" "a Bot reported by gh api user resolves to its [bot] login"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body"; then
  pass "the reported Bot login plus [bot] adopts the bot's own comment"
else
  fail "the reported Bot did not adopt its own comment"
fi

# Logins may carry underscores (enterprise managed users).
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf 'kyle_corp' >"$FAKE_GH_STATE/c-77.author"
FAKE_GH_LOGIN=kyle_corp
export FAKE_GH_LOGIN
run "$GOOD"
check_rc 0 "$RC" "a login with an underscore resolves"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body" && ! grep -q -- '--method POST' "$FAKE_GH_ARGV"; then
  pass "an underscore login adopts its own comment rather than posting a new one"
else
  fail "an underscore login did not adopt its own comment"
fi

# Resolution order: a User login wins over --app-slug; a Bot report yields to it.
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
run "$GOOD" --app-slug lane-app
check_rc 0 "$RC" "a User login with --app-slug still exits 0"
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body"; then
  pass "a User login wins over --app-slug"
else
  fail "--app-slug overrode a User login"
fi
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf 'lane-app[bot]' >"$FAKE_GH_STATE/c-77.author"
FAKE_GH_LOGIN=other-app FAKE_GH_TYPE=Bot
export FAKE_GH_LOGIN FAKE_GH_TYPE
run "$GOOD" --app-slug lane-app
if grep -q 'clean_streak=1' "$FAKE_GH_STATE/c-77.body"; then
  pass "--app-slug wins over a reported Bot login"
else
  fail "a reported Bot login overrode --app-slug"
fi

fresh_state
FAKE_GH_FAIL=user
export FAKE_GH_FAIL
run "$GOOD"
check_rc 15 "$RC" "an unresolved write identity exits 15"
if grep -qE -- '--method (POST|PATCH)' "$FAKE_GH_ARGV"; then
  fail "an unresolved write identity still wrote a comment"
else
  pass "an unresolved write identity writes nothing"
fi
fresh_state
run "$GOOD" --app-slug 'Not_A_Slug'
check_rc 15 "$RC" "a malformed --app-slug exits 15"

# A surviving userConfig placeholder is an unset key: it resolves exactly as if
# no slug were given (here, an unresolved identity under a refused gh api user).
fresh_state
FAKE_GH_FAIL=user
export FAKE_GH_FAIL
# shellcheck disable=SC2016 # the literal placeholder is the input under test
run "$GOOD" --app-slug '${user_config.lane_app_slug}'
check_rc 15 "$RC" "a placeholder --app-slug resolves as absent (unresolved identity, exit 15)"
if grep -q 'must be a GitHub App slug' "$STDERR"; then
  fail "a placeholder --app-slug was validated as a slug"
else
  pass "a placeholder --app-slug is not validated as a slug"
fi
fresh_state
FAKE_GH_FAIL="" FAKE_GH_LOGIN=lane-bot FAKE_GH_TYPE=User
export FAKE_GH_FAIL FAKE_GH_LOGIN FAKE_GH_TYPE
# shellcheck disable=SC2016 # the literal placeholder is the input under test
run "$GOOD" --app-slug '${user_config.lane_app_slug}'
check_rc 0 "$RC" "a placeholder --app-slug with a User login exits 0 as if no slug were given"

# A wrong --app-slug: the create lands under the token's real login.
fresh_state
FAKE_GH_FAIL=user FAKE_GH_POST_AS='real-app[bot]'
export FAKE_GH_FAIL FAKE_GH_POST_AS
run "$GOOD" --app-slug wrong-app
check_rc 15 "$RC" "a create posted under another login exits 15"
if grep -q -- '--method PATCH' "$FAKE_GH_ARGV"; then
  fail "a mismatched create went on to PATCH"
else
  pass "a mismatched create writes nothing further"
fi

# --- 6. usage refusals ------------------------------------------------------
fresh_state
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$GOOD" --body-dir "$WORK" --bogus >/dev/null 2>"$WORK/e.txt"
check_rc 2 "$?" "an unknown argument exits 2"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  >/dev/null 2>"$WORK/e.txt"
check_rc 2 "$?" "a missing --body-file exits 2"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  --body-file >/dev/null 2>"$WORK/e.txt"
check_rc 2 "$?" "a trailing flag with no value exits 2"
help_out="$(bash "$UPSERT" --help 2>/dev/null)"
check_rc 0 "$?" "--help exits 0"
if [[ "$help_out" == *"--body-file"* && "$help_out" == *"Exit codes"* ]]; then
  pass "--help prints the usage block and the exit-code table"
else
  fail "--help printed no usage block: $help_out"
fi

bash "$UPSERT" --lane babysit --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"
check_rc 3 "$?" "an unknown lane exits 3"

# --- 7. lane-instance refusals ----------------------------------------------
for bad in "Laptop-A" "-leading" "has_underscore" "has.dot"; do
  bash "$UPSERT" --lane "$LANE" --instance "$bad" --repo "$REPO" --issue "$ISSUE" \
    --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"
  check_rc 4 "$?" "lane instance '$bad' is rejected, never sanitized (exit 4)"
done
if grep -q 'refusing to build a marker' "$WORK/e.txt"; then
  pass "the instance refusal names what it refused to build"
else
  fail "instance refusal stderr: $(cat "$WORK/e.txt")"
fi
bash "$UPSERT" --lane "$LANE" --instance "aaaaaaaaaabbbbbbbbbbccccccccccddd" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"
check_rc 5 "$?" "a 33-character lane instance exits 5"

# A surviving userConfig placeholder means the key is unset, so it takes the
# stored random-id fallback rather than being validated as a literal id. The
# marker is public, so the fallback is never the hostname.
fresh_state
IDDIR="$WORK/iddir/work-items"
mkdir -p "$IDDIR"
write_body "$IDDIR/body.md" "$SENT"
bash "$UPSERT" --lane "$LANE" --instance '${user_config.lane_instance}' --repo "$REPO" \
  --issue "$ISSUE" --body-file "$IDDIR/body.md" --body-dir "$IDDIR" >/dev/null 2>"$WORK/e.txt"
STORED="$(cat "$IDDIR/lane-instance" 2>/dev/null)"
if [[ "$STORED" =~ ^lane-[0-9a-f]{8}$ ]] && grep -q "using the stored random id '$STORED'" "$WORK/e.txt"; then
  pass "a surviving userConfig placeholder falls back to a stored random id and logs it"
else
  fail "placeholder handling: stored '$STORED', stderr: $(cat "$WORK/e.txt")"
fi
HOST="$(hostname 2>/dev/null || uname -n)"
HOST_SANITIZED="$(printf '%s' "$HOST" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
if [[ -n "$STORED" && "$STORED" != "$HOST" && "$STORED" != "$HOST_SANITIZED" ]]; then
  pass "the fallback instance id is not the hostname"
else
  fail "the fallback instance id equals the hostname"
fi
write_body "$IDDIR/body.md" "<!-- harness-ops:lane-telemetry marker=work-items:$LANE@$STORED -->"
bash "$UPSERT" --lane "$LANE" --instance "" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$IDDIR/body.md" --body-dir "$IDDIR" >/dev/null 2>"$WORK/e.txt"
check_rc 0 "$?" "a second unset-instance run reuses the stored id and upserts"
if [[ "$(cat "$IDDIR/lane-instance")" == "$STORED" ]] && ! grep -rqF -- "$HOST_SANITIZED" "$FAKE_GH_STATE" "$FAKE_GH_ARGV"; then
  pass "the stored id is stable across runs and the hostname reaches no API call"
else
  fail "the stored id changed or the hostname reached the API"
fi

# --- 8. repo and issue refusals ---------------------------------------------
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "owner/repo/../../other/target" \
  --issue "$ISSUE" --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"
check_rc 6 "$?" "a traversal-shaped --repo exits 6 before any API call"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "../.." \
  --issue "$ISSUE" --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"
check_rc 6 "$?" "a dot-segment --repo exits 6 before any API call"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "4a2" \
  --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"
check_rc 7 "$?" "a non-numeric --issue exits 7"

# --- 9. missing prerequisites ------------------------------------------------
MINBIN="$WORK/minbin"
mkdir -p "$MINBIN"
# The wrappers take an ABSOLUTE-path shebang: a `#!/usr/bin/env bash` wrapper for
# `env` itself would be resolved through this same directory and fork-bomb.
minbin_add() {
  local t real
  for t in "$@"; do
    real="$(command -v "$t" 2>/dev/null)" || continue
    [[ -n "$real" ]] || continue
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$real" >"$MINBIN/$t"
    chmod +x "$MINBIN/$t"
  done
}
minbin_add bash cat head tail wc tr sort grep awk jq
if PATH="$MINBIN" bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"; then
  fail "gh absent should not succeed"
else
  check_rc 8 "$?" "gh absent from PATH exits 8"
fi
rm -f "$MINBIN/jq"
minbin_add gh
if PATH="$MINBIN" bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$WORK/e.txt"; then
  fail "jq absent should not succeed"
else
  check_rc 8 "$?" "jq absent from PATH exits 8"
fi

# --- 10. malformed body files ------------------------------------------------
fresh_state
run "$WORK/does-not-exist.md"
check_rc 9 "$RC" "a missing body file exits 9"
: >"$WORK/empty.md"
run "$WORK/empty.md"
check_rc 9 "$RC" "an empty body file exits 9"
printf '@/tmp/telemetry.txt\n' >"$WORK/atpath.md"
run "$WORK/atpath.md"
check_rc 9 "$RC" "a body that is a literal @path exits 9"
if grep -q 'do not re-run blind' "$STDERR"; then
  pass "the @path refusal says nothing was written and not to re-run blind"
else
  fail "@path refusal stderr: $(cat "$STDERR")"
fi
printf 'cycle=7 clean_streak=1 item_cap=2\n' >"$WORK/nosentinel.md"
run "$WORK/nosentinel.md"
check_rc 10 "$RC" "a body with no sentinel line exits 10"
printf '%s\nshort\n' "$SENT" >"$WORK/thin.md"
run "$WORK/thin.md"
check_rc 10 "$RC" "a body carrying under 16 payload bytes exits 10"
printf '\x00\x01garbage not markdown at all\n' >"$WORK/binary.md"
run "$WORK/binary.md"
check_rc 10 "$RC" "a binary-garbage body exits 10"
if [[ -z "$(grep -c . "$FAKE_GH_ARGV" 2>/dev/null | tr -d '0')" ]]; then
  pass "every body refusal made zero API calls"
else
  fail "a body refusal reached the API: $(cat "$FAKE_GH_ARGV")"
fi
# A CRLF body clears the gate: the sentinel is compared as a byte prefix and the
# floor is measured below line 1, so the line ending never decides the verdict.
fresh_state
printf '%s\r\ncycle=7 clean_streak=1 item_cap=2\r\n' "$SENT" >"$WORK/crlf.md"
run "$WORK/crlf.md"
check_rc 0 "$RC" "a CRLF body clears the sentinel gate"

# --- 11. lookup failures are fail-closed ------------------------------------
fresh_state
FAKE_GH_FAIL=list
export FAKE_GH_FAIL
run "$GOOD"
check_rc 11 "$RC" "a failed comment lookup exits 11"
if grep -q -- '--method POST' "$FAKE_GH_ARGV"; then
  fail "a failed lookup posted a comment"
else
  pass "a failed lookup writes nothing (fail closed)"
fi

fresh_state
FAKE_GH_BAD_JSON=1
export FAKE_GH_BAD_JSON
run "$GOOD"
check_rc 11 "$RC" "an unparsable comment list exits 11 rather than reading as empty"
if grep -q -- '--method POST' "$FAKE_GH_ARGV"; then
  fail "unparsable JSON was treated as an empty list and posted a duplicate"
else
  pass "unparsable JSON never takes the insert path"
fi

# --- 12. a create that cannot be re-found -----------------------------------
fresh_state
FAKE_GH_POST_DROP=1
export FAKE_GH_POST_DROP
run "$GOOD"
check_rc 12 "$RC" "a create that is not re-found exits 12"
if grep -q 'UNREPORTED' "$STDERR"; then
  pass "the not-re-found branch tells the lane to carry UNREPORTED forward"
else
  fail "not-re-found stderr: $(cat "$STDERR")"
fi

# --- 13. a failed write ------------------------------------------------------
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
FAKE_GH_FAIL="patch"
export FAKE_GH_FAIL
run "$GOOD"
check_rc 13 "$RC" "a failed PATCH exits 13"
if grep -q 'old cycle body here' "$FAKE_GH_STATE/c-77.body"; then
  pass "a failed PATCH leaves the previous cycle's body in place"
else
  fail "failed PATCH mutated the comment"
fi

# --- 14. a write that verifies badly ----------------------------------------
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf '%s\nsibling duplicate body\n' "$SENT" >"$FAKE_GH_STATE/c-88.body"
FAKE_GH_PATCH_MANGLE=1
export FAKE_GH_PATCH_MANGLE
run "$GOOD"
check_rc 14 "$RC" "a write whose read-back is not well-formed exits 14"
if grep -q 'sibling duplicate body' "$FAKE_GH_STATE/c-88.body"; then
  pass "an unverified cycle never tombstones a racing session's comment"
else
  fail "duplicates were superseded on an unverified write"
fi

# A PATCH that reports success while the comment keeps the previous cycle's body:
# that body is well-formed telemetry, so only a comparison with THIS cycle's body
# file catches it.
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf '%s\nsibling duplicate body\n' "$SENT" >"$FAKE_GH_STATE/c-88.body"
FAKE_GH_PATCH_STALE=1
export FAKE_GH_PATCH_STALE
run "$GOOD"
check_rc 14 "$RC" "a write that leaves the previous cycle's well-formed body in place exits 14"
if grep -q 'sibling duplicate body' "$FAKE_GH_STATE/c-88.body"; then
  pass "a stale read-back never tombstones a racing session's comment"
else
  fail "duplicates were superseded on a stale read-back"
fi

# The comparison tolerates line endings: a CRLF body file read back as LF verifies.
fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
printf '%s\r\ncycle=7 clean_streak=1 item_cap=2\r\n' "$SENT" >"$WORK/crlf2.md"
FAKE_GH_PATCH_LF=1
export FAKE_GH_PATCH_LF
run "$WORK/crlf2.md"
check_rc 0 "$RC" "a CRLF body stored with LF line endings still verifies"

fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
FAKE_GH_FAIL="get"
export FAKE_GH_FAIL
run "$GOOD"
check_rc 14 "$RC" "a read-back that cannot be performed exits 14"

# --- 15. body-file containment and the leak scan ----------------------------
# A path outside the safe dir is refused before any read: the file is mode 000,
# so a read would fail differently, and the refusal makes zero API calls.
fresh_state
OUTSIDE="$ROOT/outside"
mkdir -p "$OUTSIDE"
printf 'PRIVATE-KEY-MATERIAL\n' >"$OUTSIDE/secret.txt"
chmod 000 "$OUTSIDE/secret.txt"
run "$OUTSIDE/secret.txt"
check_rc 16 "$RC" "a body file outside the safe dir is refused (exit 16)"
if grep -q 'must resolve under the safe body dir' "$STDERR" && ! grep -q 'PRIVATE-KEY-MATERIAL' "$STDERR" && [[ ! -s "$FAKE_GH_ARGV" ]]; then
  pass "the outside-path refusal names the rule, echoes no content and makes no API call"
else
  fail "outside-path refusal: $(cat "$STDERR")"
fi
chmod 600 "$OUTSIDE/secret.txt"
run "$WORK/../outside/secret.txt"
check_rc 16 "$RC" "a .. traversal out of the safe dir is refused (exit 16)"
ln -s "$OUTSIDE/secret.txt" "$WORK/link.md"
run "$WORK/link.md"
check_rc 16 "$RC" "a symlink leaf escaping the safe dir is refused (exit 16)"
if ! grep -q 'PRIVATE-KEY-MATERIAL' "$STDERR" && [[ ! -s "$FAKE_GH_ARGV" ]]; then
  pass "the symlink refusal echoes no content and makes no API call"
else
  fail "symlink refusal reached content or the API"
fi
rm -f "$WORK/link.md"
STDERR="$WORK/stderr.txt"
env -u CLAUDE_PLUGIN_DATA bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" >/dev/null 2>"$STDERR"
check_rc 16 "$?" "no --body-dir and no work-items CLAUDE_PLUGIN_DATA exits 16"
FOREIGN="$WORK/codex-data"
mkdir -p "$FOREIGN"
cp "$GOOD" "$FOREIGN/body.md"
CLAUDE_PLUGIN_DATA="$FOREIGN" bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$FOREIGN/body.md" >/dev/null 2>"$STDERR"
check_rc 16 "$?" "another plugin's CLAUDE_PLUGIN_DATA is no safe body dir (exit 16)"

# A credential-shaped body is withheld whole, never posted, never echoed. The
# fake token is assembled at run time so no token-shaped literal is tracked.
fresh_state
FAKE_TOKEN="ghp""_$(printf 'Z%.0s' {1..36})"
printf '%s\ncycle=7 note=%s\n' "$SENT" "$FAKE_TOKEN" >"$WORK/leak.md"
run "$WORK/leak.md"
check_rc 17 "$RC" "a body carrying a credential-shaped token is refused (exit 17)"
if grep -q "leak-scan rule 'GitHub token'; a real credential must be rotated" "$STDERR" && ! grep -qF -- "$FAKE_TOKEN" "$STDERR" && ! grep -qF -- "$FAKE_TOKEN" <<<"$STDOUT" && [[ ! -s "$FAKE_GH_ARGV" ]]; then
  pass "the leak refusal names the rule, never prints the token, and makes no API call"
else
  fail "leak refusal: $(grep -c . "$FAKE_GH_ARGV") API calls, stderr: $(sed "s/$FAKE_TOKEN/<token>/" "$STDERR")"
fi
printf '%s\ncycle=7 password="hunter2hunter2"\n' "$SENT" >"$WORK/assign.md"
run "$WORK/assign.md"
check_rc 17 "$RC" "a body carrying a plain secret assignment is withheld too (exit 17)"

# A caller-chosen --body-dir must be the plugin's data dir: one whose last
# segment does not name work-items, or that is the home dir or an ancestor of it,
# contains nothing, so it is refused before the body is read.
fresh_state
mkdir -p "$ROOT/elsewhere"
cp "$GOOD" "$ROOT/elsewhere/body.md"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$ROOT/elsewhere/body.md" --body-dir "$ROOT/elsewhere" >/dev/null 2>"$STDERR"
check_rc 16 "$?" "a --body-dir that is not the work-items data dir is refused (exit 16)"
STUB_PASSWD_HOME="$WORK/user" HOME=/nonexistent-other bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" --body-dir "$WORK" >/dev/null 2>"$STDERR"
check_rc 16 "$?" "a --body-dir that is an ancestor of the home dir is refused (exit 16)"
if grep -q 'home dir' "$STDERR" && [[ ! -s "$FAKE_GH_ARGV" ]]; then
  pass "the home-ancestor refusal names the rule and makes no API call"
else
  fail "home-ancestor refusal: $(cat "$STDERR")"
fi

# CDPATH cannot redirect a relative body path: with the cwd outside and a CDPATH
# that holds a same-named dir inside the safe dir, the outside file is refused.
fresh_state
mkdir -p "$ROOT/cwd/sub" "$WORK/sub"
cp "$GOOD" "$ROOT/cwd/sub/body.md"
cp "$GOOD" "$WORK/sub/body.md"
(cd "$ROOT/cwd" && CDPATH="$WORK" bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file sub/body.md --body-dir "$WORK" >/dev/null 2>"$STDERR")
check_rc 16 "$?" "CDPATH cannot make an outside relative body path pass (exit 16)"

# A symlinked or malformed stored lane-instance is refused and never echoed.
fresh_state
LIDIR="$ROOT/lid/work-items"
mkdir -p "$LIDIR"
write_body "$LIDIR/body.md" "$SENT"
printf 'lane-0000beef\n' >"$ROOT/lid/elsewhere-id"
ln -s "$ROOT/lid/elsewhere-id" "$LIDIR/lane-instance"
bash "$UPSERT" --lane "$LANE" --instance "" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$LIDIR/body.md" --body-dir "$LIDIR" >/dev/null 2>"$STDERR"
check_rc 4 "$?" "a symlinked stored lane-instance is refused (exit 4)"
rm -f "$LIDIR/lane-instance"
printf 'Not_A-Valid.ID-sentinel-text\n' >"$LIDIR/lane-instance"
bash "$UPSERT" --lane "$LANE" --instance "" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$LIDIR/body.md" --body-dir "$LIDIR" >/dev/null 2>"$STDERR"
check_rc 4 "$?" "a malformed stored lane-instance is refused (exit 4)"
if grep -q 'stored lane-instance is malformed' "$STDERR" && ! grep -q 'Not_A-Valid' "$STDERR" && [[ ! -s "$FAKE_GH_ARGV" ]]; then
  pass "the malformed-id refusal never echoes the stored value and makes no API call"
else
  fail "malformed-id refusal: $(cat "$STDERR")"
fi

# A home path in the body is withheld like a credential: the comment is public.
fresh_state
# A fake home path, assembled at run time so no user path is tracked.
FAKE_HOME="/ho""me/alice"
printf '%s\ncycle=7 worktree=%s/worktrees/app\n' "$SENT" "$FAKE_HOME" >"$WORK/homepath.md"
run "$WORK/homepath.md"
check_rc 17 "$RC" "a body naming a home path is withheld (exit 17)"
if grep -q "names a machine path or hostname (home path); remove it" "$STDERR" && ! grep -q 'rotate' "$STDERR" && ! grep -qF -- "$FAKE_HOME" "$STDERR"; then
  pass "the home-path refusal names the rule, never the path"
else
  fail "home-path refusal: $(cat "$STDERR")"
fi

# A fleet-hostname-shaped instance passes the shape check but would publish the
# hostname in the marker, so it is refused up front with its own code, before
# any API call, and the message never echoes it.
fresh_state
FLEET_INSTANCE="melo-""lap-001"
FLEET_SENT="<!-- harness-ops:lane-telemetry marker=work-items:$LANE@$FLEET_INSTANCE -->"
write_body "$WORK/fleet.md" "$FLEET_SENT"
SAVED_INSTANCE="$INSTANCE"
INSTANCE="$FLEET_INSTANCE"
run "$WORK/fleet.md"
INSTANCE="$SAVED_INSTANCE"
check_rc 18 "$RC" "a fleet-hostname-shaped instance is refused (exit 18)"
if grep -q "withheld from the public marker" "$STDERR" && ! grep -q "body withheld" "$STDERR" && ! grep -qF -- "$FLEET_INSTANCE" "$STDERR" && [[ ! -s "$FAKE_GH_ARGV" ]]; then
  pass "the hostname-instance refusal blames the instance, not the body, never echoes it, and makes no API call"
else
  fail "hostname-instance refusal: $(cat "$STDERR")"
fi

# A GitHub-hosted runner's home path reveals nothing, so it is not withheld.
fresh_state
printf '%s\ncycle=7 log=/ho''me/runner/work/app/app/run.log\n' "$SENT" >"$WORK/runner.md"
run "$WORK/runner.md"
check_rc 0 "$RC" "a body naming only the hosted-runner home path is posted"

# The plugin name is checked again on the canonical dir: a symlink named for the
# plugin that points at another dir is refused.
fresh_state
mkdir -p "$ROOT/config"
cp "$GOOD" "$ROOT/config/body.md"
ln -s "$ROOT/config" "$ROOT/work-items-x"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$ROOT/work-items-x/body.md" --body-dir "$ROOT/work-items-x" >/dev/null 2>"$STDERR"
check_rc 16 "$?" "a --body-dir symlink named for the plugin but resolving elsewhere is refused (exit 16)"

if ((FAILED == 0)); then
  printf 'all lane-telemetry-upsert tests passed\n'
  exit 0
fi
printf '%s test(s) failed\n' "$FAILED" >&2
exit 1
