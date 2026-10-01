#!/usr/bin/env bash
# Tests for lane-telemetry-upsert.sh. `gh` is stubbed by a fake on PATH that
# keeps comments in a state directory and logs every argv it is called with, so
# the suite asserts the flag FORM of each write (-F body=@ for create/update,
# -f body= for the tombstone) and not only its effect. Nothing here reaches the
# network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSERT="$SCRIPT_DIR/lane-telemetry-upsert.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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
  --jq) shift 2 ;;
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
else
  op=unknown
fi
[[ "$fails" == *" $op "* ]] && exit 1

emit() { jq -Rs --arg id "$1" '{id: ($id|tonumber), body: .}' <"$2"; }

case "$op" in
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
    emit "$next" "$STATE/c-$next.body"
  else
    printf '{"id":%s,"body":""}\n' "$next"
  fi
  ;;
patch)
  id="${path##*/}"
  target="$STATE/c-$id.body"
  [[ -e "$target" ]] || exit 1
  if [[ -n "$body_file" ]]; then
    if [[ "${FAKE_GH_PATCH_MANGLE:-0}" == "1" ]]; then
      tail -n +2 "$body_file" >"$target"
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

LANE=work-loop
INSTANCE=laptop-a
REPO=melodic-software/example-repo
ISSUE=42
SENT="<!-- claude-ops:lane-telemetry marker=work-items:$LANE@$INSTANCE -->"

run() { # sets RC, STDERR, STDOUT; args after the fixed five
  STDERR="$WORK/stderr.txt"
  STDOUT="$(bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
    --issue "$ISSUE" --body-file "$1" 2>"$STDERR")"
  RC=$?
}

fresh_state() {
  FAKE_GH_STATE="$WORK/state"
  FAKE_GH_ARGV="$WORK/argv.log"
  rm -rf "$FAKE_GH_STATE"
  mkdir -p "$FAKE_GH_STATE"
  : >"$FAKE_GH_ARGV"
  unset FAKE_GH_FAIL FAKE_GH_BAD_JSON FAKE_GH_POST_DROP FAKE_GH_PATCH_MANGLE
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
printf '%s\nsibling lane body\n' "<!-- claude-ops:lane-telemetry marker=work-items:$LANE@laptop-b -->" \
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

# --- 6. usage refusals ------------------------------------------------------
fresh_state
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "$ISSUE" \
  --body-file "$GOOD" --bogus >/dev/null 2>"$WORK/e.txt"
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
  --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"
check_rc 3 "$?" "an unknown lane exits 3"

# --- 7. lane-instance refusals ----------------------------------------------
for bad in "Laptop-A" "-leading" "has_underscore" "has.dot"; do
  bash "$UPSERT" --lane "$LANE" --instance "$bad" --repo "$REPO" --issue "$ISSUE" \
    --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"
  check_rc 4 "$?" "lane instance '$bad' is rejected, never sanitized (exit 4)"
done
if grep -q 'refusing to build a marker' "$WORK/e.txt"; then
  pass "the instance refusal names what it refused to build"
else
  fail "instance refusal stderr: $(cat "$WORK/e.txt")"
fi
bash "$UPSERT" --lane "$LANE" --instance "aaaaaaaaaabbbbbbbbbbccccccccccddd" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"
check_rc 5 "$?" "a 33-character lane instance exits 5"

# A surviving userConfig placeholder means the key is unset, so it takes the
# hostname fallback rather than being validated as a literal id.
fresh_state
bash "$UPSERT" --lane "$LANE" --instance '${user_config.lane_instance}' --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"
if grep -q 'assuming the sanitized hostname' "$WORK/e.txt"; then
  pass "a surviving userConfig placeholder falls back to the hostname and logs the assumption"
else
  fail "placeholder handling stderr: $(cat "$WORK/e.txt")"
fi

# --- 8. repo and issue refusals ---------------------------------------------
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "owner/repo/../../other/target" \
  --issue "$ISSUE" --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"
check_rc 6 "$?" "a traversal-shaped --repo exits 6 before any API call"
bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" --issue "4a2" \
  --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"
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
minbin_add bash cat head tail wc tr sort grep hostname awk jq
if PATH="$MINBIN" bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"; then
  fail "gh absent should not succeed"
else
  check_rc 8 "$?" "gh absent from PATH exits 8"
fi
rm -f "$MINBIN/jq"
minbin_add gh
if PATH="$MINBIN" bash "$UPSERT" --lane "$LANE" --instance "$INSTANCE" --repo "$REPO" \
  --issue "$ISSUE" --body-file "$GOOD" >/dev/null 2>"$WORK/e.txt"; then
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

fresh_state
printf '%s\nold cycle body here\n' "$SENT" >"$FAKE_GH_STATE/c-77.body"
FAKE_GH_FAIL="get"
export FAKE_GH_FAIL
run "$GOOD"
check_rc 14 "$RC" "a read-back that cannot be performed exits 14"

if ((FAILED == 0)); then
  printf 'all lane-telemetry-upsert tests passed\n'
  exit 0
fi
printf '%s test(s) failed\n' "$FAILED" >&2
exit 1
